# Manual Plug Endpoints and Request Boundaries

Use the low-level API when your endpoint needs to inspect input or decide an
HTTP status before committing to SSE. It does not require Phoenix components,
Igniter, or a stream registry.

## Fetch, validate, then start

This complete Plug accepts a bounded counter document. It returns a normal HTTP
error for malformed input and starts streaming only after application validation.

```elixir
defmodule MyApp.RawCounterEndpoint do
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: "POST"} = conn, _opts) do
    case StarView.Signals.fetch(conn, max_bytes: 8_192) do
      {:ok, signals, conn} -> increment(conn, signals)
      {:error, reason, conn} -> StarView.Signals.send_error(conn, reason)
    end
  end

  def call(conn, _opts) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "Use POST")
    |> halt()
  end

  defp increment(conn, %{"count" => count})
       when is_integer(count) and count >= 0 and count < 1_000_000 do
    conn
    |> StarView.start()
    |> StarView.patch_signals(%{count: count + 1})
  end

  defp increment(conn, _signals), do: StarView.Signals.send_error(conn, :invalid_signals)
end
```

Route it behind authentication and CSRF middleware if the application uses
cookies or protects the counter. This example changes browser UI state only;
an actual saved update must run through the application's authorized action.

Both `StarView.Signals.fetch/2` and its facade `StarView.fetch_signals/2` return
the updated connection in **both** result shapes. Keep that returned conn. Reading
a raw body advances the transport, and fetch stores the decoded object in
`body_params` for subsequent consumers. Retaining the original conn can reread an
already-consumed body or lose populated params. Route path params remain the
route identity; a signal named `module` cannot overwrite the resolved path param.

| Input | Result before SSE |
| --- | --- |
| JSON object such as `{"count": 1}` | `{:ok, signals, conn}` |
| Missing GET `datastar` query | Empty signal map |
| Empty raw request body | Empty signal map; validate required fields yourself |
| JSON array, scalar, `null`, malformed JSON, or empty `datastar=` | HTTP 400 when passed to `Signals.send_error/2` |
| Raw body or query JSON exceeds `max_bytes` | HTTP 413 |

The default raw/query limit is 1,000,000 bytes; `max_bytes` must be a positive
integer. A previously parsed JSON object has no original byte size to measure.
Configure `Plug.Parsers`' `length:` limit too. Parsing and business validation
are separate: an object containing the wrong keys is still a valid object.

GET and DELETE read JSON from the `datastar` query parameter; other methods
read the body. The compatibility `StarView.read_signals/1` returns only a map
and raises on bad input. Prefer fetch whenever middleware still needs the conn.

## Authentication and CSRF happen before streaming

Put session fetching, user resolution, and route access checks before dispatch.
For Phoenix's browser pipeline, the relevant order is:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug MyAppWeb.FetchCurrentUser
  plug StarView.Plug.RenameCsrfParam
  plug :protect_from_forgery
end

pipeline :authenticated_counter do
  plug MyAppWeb.RequireCounterUser
end

scope "/", MyAppWeb do
  pipe_through [:browser, :authenticated_counter]
  post "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

`FetchCurrentUser` and `RequireCounterUser` represent your application's user
resolver and route gate; StarView does not supply an identity provider. A normal
Phoenix endpoint already runs `Plug.Parsers` before the router. Include a JSON
parser and an appropriate size limit there rather than adding a second parser.

The page's non-underscore `csrf` signal carries the session token. The generated
layout supplies it. `RenameCsrfParam` runs before Phoenix's CSRF check and handles
body signals and GET/DELETE query signals. When only query/params hold a token
and the raw body is still unfetched, v0.4.0 places the token in `x-csrf-token`
without consuming the body. An explicit existing header remains authoritative.
See [CSRF](../core/csrf.md) for precedence and query-log considerations.

## Authorize each operation too

A successful page mount does not authorize a later event. Browser ids, roles,
tenant names, and counters are submitted input. Resolve the user and tenant
from trusted request context and ask the application's action/policy to authorize
the operation again.

Inside a Phoenix StarView event, the dispatcher has already sent status 200.
Use the page's existing error state when authorization or validation fails:

```elixir
def handle_event("save", %{"record_id" => id, "values" => values}, conn) do
  result =
    MyApp.Records.save(id, values,
      actor: conn.assigns.current_user,
      tenant: conn.assigns.tenant
    )

  case result do
    {:ok, record} -> conn |> Plug.Conn.assign(:record, record) |> patch_element(&record_card/1)
    {:error, :forbidden} -> signal(conn, :save_error, "You cannot edit this record.")
    {:error, _} -> signal(conn, :save_error, "The record could not be saved.")
  end
end
```

`MyApp.Records.save/3` is an application integration boundary, not a StarView
API. Its contract must perform validation and authorization before writing. An
Ash application can implement it with a named action and explicit actor/tenant.
Do not substitute a client-supplied tenant for `conn.assigns.tenant`.

After SSE begins, `put_status`, `send_resp`, cookie/session writes, and an HTTP
redirect cannot replace the response. `StarView.redirect/2` sends a client-side
script; it does not set a session cookie. Authentication exchanges should finish
with a normal form POST and HTTP redirect before streaming, as the
[magic-link auth generator](../phoenix/auth.md) does.

## Choose the correct dispatcher callback

| Dispatcher | Target selection | Handler arguments |
| --- | --- | --- |
| `StarView.Dispatch` | Controller marked by `use StarView` | `handle_event(event, signals, conn)` |
| `StarView.Plug.Dispatch` | Explicit `modules:` allowlist | `handle_event(conn, event, signals)` |

Both fetch and validate signal objects before starting SSE by default. The
allowlisted Plug has `start: false` for handlers that must make their own
pre-stream decisions:

```elixir
post "/ds/:module/:event", StarView.Plug.Dispatch,
  modules: [MyApp.CounterEvents], start: false
```

Such a handler must call `StarView.start/1` itself before patching. It can return
an HTTP 403 before starting instead. Do not mix callback orders or start an SSE
response twice. For long-running subscriptions, use a separate ordinary endpoint
and [the stream lifecycle](pubsub_stream.md).
