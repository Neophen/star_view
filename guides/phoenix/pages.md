# Pages, streams and shared components

The optional page layer, added in v0.5.0, colocates a page's HEEx template,
events and stream callbacks. It uses the same bounded signals, dispatcher,
transport errors and stream ownership as the functional core. Existing
controller integrations continue to work; adopting pages is optional.

The page/component/routing design adapts [dstar](https://github.com/ricotrevisan/dstar)
under its MIT license. StarView uses its own shared stream lifecycle.

## A complete page

Put the route inside your existing authenticated browser pipeline. The pipeline
must fetch the session/actor, run `StarView.Plug.RenameCsrfParam` before
`Plug.CSRFProtection`, and resolve trusted tenant context where needed:

```elixir
import StarView.Router

scope "/", MyAppWeb do
  pipe_through :browser
  star_view "/counter", CounterPage
end
```

```elixir
defmodule MyAppWeb.CounterPage do
  use StarView.Page
  alias MyAppWeb.Components.StarView.Layout

  @impl StarView.Page
  def mount(conn, _params), do: assign(conn, count: 0)

  @impl StarView.Page
  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <div data-signals:count={@count}>
        <h1 data-text="$count"></h1>
        <span id="history">No changes yet</span>
        <button id="increment" data-on:click={event("increment")}>+1</button>
        <button id="reset" data-on:click={event("reset")}>Reset</button>
      </div>
    </Layout.app>
    """
  end

  @impl StarView.Page
  def handle_event("increment", %{"count" => count}, %{method: "POST"} = conn)
      when is_integer(count) and count >= 0 and count < 1_000_000 do
    conn |> patch_signals(%{count: count + 1}) |> patch(&history/1, last: count + 1)
  end

  def handle_event("reset", _signals, %{method: "POST"} = conn) do
    conn |> patch_signals(%{count: 0}) |> patch(&history/1, last: 0)
  end

  def handle_event(_event, _signals, conn), do: conn

  defp history(assigns) do
    ~H"""
    <span id="history">Last: {@last}</span>
    """
  end
end
```

The example counter is browser UI state. Database writes belong in authorized
application actions with the actor and tenant from the conn; never authorize
using submitted IDs alone. Mount runs only for the GET page, so authorization
in mount does not authorize later events or stream connections.

`star_view/2` adds GET rendering, POST streaming and `/_event/:event` dispatch.
The route explicitly selects the page; it does not use a client module signal.
`_event` is reserved below that path. SSE starts before `handle_event/3`, so
handlers return the conn and patch it without calling `StarView.start/1`.
Missing event/connect callbacks return 404. Invalid object signals return 400,
oversized raw/query signals return 413, before any callback or SSE starts.

Event routes default to POST. Declare additional CSRF-protected methods explicitly:

```elixir
star_view "/counter", CounterPage, event_methods: [:post, :put, :patch, :delete]
star_view "/reports", ReportsPage, get_events: true
```

The first example selects unsafe event methods; the second explicitly permits
read-only GET for one page. Still guard mutation clauses by method: GET bypasses
CSRF protection. Enabling GET must never make a write clause reachable through it.
Router options and their method/module lists are literal values; module
attributes, variables and sigils are not evaluated as options. Use a literal
keyword list and ordinary module aliases.
The browser derives a page-local URL from `location.pathname`; path parameters
need no extra assigns. Event names are percent-encoded literal segments. Empty
names and exact `.`/`..` segments raise. Action values still need HTML attribute
escaping; HEEx does that automatically.

```elixir
StarView.Page.Helpers.event("remove:123", verb: :delete)
StarView.Page.Helpers.event("save", opts: "{retryMaxCount: 5}")
```

`:opts` is trusted developer JavaScript text, emitted verbatim. Never build it
from browser signals or untrusted records. Use `StarView.JSON.encode!/1` for
literal values in custom expressions.

## One assign API

`use StarView.Page` imports `StarView.Page.Assigns` in place of Phoenix's assign
family. `assign/2,3`, `assign_new/3` and `update/3` act on Plug conns in callbacks,
and delegate to Phoenix for assigns maps in components. `patch/3,4` adds missing
HEEx change tracking when rendering a function component directly.

## Streaming pages

```elixir
defmodule MyAppWeb.DashboardPage do
  use StarView.Page, idle_check: 15_000
  alias MyAppWeb.Components.StarView.Layout

  @impl StarView.Page
  def mount(conn, _params), do: assign(conn, orders: 0)

  @impl StarView.Page
  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <div data-signals:orders={@orders} data-init={connect()}>
        <span id="order-count" data-text="$orders"></span>
      </div>
    </Layout.app>
    """
  end

  @impl StarView.Page
  def handle_connect(conn, _params) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "orders")
    conn
  end

  @impl StarView.Page
  def handle_info({:order_count, count}, conn) when is_integer(count) and count >= 0,
    do: patch_signals(conn, %{orders: count})

  def handle_info(:done, conn), do: {:halt, conn}

  @impl StarView.Page
  def handle_disconnect(conn) do
    Phoenix.PubSub.unsubscribe(MyApp.PubSub, "orders")
    conn
  end
end
```

`connect/0,1` opens POST streaming with unlimited reconnect attempts by default.
Use `include_search: true` to carry query parameters to `handle_connect/2`.
The library fetches signals and starts SSE before connect. It probes on a fixed
`:idle_check` deadline, even during busy PubSub traffic. Closed/reset writes end
normally; timeouts and application exceptions propagate.

Return `{:halt, conn}` to end normally. Unmatched `handle_info/2` callback heads
are logged and ignored; errors inside a matched clause propagate. You can omit
`handle_info/2` entirely for a stream that only needs liveness.

Define `stream_key(conn)` from trusted actor/route context to opt into keyed
replacement. This needs supervised `StarView.StreamRegistry` and a usable,
non-underscore `tabId` signal. Without a tab ID the stream opens unkeyed; a
refused keyed claim returns 503 before subscribing. See
[stream ownership](../core/stream_deduplication.md).

`handle_disconnect/1` runs once after exact claim release on normal ends,
takeover and exceptions. It receives the latest conn returned successfully by
a callback, or the opening conn if connect never returned. Use this for
subscriptions/resources; request processes can survive a stream under HTTP/1
keep-alive. If cleanup also fails while handling an existing exception, cleanup
is logged and the original exception is preserved. Forced process kills cannot
run application cleanup; process-owned subscriptions still disappear on death.

`mix star_view.setup.stream_page` generates `/stream-demo`, a supervised PubSub
ticker, the page, and router/CSRF wiring. The generated page unsubscribes in
`handle_disconnect/1`. Remove both demo modules and the ticker child when finished.

## Shared components with events

```elixir
defmodule MyAppWeb.DetailDrawer do
  use StarView.Component

  def drawer(assigns) do
    ~H"""
    <div id="detail-drawer">
      <input id="drawer-title" data-bind:title data-on:change={event("change_title:#{@item.id}")} />
    </div>
    """
  end

  def handle_event("change_title:" <> _id, %{"title" => title}, %{method: "POST"} = conn)
      when is_binary(title) and byte_size(title) <= 200 do
    # Authorize any real write with trusted actor/tenant context before patching.
    patch_signals(conn, %{saved: true})
  end

  def handle_event(_event, _signals, conn), do: conn
end
```

Embed the drawer as an ordinary function component. `StarView.Component` marks
its module dispatchable through `StarView.Dispatch`; it adds no process or
server state. Wire the component base explicitly:

```elixir
import StarView.Router
star_view_components "/ds"
```

The installer POST route also dispatches components with default POST events.
For a custom base or scoped application path, set `<body data-ds-base="...">`
to the full local dispatch base, including `/ds`. With the generated layout, pass
`body_attrs={%{"data-ds-base" => "/app/ds"}}` to `Layout.app/1`. The helper validates
the runtime base and safely encodes module/event segments. Encoded query/fragment
or backslash characters and malformed percent encoding are deliberately rejected
in page paths and dispatch bases; those paths cannot use these helpers.

Component routes also default to POST. Extra unsafe methods use `:event_methods`.
Read-only GET needs an explicit module list, and still requires method guards:

```elixir
star_view_components "/ds", get_events: [StatusBadge]
```

Only listed marked modules are dispatchable through that GET route. Other
components and existing marked controllers retain their POST boundary. Module
lists follow the enclosing Phoenix scope alias just like page modules. A broad
`get_events: true` for components is rejected. The low-level `StarView.Dispatch`
keeps its existing behavior unless a route supplies the new `only: [Module]`
restriction; route selection and handler authorization remain application-owned.

## Layout and errors

The Page plug disables inherited Phoenix root layouts before mount, because
`Layout.app/1` owns the document. A page can opt back into its Phoenix root
layout by calling `Phoenix.Controller.put_root_layout/2` in mount.

Event failures are logged. For development only, set
`config :star_view, debug_errors: true` to send a console error before reraising.
The relay is best-effort and cannot replace the original error. Keep this off
in production because exception details can contain application data.

For existing controller pages, continue using `use MyAppWeb, :star_view` and
[the controller guide](web_module.md). Page/component callbacks do not require
a controller dispatch rewrite.
