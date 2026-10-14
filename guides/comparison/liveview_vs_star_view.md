# LiveView vs StarView

This guide compares Phoenix LiveView and StarView using the same active search example.

Both implementations support:

- debounced input
- optimistic client-side filtering
- server-side filtering as the source of truth
- realtime updates

The difference shows up in the amount of machinery each approach needs once the UI becomes interactive.

## The Example

A search input filters a list of framework names as the user types.

The UI should respond immediately in the browser, while the server still owns the canonical result set.

## Code Comparison

### StarView Controller

```elixir
defmodule AppWeb.SearchController do
  use AppWeb, :star_view

  @items ["Elixir", "Phoenix", "LiveView", "Datastar", "SSE", "Plug", "Ecto", "Ash", "HEEx", "Tailwind"]

  @impl StarView
  def mount(conn, _params) do
    conn
    |> signal(:query, "")
    |> signal(:results, @items)
  end

  @impl StarView
  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <div class="max-w-xl mx-auto p-6">
        <h1 class="text-2xl font-bold mb-4">Active Search</h1>
        <.search_form />
        <.item_list results={@results} />
        <.no_results query={@query} />
      </div>
    </Layout.app>
    """
  end

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

  attr :query, :string, default: nil

  def no_results(assigns) do
    ~H"""
    <div data-show={query_results("=== 0")}>
      <p class="text-gray-500">
        No results found for "<span data-text="$query">{@query}</span>"
      </p>
    </div>
    """
  end

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

  @impl StarView
  def handle_event("search", %{"query" => query} = signals, conn) do
    conn
    |> signal(:results, get_items(query))
    |> maybe_patch_list(signals)
  end

  def handle_event("reset", signals, conn) do
    conn
    |> signal(:query, "")
    |> signal(:results, @items)
    |> maybe_patch_list(signals)
  end

  defp get_items(""), do: @items

  defp get_items(query) do
    search_query = String.trim(String.downcase(query))
    Enum.filter(@items, &String.contains?(&1 |> String.downcase(), search_query))
  end

  defp maybe_patch_list(%{assigns: %{results: x}} = conn, %{"results" => x}), do: conn
  defp maybe_patch_list(conn, _signals), do: patch_element(conn, &item_list/1)

  defp starts_with?(item) do
    "#{item}.trim().toLowerCase().startsWith($query.trim().toLowerCase())"
  end

  defp query_results(condition) do
    "$results.filter(x => #{starts_with?("x")}).length #{condition}"
  end
end
```

### LiveView Equivalent

```elixir
defmodule AppWeb.SearchLive do
  use AppWeb, :live_view

  alias Phoenix.LiveView.ColocatedHook

  @items ["Elixir", "Phoenix", "LiveView", "Datastar", "SSE", "Plug", "Ecto", "Ash", "HEEx", "Tailwind"]

  @impl LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(:query, "")
    |> assign(:results, @items)
    |> ok()
  end

  @impl LiveView
  def render(assigns) do
    ~H"""
    <div id="active-search" class="max-w-xl mx-auto p-6" phx-hook=".ActiveSearch">
      <h1 class="text-2xl font-bold mb-4">Active Search</h1>
      <.search_form query={@query} />
      <.item_list results={@results} />
      <.no_results query={@query} has_results?={@results != []} />
    </div>
    <.active_search_script />
    """
  end

  attr :query, :string, default: nil

  def search_form(assigns) do
    ~H"""
    <form phx-change="search" class="mb-4 flex gap-2">
      <input
        type="text"
        class="input grow"
        placeholder="Search frameworks..."
        name="query"
        value={@query}
        phx-debounce="200"
        data-search-input
      />
      <button type="button" class="btn" phx-click="reset">
        Reset
      </button>
    </form>
    """
  end

  attr :query, :string, default: nil
  attr :has_results?, :boolean, default: false

  def no_results(assigns) do
    ~H"""
    <div class="space-y-2" data-search-empty hidden={@query == "" || @has_results?}>
      <p class="text-gray-500">
        No results found for "<span data-search-empty-query>{@query}</span>"
      </p>
    </div>
    """
  end

  attr :results, :list, default: []

  def item_list(assigns) do
    ~H"""
    <ul class="grid gap-2" data-search-results hidden={@results == []}>
      <.item :for={item <- @results} item={item} />
    </ul>
    """
  end

  attr :item, :string, required: true

  def item(assigns) do
    ~H"""
    <li class="border p-4" data-search-item={@item}>
      {@item}
    </li>
    """
  end

  @impl LiveView
  def handle_event("search", %{"query" => query}, socket) do
    socket
    |> assign(:query, query)
    |> assign(:results, get_items(query))
    |> noreply()
  end

  def handle_event("reset", _params, socket) do
    socket
    |> assign(:query, "")
    |> assign(:results, @items)
    |> noreply()
  end

  defp get_items(""), do: @items

  defp get_items(query) do
    search_query = String.trim(String.downcase(query))
    Enum.filter(@items, &String.contains?(&1 |> String.downcase(), search_query))
  end

  def active_search_script(assigns) do
    ~H"""
    <script :type={ColocatedHook} name=".ActiveSearch">
      export default {
        mounted() {
          this.onInput = event => {
            if (event.target.matches("[data-search-input]")) {
              this.applyFilter()
            }
          }
          this.el.addEventListener("input", this.onInput, {passive: true})
          this.applyFilter()
        },
        updated() { this.applyFilter() },
        destroyed() { this.el.removeEventListener("input", this.onInput) },
        applyFilter() {
          const input = this.el.querySelector("[data-search-input]")
          const query = (input?.value || "").trim().toLowerCase()
          let visibleCount = 0

          this.el.querySelectorAll("[data-search-item]").forEach(item => {
            const value = (item.dataset.searchItem || "").trim().toLowerCase()
            const isVisible = query === "" || value.startsWith(query)
            item.hidden = !isVisible
            if (isVisible) { visibleCount += 1 }
          })

          const results = this.el.querySelector("[data-search-results]")
          const noResults = this.el.querySelector("[data-search-empty]")
          const noResultsQuery = this.el.querySelector("[data-search-empty-query]")

          if (results) { results.hidden = visibleCount === 0 }
          if (noResults) { noResults.hidden = query === "" || visibleCount > 0 }
          if (noResultsQuery) { noResultsQuery.textContent = input?.value || "" }
        }
      }
    </script>
    """
  end
end
```

