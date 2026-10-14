# Phoenix Counter and Component Patches

Use this example when an interaction needs both a browser signal and fresh
server-rendered HTML. StarView keeps them in one connection pipeline: validate
the input, update the signal, and render the component that changed.

This counter deliberately stores its count in the browser. It demonstrates
transport and rendering, not durable state or concurrent updates. For a saved
counter, load and update the record through your application's authorized
action instead of treating the submitted count as the source of truth.

## Set up Phoenix

Start with the [installation](../introduction/installation.md), [web module](../phoenix/web_module.md),
and [layout](../phoenix/layout.md) guides. They supply `MyAppWeb, :star_view`, the Datastar
client, and `MyAppWeb.Components.StarView.Layout`.

Add these routes through a browser pipeline that parses JSON and applies CSRF
protection before dispatch:

```elixir
scope "/", MyAppWeb do
  pipe_through :browser

  get "/counter", CounterController, :mount
  post "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

Use one module in `lib/my_app_web/controllers/counter_controller.ex`:

```elixir
defmodule MyAppWeb.CounterController do
  use MyAppWeb, :star_view

  @impl StarView
  def mount(conn, _params) do
    conn
    |> Plug.Conn.assign(:label, "Count")
    |> signal(:count, 0)
    |> signal(:counter_error, "")
  end

  @impl StarView
  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <section id="counter">
        <.summary count={@count} label={@label} />
        <button id="counter-increment" type="button" data-on:click={post("increment")}>
          Add one
        </button>
        <p
          id="counter-error"
          role="alert"
          data-show="$counter_error !== ''"
          data-text="$counter_error"
        ></p>
      </section>
    </Layout.app>
    """
  end

  @impl StarView
  def handle_event("increment", %{"count" => count}, %{method: "POST"} = conn)
      when is_integer(count) and count >= 0 and count < 1_000_000 do
    conn
    |> Plug.Conn.assign(:label, "Count")
    |> signal(:counter_error, "")
    |> signal(:count, count + 1)
    |> patch_element(&summary/1)
  end

  def handle_event("increment", _signals, conn),
    do: signal(conn, :counter_error, "Send a count between 0 and 999,999.")

  def handle_event(_event, _signals, conn), do: conn

  attr :count, :integer, required: true
  attr :label, :string, required: true

  def summary(assigns) do
    assigns = Phoenix.Component.assign(assigns, :display, "#{assigns.label}: #{assigns.count}")

    ~H"""
    <output id="counter-summary" aria-live="polite">{@display}</output>
    """
  end
end
```

Open `/counter` and click **Add one**. The initial document contains `Count: 0`.
The POST produces signal patches and an element patch for `#counter-summary`;
the page document is not rendered again. Invalid counts produce the existing
error signal without changing the count.

## Understand the two assign APIs

`Plug.Conn.assign/3` updates the request connection. `Phoenix.Component.assign/3`
updates a component's assigns map. The dedicated web entrypoint keeps the Plug
version available to controllers; the explicit calls above make the distinction
visible when both operations appear in the same module.

`patch_element/3` passes current connection assigns to its rendering function.
In v0.4.0 it also supplies `:__changed__` metadata when ordinary Plug assigns
lack it. The `summary/1` component can therefore call `Phoenix.Component.assign/3`
both from the initial HEEx render and from an event patch. This is rendering
metadata, not LiveView diff tracking or persistent server state.

Each event is a new HTTP request. `mount/2` does not run before every event, and
the dispatcher does not retain the previous connection's assigns. The handler
sets `:label` again because its component needs that server-only value.

| Operation | Component input | Browser state |
| --- | --- | --- |
| `Plug.Conn.assign(conn, :label, value)` | Updated | Unchanged |
| `signal(conn, :count, value)` | Updated | Patched during SSE |
| `StarView.patch_signals(conn, %{count: value})` | Unchanged | Patched |
| `patch_element(conn, &summary/1)` | Read to render HTML | DOM patched |

## Change only the required region

A stable root id lets Datastar find a component without an explicit selector.
To append an item inside a list, use a separate item component and the list's id:

```elixir
conn
|> Plug.Conn.assign(:item, %{id: "item-42", name: "Ada"})
|> patch_element(&item/1, to: "people", mode: :append)
```

Here `item/1` must render the new list item; it should not render another
`<ul id="people">` inside the existing list. `to:` accepts a DOM id, while
`selector:` accepts a CSS selector. The default patch mode is `:outer`.

Use component assigns for records that only need to become HTML. Putting a
record in a signal also serializes it for the browser. Authorization must
control both what you render and what you expose as JSON.

See [actions and quoted values](../core/actions.md), [manual Plug endpoints](plug_endpoints.md),
and [troubleshooting](../reference/troubleshooting.md) for the transport boundaries.
