# Actions, URLs, and Quoted Values

Use `StarView.Actions` to connect a Datastar event to its server handler. It
constructs the `/ds` route and serializes the JavaScript string argument, so an
event name containing quotes, spaces, or slashes cannot alter the expression.

## Pick the handler explicitly

Inside a controller that `use StarView`, `post("increment")` targets that
controller. A reusable function component should name its owning controller:

```elixir
defmodule MyAppWeb.CounterButton do
  use Phoenix.Component

  def button(assigns) do
    ~H"""
    <button
      id="counter-shared-increment"
      type="button"
      data-on:click={StarView.Actions.post(MyAppWeb.CounterController, "increment")}
    >Add one</button>
    """
  end
end
```

Do not `use StarView` just to obtain an action helper in a component. That use
registers a controller/event handler and adds controller lifecycle functions.
Function components can call `StarView.Actions` directly.

All verbs have the explicit form `verb(module, event, opts \\ [])`:

```elixir
StarView.Actions.post(MyAppWeb.CounterController, "increment")
StarView.Actions.get(MyAppWeb.CounterController, "refresh", prefix: "/admin")
StarView.Actions.delete(MyAppWeb.CounterController, "reset")
StarView.Actions.post(MyAppWeb.CounterController, "save/preview")
```

The final event is one encoded segment, `save%2Fpreview`. Prefixes are local
application paths; `"admin/"` normalizes to `"/admin"`. External URLs, query
strings, fragments, backslashes, dot segments, and malformed escapes are
rejected. Empty, `.` and `..` event segments are rejected too. Route your
dispatcher under the matching prefix when you set one.

The helper only creates the client expression. Register each HTTP verb you
actually use; the installer registers POST by default. For the GET example's
`/admin` prefix and the DELETE example's default prefix:

```elixir
scope "/admin", MyAppWeb do
  pipe_through :browser
  get "/ds/:module/:event", StarView.Dispatch, [], alias: false
end

scope "/", MyAppWeb do
  pipe_through :browser
  post "/ds/:module/:event", StarView.Dispatch, [], alias: false
  delete "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

Keep the browser pipeline's session/authentication and CSRF plugs. In a shared
dispatch route, handlers must also reject unexpected `conn.method` values so a
mutation handler cannot be invoked through GET. The counter example accepts
only POST. Add PUT/PATCH routes only when your application uses those helpers.

GET actions must be read-only. A helper's verb does not enforce authorization
or CSRF protection; those remain router and handler responsibilities.

## Fetch options

Controller helpers accept the same trusted JavaScript `:opts` object as page
and component event helpers. Values such as an `AbortController`, regular
expressions, and signal references must stay JavaScript expressions:

```elixir
StarView.Actions.post(MyAppWeb.CounterController, "save",
  opts: "{requestCancellation: controller, retry: 'never', retryMaxCount: 0}"
)
```

Only pass developer-authored code to `:opts`; encode dynamic literal values with
`StarView.JSON.encode!/1` and never build executable options from submitted text.
Check the emitted expression in integration tests.

Keep mutation retries separate from read-stream reconnection. Verify the pinned
Datastar client's behavior: Octafest's vendored Pro 1.0.4 transport was verified
with a failing-fetch test and needs
`retryMaxCount: 0` as well as `retry: 'never'` to prevent network-error retries.
Use an explicit payload or `filterSignals` to send only the operation's inputs,
retaining CSRF and the application's authorization boundary. A timeout or lost
response can follow a committed write; communicate an unconfirmed outcome
instead of automatically resubmitting it.

## The dynamic module contract

The overload `StarView.Actions.post("increment")` uses the client-only
`$_star_view_module` signal. Your application must initialize it with
`StarView.Actions.encode_module(controller)`; neither dispatcher nor the
generated layout sets it for you. Initialize it explicitly in the page markup:

```heex
<div data-signals={StarView.JSON.encode!(%{
  _star_view_module: StarView.Actions.encode_module(MyAppWeb.CounterController)
})}>
  <button data-on:click={StarView.Actions.post("increment")}>Add one</button>
</div>
```

An explicit controller helper, including controller-local `post("increment")`,
does not need the dynamic signal. Prefer that form when the target is known.
The underscore prefix makes `_star_view_module` client-only: it is used to
construct the URL rather than being posted as application data.

The dynamic helper validates and percent-encodes the module value in the
browser. A `module:` override is literal encoded route data:

```elixir
StarView.Actions.post("increment", module: "my_app_web-counter_controller")
```

`module: "$_star_view_module"` retains the standard dynamic contract. Other
`$`-prefixed overrides are rejected in v0.4.0; custom JavaScript expressions
are not accepted as module names. Module decoding uses existing Elixir atoms.
Neither this mechanism nor the dispatchable marker grants permission to call
the target's business operation.

## Put strings into expressions as strings

For an application value inside a custom expression, serialize it as JSON:

```elixir
attr :label, :string, required: true

def choose_label(assigns) do
  assigns = Phoenix.Component.assign(assigns, :quoted_label, StarView.JSON.encode!(assigns.label))

  ~H"""
  <button data-on:click={"$chosen_label = " <> @quoted_label}>Choose {@label}</button>
  """
end
```

HEEx escapes the HTML attribute, while JSON quoting preserves the JavaScript
string value. Interpolating an unescaped label into `'#{label}'` can turn a quote
in the label into expression syntax. JSON quoting is for a **value**, not for an
entire already-constructed action expression.

Action helpers now emit JSON double-quoted string literals. Code that extracts
URLs with a pattern that only recognizes `@post('...')` must be updated. Prefer
using the helper at the call site and keeping module/event values as data;
do not rewrite generated expressions with a single-quote string match.

The quote change also affects hand-built HTML. In HEEx, use an expression
attribute as above. When creating raw HTML, escape the **whole action expression
as an HTML attribute value**; JSON quoting the URL alone is insufficient:

```elixir
action = StarView.Actions.post(MyAppWeb.CounterController, "increment")
escaped_action = action |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
"<button data-on:click=\"" <> escaped_action <> "\">Add one</button>"
```

Do not insert the double-quoted action directly into a double-quoted HTML
attribute, or mark unescaped action text as `Phoenix.HTML.raw/1`.

For return values and request validation, see [manual Plug endpoints](../examples/plug_endpoints.md).