## Main Difference

LiveView keeps UI state on the server and sends DOM patches over a persistent WebSocket connection.

StarView keeps ephemeral interaction state in browser signals and uses normal HTTP requests plus an SSE stream for server updates.

That choice affects the whole system:

- where state lives
- how optimistic UI is written
- how much JavaScript you need
- how much server memory is retained per open tab
- how easy the app is to inspect with standard HTTP tooling
- how much runtime behavior the framework owns for you

## 1. Client-Side Filtering

StarView uses Datastar attributes with JavaScript expressions evaluated in the browser.

```elixir
defp starts_with?(item) do
  "#{item}.trim().toLowerCase().startsWith($query.trim().toLowerCase())"
end

defp query_results(condition) do
  "$results.filter(x => #{starts_with?("x")}).length #{condition}"
end
```

The markup describes the behavior directly:

```html
<li class="border p-4" data-show={starts_with?(StarView.JSON.encode!(@item))}>
```

The input updates `$query` locally. The list visibility updates locally. The empty-state text updates locally.

No hook is needed for the optimistic part.

LiveView can do the same visible behavior, but the local optimistic layer has to be written manually:

```javascript
this.el.querySelectorAll("[data-search-item]").forEach(item => {
  const value = (item.dataset.searchItem || "").trim().toLowerCase()
  const isVisible = query === "" || value.startsWith(query)
  item.hidden = !isVisible
  if (isVisible) { visibleCount += 1 }
})
```

That code is not complicated. The cost is ownership.

Once a hook exists, it has to survive LiveView patches, reconnects, lifecycle callbacks, selector changes, and future markup changes.

## 2. Signal Binding vs Form Binding

StarView binds the input to a signal:

```html
<input
  data-bind:query
  data-on:input__debounce.200ms={post("search")}
/>
```

The browser owns the current input value immediately.

The server receives a JSON signal map:

```elixir
def handle_event("search", %{"query" => query} = signals, conn) do
  conn
  |> signal(:results, get_items(query))
  |> maybe_patch_list(signals)
end
```

LiveView uses form semantics:

```html
<form phx-change="search">
  <input name="query" value={@query} phx-debounce="200" />
</form>
```

The server receives a form payload:

```elixir
def handle_event("search", %{"query" => query}, socket) do
  socket
  |> assign(:query, query)
  |> assign(:results, get_items(query))
  |> noreply()
end
```

For normal forms, LiveView's model is good.

For highly interactive state, signals can be cleaner. They model application state as JSON instead of forcing everything through input names and form payloads.

