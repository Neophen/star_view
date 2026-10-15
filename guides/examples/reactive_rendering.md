# Reactive Rendering After Scoped Invalidations

A live page can render its current state whenever something relevant changes,
instead of translating every event into a hand-written DOM update. Producers
broadcast that *something changed*; the stream re-reads authorized state and
patches one stable region. Bursts collapse into one render, and identical HTML
is not sent again.

This builds on [PubSub streams](pubsub_stream.md): the same loop, probes,
ownership and cleanup apply. Nothing here adds a process, database hook or
global "refresh everything" signal.

## The flow

1. `handle_connect/2` subscribes to topics derived from trusted conn assigns.
2. Producers commit an authorized change, then broadcast an identifier, such as
   `{:order_changed, order_id}`. The message carries no rendered data.
3. `handle_info/2` calls `StarView.invalidate/1`. Invalidations already queued are
   coalesced into one pending render.
4. `handle_refresh/1` reloads state for the conn's actor and tenant and patches
   the region with `only_changed: true`.

`handle_refresh/1` also runs once right after `handle_connect/2`. That snapshot
covers changes made between the page render and the subscription, and anything
missed while the browser was disconnected or the tab was hidden.

## Page example

```elixir
defmodule MyAppWeb.OrdersPage do
  use StarView.Page, refresh_interval: 50

  alias MyAppWeb.Components.StarView.Layout
  alias Phoenix.PubSub

  def mount(conn, _params) do
    case MyApp.Orders.authorized_list(conn.assigns.current_scope) do
      {:ok, orders} -> assign(conn, :orders, orders)
      {:error, :forbidden} -> conn |> Plug.Conn.send_resp(403, "Forbidden") |> Plug.Conn.halt()
    end
  end

  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <section data-init={connect()} data-on:online__window={connect()}>
        <.orders orders={@orders} />
      </section>
    </Layout.app>
    """
  end

  def handle_connect(conn, _params) do
    :ok = PubSub.subscribe(MyApp.PubSub, topic(conn))
    conn
  end

  def handle_info({:order_changed, _order_id}, conn), do: StarView.invalidate(conn)
  def handle_info(_message, conn), do: conn

  def handle_refresh(conn) do
    case MyApp.Orders.authorized_list(conn.assigns.current_scope) do
      {:ok, orders} -> patch(conn, &orders/1, [orders: orders], key: :orders, only_changed: true)
      {:error, :forbidden} -> {:halt, conn}
    end
  end

  def handle_disconnect(conn), do: PubSub.unsubscribe(MyApp.PubSub, topic(conn))

  def orders(assigns) do
    ~H"""
    <ul id="orders">
      <li :for={order <- @orders} id={"order-#{order.id}"}>{order.number}</li>
    </ul>
    """
  end

  defp topic(conn), do: "orders:" <> to_string(conn.assigns.current_scope.organization.id)
end
```

Replace `MyApp.Orders` with your application's business API. The route
pipeline assigns `current_scope` and gates access to both page and stream
requests before SSE starts; mount does not run on stream requests.
The topic is derived from the authenticated scope,
never from a browser signal. `handle_refresh/1` re-authorizes on every render,
so a revoked user stops receiving data and the stream halts.

The example uses `connect()` so a deliberate halt stays terminal. If the page
must also recover from clean stream endings, choose the
[explicit retry policy](../phoenix/pages.md) for that read resource. With
`retry: :always`, even a forbidden refresh that halts would reconnect; a request
gate must recheck access before opening SSE and can return a terminal response
(such as HTTP 204) when the read resource has ended.

## Plain `StarView.Stream`

Controllers use the same loop with `:render`:

```elixir
Stream.run(conn,
  connect: &subscribe/1,
  info: &invalidate_on_change/2,
  render: &render_orders/1,
  render_interval: 50
)
```

`StarView.Stream.invalidate/1` (also `StarView.invalidate/1`) raises unless the
conn belongs to the currently running stream with a `:render` callback. A conn
kept after `run/2` returns, including the one given to a disconnect callback,
cannot schedule a render. Pages call it qualified; it is not imported, so an
existing local `invalidate/1` keeps compiling.
`render_on_connect: false` disables the initial snapshot.

## Timing

`render_interval` (page option `:refresh_interval`) is the minimum number of
milliseconds between render starts. The wait uses a timer, so the loop keeps
receiving messages and probing during it. Renders run inside the stream loop:
keep them bounded and their reads cheap, because a slow render delays probes
and takeover handling. Pending timers and render messages are removed when the
stream ends normally or raises, so a reused keep-alive process starts clean.

## Skipping unchanged patches

`only_changed: true` needs an explicit `:key` and an idempotent mode
(`:outer`, `:inner` or `:replace`). A patch is skipped only when its HTML,
selector, mode, namespace, view-transition setting and SSE metadata all match the last patch
sent under that key on the current stream. Append, prepend, before, after and
remove raise, because repeating them changes the page.

Fingerprints are SHA-256 digests. Each stream tracks up to 64 keys; patches
for later keys always send. A reconnect starts a new stream with no
fingerprints, so its first render is always sent. Outside an active
`StarView.Stream.run/2`, for example in an event response, `only_changed`
patches are always sent.

The stream remembers what it sent, not what the browser shows. Any other
element patch or removal on the same stream, including `execute_script/3`,
clears every remembered key, so the next keyed patch is sent again. The stream
cannot see changes from event responses, other streams or tabs, raw
`StarView.send/4` events, or browser code. Use `only_changed` only for a region
this stream owns exclusively, and update that region from events by
invalidating rather than patching it directly. Give each key its own
non-overlapping region: two keys that target the same element, or one nested
inside the other, can skip a patch the page needs. Use one key for the outer
region instead.

## Preserve browser drafts

A refresh morphs the patched region. Keep it below any element whose
`data-signals` would reset drafts, such as the layout's `<main>`. Bind draft
inputs with `data-bind`, and initialize component signals with the
only-if-missing modifier (`data-signals__ifmissing`) so a refresh does not
overwrite what the user typed. Skipping unchanged HTML also avoids needless
morphs while someone is typing.
