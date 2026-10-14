# `patch_signals/3`

`StarView.patch_signals/3` sends a Datastar `datastar-patch-signals` event to
the browser. Use it when you want explicit control over the signal patch:

```elixir
conn
|> StarView.patch_signals(%{count: 1})
|> StarView.patch_signals(%{query: "", results: []})
```

In Phoenix controllers that `use StarView`, you usually reach for the
`signal/3` helper first. It is a convenience wrapper for the common case where
the same value should be available to server-rendered function components and to
Datastar in the browser.

## The `signal/3` Helper

`signal/3` does two jobs:

1. calls `assign/3`, so function components can read the value as `@key`
2. exposes the value as a Datastar signal, so the browser can read it as `$key`

```elixir
conn
|> signal(:query, "")
|> signal(:results, @items)
```

Underneath, `signal/3` checks whether the SSE response has already started.

Before SSE starts, usually during `mount/2`, it records the signal key and
stores the value in `conn.assigns`:

```elixir
@impl StarView
def mount(conn, _params) do
  conn
  |> signal(:query, "")
  |> signal(:results, @items)
end
```

`render/1` then writes those recorded values into the first HTML response
through the generated `Layout.app/1` wrapper:

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

After SSE starts, usually inside `handle_event/3`, `signal/3` still updates
`conn.assigns`, then calls `StarView.patch_signals/3` for you:

```elixir
@impl StarView
def handle_event("search", %{"query" => query} = signals, conn) do
  conn
  |> signal(:results, get_items(query))
  |> maybe_patch_list(signals)
end
```

That is equivalent to assigning the value and then sending a signal patch:

```elixir
conn
|> assign(:results, results)
|> StarView.patch_signals(%{results: results})
```

The helper keeps those two operations together so the component render state and
browser signal state do not drift.

## Full Flow

The generated search controller in `priv/templates/search_controller.ex.eex`
uses signals for the query and result list.

The search input binds to `$query` in the browser:

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

When the input posts to `"search"`, Datastar sends the current browser signal
map. StarView reads that JSON, starts the SSE response, and calls the event
handler:

```elixir
@impl StarView
def handle_event("search", %{"query" => query} = signals, conn) do
  conn
  |> signal(:results, get_items(query))
  |> maybe_patch_list(signals)
end
```

The `signals` argument is the browser's submitted state, so its keys are
strings. The updated values are in `conn.assigns`, so their keys are atoms:

```elixir
defp maybe_patch_list(%{assigns: %{results: results}} = conn, %{"results" => results}) do
  conn
end

defp maybe_patch_list(conn, _signals) do
  patch_element(conn, &item_list/1)
end
```

This comparison lets the handler skip an HTML patch when the server result list
matches the browser's current `$results` signal.

## Manual Patching

Use `StarView.patch_signals/3` directly when you want explicit control:

```elixir
def handle_event("search", %{"query" => query}, conn) do
  results = get_items(query)

  conn
  |> StarView.patch_signals(%{results: results})
  |> patch_element(fn assigns ->
    item_list(Map.put(assigns, :results, results))
  end)
end
```

Manual patching is useful when:

- you are writing lower-level Plug code instead of a StarView controller
- you want to send a signal patch without changing `conn.assigns`
- you want to patch several signal keys in one explicit call
- you want to use `patch_signals_raw/3` with pre-encoded JSON

The important difference is that `StarView.patch_signals/3` does not call
`assign/3`. If a later component patch needs the same value, assign it yourself
or use `signal/3`.

```elixir
conn
|> assign(:results, results)
|> StarView.patch_signals(%{results: results})
|> patch_element(&item_list/1)
```

## Assigns vs Signals

Use `assign/3` when only the server-rendered component needs the value:

```elixir
def handle_event("show_profile", %{"id" => id}, conn) do
  conn
  |> assign(:profile, Accounts.get_profile!(id))
  |> patch_element(&profile_card/1, to: "profile")
end
```

The browser receives only the HTML patch. It does not receive `profile` as JSON.
This is the right choice for database structs, authorization-sensitive data,
large payloads, and values that only affect the next rendered component.

Use `signal/3` when the browser should react to the value, bind to it, or send
it back on the next event:

```elixir
def handle_event("reset", signals, conn) do
  conn
  |> signal(:query, "")
  |> signal(:results, @items)
  |> maybe_patch_list(signals)
end
```

The practical rule is:

| Function | Function components see it | Browser sees it | Use it for |
| --- | --- | --- | --- |
| `assign(conn, :key, value)` | Yes | No | Server-only render data |
| `signal(conn, :key, value)` | Yes | Yes | Shared server and browser state |
| `StarView.patch_signals(conn, map)` | No | Yes | Explicit browser-only signal patches |

## Reading Signals

Most Phoenix controller events should use the `signals` argument passed to
`handle_event/3`. Lower-level Plug code can read the same payload manually:

```elixir
{:ok, signals, conn} = StarView.fetch_signals(conn)
```

`GET` and `DELETE` requests read the `datastar` query parameter. Other methods
read JSON from the request body unless Plug parsers have already populated
`conn.body_params`. Raw body and query JSON are limited to 1,000,000 bytes by
default (`max_bytes:` overrides this in `fetch_signals/2`). Non-object JSON is
rejected. Always thread the fetched conn; `read_signals/1` is retained for callers
that already parsed their input. Configure `Plug.Parsers` to bound parsed bodies
too, since the original byte size is unavailable after parsing.

## Raw Patches And Removal

Use `patch_signals_raw/3` when you already have encoded JSON:

```elixir
StarView.patch_signals_raw(conn, ~s({"count":3}))
```

Use `remove_signals/2` to remove one or more signal paths:

```elixir
StarView.remove_signals(conn, ["user.email", "user.name"])
```

Removal is encoded as `null` values using RFC 7386 JSON Merge Patch semantics.

## Options

`signal/4` accepts the same signal patch options as `StarView.patch_signals/3`:

```elixir
signal(conn, :feature_flags, flags, only_if_missing: true)
```

During an SSE event, the option is applied to the immediate
`datastar-patch-signals` event. With manual control, pass the option directly:

```elixir
StarView.patch_signals(conn, %{feature_flags: flags}, only_if_missing: true)
```