## 3. Optimistic UI

StarView makes optimistic UI cheap for local interactions.

Examples:

- filtering a list
- hiding and showing sections
- updating empty states
- showing selected values
- toggling UI controls
- reflecting temporary input state

These can live directly in attributes:

```html
<div data-show="$results.length > 0">
<span data-text="$query"></span>
```

LiveView's default model is server-owned state. That is great for correctness and consistency, but local UI needs either LiveView.JS commands, hooks, or custom client code.

For small interactions, that is fine.

For many interactions, hooks start becoming a parallel frontend layer.

That is where LiveView apps can get awkward. The page looks server-rendered, but the behavior is split between server assigns and client hooks.

## 4. Change Detection

LiveView tracks assigns automatically, computes diffs, and sends minimal patches.

That is one of its best features.

You write this:

```elixir
socket
|> assign(:query, query)
|> assign(:results, get_items(query))
```

LiveView decides what changed.

StarView is more explicit:

```elixir
defp maybe_patch_list(%{assigns: %{results: x}} = conn, %{"results" => x}), do: conn
defp maybe_patch_list(conn, _signals), do: patch_element(conn, &item_list/1)
```

If the result list did not change, no list patch is sent.

This is manual. It is also obvious.

The tradeoff is simple:

| Approach | Benefit | Cost |
|---|---|---|
| LiveView automatic diffing | Less application code | More framework machinery |
| StarView explicit patching | More control | More manual decisions |

## 5. Transport

Both approaches support realtime server push and both work well with Phoenix PubSub.

The transport shapes the architecture.

StarView uses:

- SSE for server-to-client updates
- HTTP requests for client-to-server events

LiveView uses:

- WebSockets for events
- WebSockets for patches
- WebSockets for uploads
- WebSockets for PubSub-driven updates

### SSE in StarView

| Pros | Cons |
|---|---|
| Plain HTTP | One-way stream |
| Easy to inspect with browser dev tools or `curl` | Client events need separate HTTP requests |
| Cookies behave normally | Raw SSE can hit browser connection limits on HTTP/1.1, but Dstar weakens this with per-tab stream deduplication and HTTP/2 avoids the old per-domain bottleneck in normal deployments |
| Works well with existing middleware | Text based |
| Usually easier with proxies and load balancers | Client must initiate the stream |
| No per-view process required just to hold UI assigns | Long-running streams still need cleanup, heartbeat handling, and stream deduplication across navigation |

StarView also addresses the usual SSE tab problem. `StarView.start_stream/2` uses per-tab stream deduplication, replacing the previous stream for the same user and tab before opening a new one. The README calls this `StreamRegistry`: one process per tab instead of zombie streams piling up across navigation. With HTTP/2, SSE streams also avoid the old HTTP/1.1 six-connections-per-domain bottleneck in normal Phoenix deployments.

SSE fits request-oriented applications well.

A lot of business software is request-oriented:

- forms
- filters
- dashboards
- tables
- CRUD
- admin workflows

For those apps, SSE plus HTTP keeps the system boring in a good way.

### WebSockets in LiveView

| Pros | Cons |
|---|---|
| Bidirectional connection | Persistent connection per open view |
| Good for low-latency interaction | More connection lifecycle complexity |
| Strong fit for realtime collaboration | WebSocket infrastructure can be more fragile in some environments |
| One channel handles events and patches | Cookies and session changes still need normal HTTP routes |
| Excellent Phoenix integration | Server memory grows with open LiveViews |
| Mature LiveView features | Hooks can become a second client-side state layer |

WebSockets fit highly interactive systems well.

Examples:

- collaborative tools
- chat
- realtime dashboards
- presence
- multiplayer-style interfaces
- complex uploads
- live monitoring screens

LiveView is very strong in this category.

## 6. Server Memory Model

StarView request handlers are short-lived.

The server handles an event, returns patches or signals, and lets the request finish. The SSE stream can stay open for server push, but the page does not require a stateful LiveView process holding the full UI state. With StarView stream deduplication enabled, navigation within the same tab replaces the previous stream instead of accumulating duplicate SSE processes.

LiveView keeps a process per mounted LiveView.

That process holds:

- socket assigns
- component state
- diff metadata
- lifecycle state
- subscriptions

The BEAM handles many lightweight processes very well.

That does not make memory free.

For many apps this is completely acceptable. For apps with many open tabs, large assigns, high fan-out updates, or long-lived dashboards, the resource model should be considered early.

## 7. Event Payloads

StarView uses JSON signal maps.

