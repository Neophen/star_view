# `patch_element/3`

`patch_element/3` renders a Phoenix function component against the current
connection assigns and sends the resulting HTML as a Datastar
`datastar-patch-elements` event.

The generated search controller in `priv/templates/search_controller.ex.eex`
uses this pattern:

1. `mount/2` puts initial state on the connection.
2. `render/1` renders the first page through `Layout.app/1`, which emits
   initial browser signals with `init_signals/1`.
3. Datastar sends an event with the current browser signals.
4. `handle_event/3` updates assigns or signals on the connection.
5. `patch_element/3` re-renders only the component that changed.

## Component Example

Write function components the same way you would in a Phoenix view module:

```elixir
attr :results, :list, default: []

def item_list(assigns) do
  ~H"""
  <ul id="item-list" class="grid gap-2" data-show={query_results("> 0")}>
    <.item :for={item <- @results} item={item} />
  </ul>
  """
end

attr :item, :string, required: true

def item(assigns) do
  ~H"""
  <li class="border p-4" data-show={starts_with?(StarView.JSON.encode!(@item))}>
    {@item}
  </li>
  """
end
```

`JSON.encode!/1` makes the item a JavaScript string value. HEEx separately
escapes the HTML attribute. This matters when an item contains quotes or came
from submitted input; interpolating it into a hand-built quoted expression can
turn data into expression syntax.

When the component is rendered from the initial page, attributes come from the
parent template:

```elixir
@impl StarView
def render(assigns) do
  ~H"""
  <Layout.app conn={@conn}>
    <.item_list results={@results} />
  </Layout.app>
  """
end
```

When the component is rendered by `patch_element/3`, it receives
`conn.assigns`. Set every value the component needs before patching it:

```elixir
@impl StarView
def handle_event("search", %{"query" => query}, conn) do
  conn
  |> signal(:results, get_items(query))
  |> patch_element(&item_list/1)
end
```

In this example, `signal(:results, ...)` writes `conn.assigns.results` for the
component and patches `$results` for the browser.

If the component needs values that are not already in `conn.assigns`, pass a
small rendering function:

```elixir
def handle_event("add_item", %{"name" => name}, conn) do
  patch_element(conn, fn assigns ->
    item(Map.put(assigns, :item, name))
  end, to: "item-list", mode: :append)
end
```

Pass raw HTML when you already have the rendered content:

```elixir
patch_element(conn, "<li>Saved</li>", to: "item-list", mode: :append)
```

## Full Flow

The active-search template uses signals for state the browser should know about:

```elixir
@impl StarView
def mount(conn, _params) do
  conn
  |> signal(:query, "")
  |> signal(:results, @items)
end
```

During the initial render, those values are available as assigns and as
Datastar signals:

```elixir
@impl StarView
def render(assigns) do
  ~H"""
  <Layout.app conn={@conn}>
    <div class="max-w-xl mx-auto p-6">
      <.search_form />
      <.item_list results={@results} />
      <.no_results query={@query} />
    </div>
  </Layout.app>
  """
end
```

The input binds directly to the browser signal:

```elixir
def search_form(assigns) do
  ~H"""
  <div class="mb-4 flex gap-2">
    <input
      type="text"
      class="input grow"
      placeholder="Search frameworks..."
      data-bind:query
      data-on:input__debounce.200ms={post("search")}
    />
    <button class="btn" data-on:click={post("reset")}>
      Reset
    </button>
  </div>
  """
end
```

When the user types, Datastar posts the current signal map. StarView starts the
SSE response, calls the controller, and the controller returns patched state and
patched HTML:

```elixir
@impl StarView
def handle_event("search", %{"query" => query} = signals, conn) do
  conn
  |> signal(:results, get_items(query))
  |> maybe_patch_list(signals)
end

defp maybe_patch_list(%{assigns: %{results: results}} = conn, %{"results" => results}) do
  conn
end

defp maybe_patch_list(conn, _signals) do
  patch_element(conn, &item_list/1)
end
```

The `signals` argument is the browser's JSON state at request time, so its keys
are strings. `conn.assigns` is the server render state after your pipeline runs,
so its keys are atoms. Comparing both lets you skip an element patch when the
server result list did not actually change.

## Assigns vs Signals

Use `assign/3` when only the server-rendered component needs the value:

```elixir
def handle_event("show_profile", %{"id" => id}, conn) do
  profile = Accounts.get_profile!(id)

  conn
  |> assign(:profile, profile)
  |> patch_element(&profile_card/1, to: "profile")
end
```

The browser receives only the HTML patch. It does not receive `profile` as JSON.
This is the right choice for server-only data, large structs, values that cannot
be encoded cleanly as JSON, and values the browser should not own.

Use `signal/3` when the browser should react to the value or send it back on the
next event:

```elixir
def handle_event("select_tab", %{"tab" => tab}, conn) do
  conn
  |> signal(:tab, tab)
  |> assign(:items, Items.for_tab(tab))
  |> patch_element(&tab_panel/1)
end
```

The component can read `@tab` because `signal/3` also assigns the value, and the
browser can read `$tab` in attributes such as `data-show`, `data-text`, or
`data-bind`.

The rule of thumb is:

| State | Use | Why |
| --- | --- | --- |
| Render-only server state | `assign/3` | Function components can read it; the browser does not receive it. |
| Browser-visible JSON state | `signal/3` | Components can read it and Datastar can react to it. |
| Event input from the browser | `signals` argument | It is the submitted client state before the handler's updates. |

## Targeting

If the rendered element has a stable `id`, you can often let Datastar target it
from the patched HTML:

```elixir
patch_element(conn, &item_list/1)
```

Use `:to` when you want to target a DOM id explicitly. StarView turns the id
into a CSS selector:

```elixir
patch_element(conn, &item_list/1, to: "item-list", mode: :replace)
```

Use Datastar element options directly when you need more control:

```elixir
patch_element(conn, &item_list/1, selector: "#item-list", mode: :append)
```

The default element patch mode is `:outer`. Other supported modes include
`:inner`, `:replace`, `:prepend`, `:append`, `:before`, `:after`, and `:remove`.

## Change Checks

StarView does not maintain LiveView-style change tracking. If a handler can skip
an HTML patch, keep that decision explicit:

```elixir
defp maybe_patch_list(%{assigns: %{results: results}} = conn, %{"results" => results}) do
  conn
end

defp maybe_patch_list(conn, _signals) do
  patch_element(conn, &item_list/1)
end
```

Signal patches and element patches are independent. It is valid to update a
signal without patching HTML when Datastar can handle the UI change locally, and
it is valid to patch HTML from assigns without exposing those assigns as
signals.
