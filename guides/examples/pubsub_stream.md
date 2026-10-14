# PubSub Streams with Bounded Ownership

Use a long-running SSE endpoint when a page should receive updates produced by
other requests or jobs. `StarView.Stream` owns the receive loop, disconnect probes,
and optional per-tab claim. Your application owns authentication, topic selection,
and subscription cleanup.

This is separate from a short `handle_event/3` response. Open the stream from an
ordinary route so authentication and the stream claim finish before SSE starts.

## Set up PubSub and optional deduplication

A Phoenix application normally supervises its PubSub server already. Add the
stream registry when each authenticated user/tab should have one active stream:

```elixir
children = [
  {Phoenix.PubSub, name: MyApp.PubSub},
  {StarView.StreamRegistry, grace_ms: 1_000}
]
```

Keep a public `tabId` signal in the root document. `tab-id` is the HTML spelling
Datastar camelizes; an underscore prefix would prevent transmission:

```heex
<body data-signals:tab-id="sessionStorage.getItem('_sv_tab') || (() => { const id = crypto.randomUUID(); sessionStorage.setItem('_sv_tab', id); return id; })()">
```

Open the endpoint with a constant, local URL in the page:

```heex
<div id="counter-events" data-init="@get('/counter/events', {filterSignals: {exclude: /(^|\.)_|^csrf$/}})">
  <output id="counter-live-value" data-text="$count"></output>
</div>
```

The initial page must initialize `$count`. GET here subscribes to updates; it
must not perform a business mutation. Datastar is loaded by your application's
asset entrypoint. The server SDK does not supply a licensed Datastar Pro client.
The filter keeps the public `csrf` signal out of this read-only GET's query and
retains Datastar's default client-only signal exclusion. `tabId` is still sent.
If you do not filter it, redact the full `datastar` query value from access logs;
adding a CSRF header by itself would not remove the signal from the URL.

## Complete Phoenix stream controller

Route `GET /counter/events` through the application's authenticated pipeline.
It must assign the authenticated `current_user`, including its stable `id`.
Use the ordinary controller entrypoint, not a dispatched StarView event:

```elixir
scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]
  get "/counter/events", CounterStreamController, :show
end
```

`:require_authenticated_user` is the application's authentication pipeline;
replace that name with your own pipeline that assigns `current_user`.

```elixir
defmodule MyAppWeb.CounterStreamController do
  use MyAppWeb, :controller

  alias Phoenix.PubSub
  alias StarView.Stream

  require Logger

  def show(conn, _params) do
    case Stream.open(conn, key: {:counter, conn.assigns.current_user.id}) do
      {:ok, conn} -> run_stream(conn)
      {:error, conn} -> conn
    end
  end

  defp run_stream(conn) do
    try do
      Stream.run(conn,
        connect: &subscribe/1,
        info: &handle_update/2,
        disconnect: &disconnected/1,
        idle_check: 30_000
      )
    after
      PubSub.unsubscribe(MyApp.PubSub, topic(conn))
    end
  end

  defp subscribe(conn) do
    :ok = PubSub.subscribe(MyApp.PubSub, topic(conn))
    conn
  end

  defp handle_update({:counter_changed, count}, conn) when is_integer(count),
    do: StarView.patch_signals(conn, %{count: count})

  defp handle_update(:stop_counter_stream, conn), do: {:halt, conn}
  defp handle_update(_message, conn), do: conn

  defp disconnected(_conn), do: Logger.debug("Counter stream ended")

  defp topic(conn), do: "counter:" <> to_string(conn.assigns.current_user.id)
end
```

An authorized producer publishes the resulting saved value to that user's topic:

```elixir
Phoenix.PubSub.broadcast(MyApp.PubSub, "counter:" <> to_string(user.id), {:counter_changed, count})
```

This example renders updates, not their persistence. The producer's action must
authorize and commit its own business operation before broadcasting. Topics are
derived from the authenticated user, not a submitted browser topic or user id.

## Know what owns cleanup

`open/2` returns `{:ok, conn}` only after SSE starts. On `{:error, conn}`, it
returns a halted ordinary HTTP response: 400 for bad signal input, 413 for an
oversized raw/query document, or 503 for an unavailable/refused keyed claim.
No subscription has run on that path.

`run/2` threads current conns through `connect` and `info`; `info` may return
`{:halt, conn}`. The library synchronously releases the exact stream claim before
the normal `disconnect` callback. It also releases that claim if a callback raises.
The disconnect callback is **not** an exception finalizer. The example's `after`
unsubscribes once on normal completion or exceptions; `disconnected/1` only
records a normal stream end.

Claim release uses the stored generation, so cleanup for an old connection
cannot remove a newer stream. Takeover messages are tagged with that generation;
a stale message cannot end the next request on a reused HTTP/1.1 keep-alive
process. This also works without requiring HTTP/2 owners to trap exits. Slow
cleanup happens after release, so an old handover timer cannot kill the reused
process. Keep callbacks bounded so an active request can respond to takeover.

## Probes are deadline-driven

`idle_check:` is a positive millisecond interval, defaulting to 30,000. It sets
a fixed deadline for an SSE comment probe, not a timeout that restarts after
every PubSub message. Busy streams still probe the adapter. Bandit's HTTP/2
flow-control messages are left for the transport instead of passed to `info`.

Expected disconnected writes (`:closed`, `:econnreset`, `:epipe`) end normally.
`:timeout`, invalid callback return values, and application/formatting exceptions
propagate after claim release. The `after` block still cleans the subscription.
Do not hide all exceptions as disconnects.

Deduplication requires both a server-chosen `key:` and a usable `tabId`: a
non-whitespace UTF-8 string of 1–256 bytes. Missing/invalid tab ids intentionally
fall back to unkeyed SSE. Omit `key:` to use unkeyed streams without a registry.
This is stream ownership, not authorization, durable delivery, or replay. Load a
fresh authorized snapshot when opening/reconnecting if missed events matter.

See [the ownership API](../core/stream_deduplication.md) for manual loops. Manual users
of `start_stream/2` must release the claim themselves; prefer `open/2` and `run/2`
for generation-aware teardown.
