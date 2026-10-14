# Phoenix Web Module

StarView controllers should use a dedicated `:star_view` section in your
Phoenix web module. Keep it near the existing `controller` section so
controller-style imports stay grouped together.

```elixir
def star_view do
  quote do
    use Phoenix.Controller, formats: [:html, :json]
    use StarView
    use Phoenix.Component

    use Gettext, backend: MyAppWeb.Gettext

    import Phoenix.Component, except: [assign: 3]
    import Plug.Conn

    alias MyAppWeb.Components.StarView.Layout

    plug :put_root_layout, false

    unquote(verified_routes())
  end
end
```

The installer also generates `MyAppWeb.Components.StarView.Layout`.
`put_root_layout/2` disables Phoenix's root layout for StarView controllers,
and `Layout.app/1` emits the full document plus the initial Datastar signals
for the page.

Then use that section from a controller:

```elixir
defmodule MyAppWeb.CounterController do
  use MyAppWeb, :star_view

  @impl StarView
  def mount(conn, _params) do
    signal(conn, :count, 0)
  end

  @impl StarView
  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <button data-on:click={post("increment")}>+</button>
      <span data-text="$count"></span>
    </Layout.app>
    """
  end

  @impl StarView
  def handle_event("increment", %{"count" => count}, %{method: "POST"} = conn)
      when is_integer(count) and count >= 0 and count < 1_000_000 do
    signal(conn, :count, count + 1)
  end

  def handle_event(_event, _signals, conn), do: conn
end
```

## Router

Add the dispatch route inside your browser pipeline:

```elixir
pipeline :browser do
  # ...
  plug StarView.Plug.RenameCsrfParam
  plug :protect_from_forgery
  # ...
end

scope "/", MyAppWeb do
  pipe_through :browser

  get "/counter", CounterController, :mount
  post "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

`StarView.Dispatch` decodes the target controller from the Datastar action,
verifies that it used `use StarView`, starts the SSE response, and calls
`handle_event/3`. The `alias: false` route option keeps Phoenix from resolving
the dispatch plug as `MyAppWeb.StarView.Dispatch` inside the scoped router
block.
`StarView.Plug.RenameCsrfParam` must run before `:protect_from_forgery` so
Datastar's `csrf` signal is available as Phoenix's `_csrf_token` parameter.

## Function components without handler registration

A reusable component needs HEEx and any rendering helpers it actually uses;
it should not register itself as a dispatched event handler. For Datastar
components, an application can define a separate entrypoint:

```elixir
def star_component do
  quote do
    use Phoenix.Component

    import Phoenix.Controller, only: [get_csrf_token: 0]
    import StarView.Controller, only: [init_signals: 1]

    unquote(verified_routes())
  end
end
```

Use `MyAppWeb, :star_component` for reactive components and the manually adapted
layout in the [layout guide](layout.md). This entrypoint is application code;
the current installer generates the layout with the application's existing
`:html` entrypoint plus its required rendering helper import. Add your shared
Gettext/components imports to the new entrypoint as needed. Keep
`Phoenix.Component.assign/3` for maps and `Plug.Conn.assign/3` for conns.

Only the controller entrypoint uses `use StarView`. Its generated `post/1`
helper targets that controller; shared components call `StarView.Actions.post/2`
with the owning controller explicitly. For the full render-and-patch flow,
see the [counter example](../examples/phoenix_counter.md).

If you factor imports into quoted helpers and use an AST-rewriting formatter,
check the formatted expansion order. A later narrow import of
`Phoenix.Controller` can replace the controller's full import and remove its
pipeline functions. A later full `Phoenix.Component` import can reintroduce
`assign/3` ambiguity with `Plug.Conn`. Named application `use` entrypoints keep
helper expansion order explicit; compile the formatted result.