```elixir
%{"query" => query, "results" => results}
```

That is a natural shape for interactive UI state.

You can pattern match on it, inspect it, merge it, and send it back as signals.

LiveView uses event payloads built around forms and `phx-*` bindings.

That works very well for classic forms.

It gets more annoying with highly dynamic nested inputs, temporary UI state, or state that is not really a form submission.

LiveView has good tools for these cases. StarView's signal model is just simpler for this class of problem.

## 8. Debugging

StarView keeps more behavior visible in HTML attributes and HTTP requests.

You can usually inspect:

- current signals
- outgoing HTTP requests
- incoming SSE events
- patched fragments
- browser-side expressions

LiveView debugging often involves more framework context:

- socket lifecycle
- mount vs connected mount
- assigns
- diffs
- hooks
- reconnect behavior
- component boundaries
- temporary assigns
- streams

LiveView gives you strong tooling, but the model is bigger.

StarView gives you fewer layers to inspect.

## 9. Ecosystem

LiveView wins on ecosystem maturity.

That matters.

LiveView gives you:

- components
- streams
- uploads
- JS commands
- presence
- PubSub patterns
- testing helpers
- telemetry
- community examples
- production battle testing

StarView is smaller and younger.

That means fewer examples, fewer solved edge cases, and more application-level decisions.

For teams that want the paved road, LiveView is safer.

For teams that value a smaller runtime and are willing to own more decisions, StarView is attractive.

## 10. Architecture Comparison

| Aspect | StarView | LiveView |
|---|---|---|
| Transport | SSE plus HTTP | WebSocket |
| Server state | Minimal request state plus optional per-tab StreamRegistry for SSE deduplication | Persistent LiveView process |
| Client state | Datastar signals | Server assigns plus optional hooks |
| Optimistic UI | HTML attributes and signals | LiveView.JS or hooks |
| Change tracking | Explicit patches | Automatic diffs |
| Event payloads | JSON signals | Form/event maps |
| Debugging | HTTP, SSE, visible attributes | LiveView lifecycle and socket state |
| Realtime | Good | Excellent |
| Uploads | Application-defined | Built in |
| Ecosystem | Smaller | Mature |
| Operational model | More HTTP-native | More realtime-runtime oriented |
| Best fit | CRUD, dashboards, admin, business apps | Realtime, collaboration, complex LiveView apps |

## Choose StarView When

Choose StarView when you want:

- HTTP-native architecture
- simple request handling
- explicit patches
- browser-owned ephemeral UI state
- optimistic UI without hooks
- JSON signal payloads
- easy inspection with standard tools
- less framework runtime per page
- existing Phoenix controllers

Good fit:

- internal tools
- admin panels
- SaaS dashboards
- CRUD-heavy applications
- reporting interfaces
- forms with local interaction
- filters and search screens
- business workflows

## Choose LiveView When

Choose LiveView when you want:

- mature Phoenix integration
- automatic diffing
- component architecture
- built-in uploads
- streams
- presence
- strong realtime coordination
- fewer manual patching decisions
- one framework-owned runtime for server-driven UI

Good fit:

- collaborative applications
- chat-like systems
- realtime dashboards
- complex uploads
- live monitoring
- applications already invested in LiveView components
- teams that want the established Phoenix path

## Practical Recommendation

Use StarView when the application is mostly business software and the UI benefits from local interaction.

Use LiveView when realtime coordination is central or when you want the full LiveView ecosystem.

For many dashboards, admin panels, and CRUD applications, StarView will keep the system simpler.

For complex realtime applications, LiveView gives you more built-in power.

The decision should come from the shape of the app:

| Application shape | Better default |
|---|---|
| CRUD with local interaction | StarView |
| Admin dashboard | StarView |
| Search and filtering-heavy UI | StarView |
| Server-rendered business workflow | StarView |
| Realtime collaboration | LiveView |
| Presence-heavy application | LiveView |
| Upload-heavy workflow | LiveView |
| Existing LiveView codebase | LiveView |

## Final Take

LiveView is powerful, mature, and deeply integrated with Phoenix.

StarView is smaller, more explicit, and closer to normal HTTP.

LiveView gives you more framework support.

StarView gives you fewer moving parts.

For this active search example, StarView expresses the optimistic behavior directly in markup with signals. LiveView needs a hook once the UI should update locally before the server patch arrives.

That is the main tradeoff in miniature.

LiveView pays for power with runtime complexity.

StarView pays for simplicity with more explicit application decisions.
