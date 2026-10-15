# Checked event references

Enable `checked_events: true` on a controller, page or component to derive its
event contract from the actual `handle_event/3` clauses. Keep the existing
Datastar attributes and request helpers:

```elixir
defmodule MyAppWeb.CheckedSaveController do
  use Phoenix.Controller, formats: [:html]
  use StarView, checked_events: true
  use Phoenix.Component
  import StarView.Template.Sigils

  @impl StarView
  def mount(conn, _params), do: Plug.Conn.assign(conn, :title, "")

  def index(conn, params), do: mount(conn, params)

  @impl StarView
  def render(assigns) do
    ~STAR"""
    <main id="save-page" data-signals:title={StarView.JSON.encode!(@title)}>
      <input id="title" aria-label="Title" data-bind:title />
      <button id="save" data-on:click={post("save")}>Save</button>
    </main>
    """
  end

  @impl StarView
  def handle_event("save", %{"title" => title}, %{method: "POST"} = conn)
      when is_binary(title) and byte_size(title) > 0 and byte_size(title) <= 200 do
    signal(conn, :saved, true)
  end

  def handle_event("save", _signals, %{method: "POST"} = conn) do
    StarView.patch_signals(conn, %{error: "Enter a title of at most 200 bytes"})
  end
end
```

This example acknowledges valid input; it does not persist a record. For a
real save, authorize the operation and invoke the application's action layer
inside the handler before acknowledging success.

The registry is generated from the final public handler clauses. The example
registers `"save"` for `"POST"` once, despite its two validation clauses. There
is no separate list of names or methods to maintain. Renaming or removing a
handler changes the contract on the same compilation that checks its template.
Handlers may appear below `render/1`.

## What compilation checks

Within a checked controller's native `~STAR` expressions, `post("save")`,
`get("search")`, `put`, `patch` and `delete` must reference a registered name
and method. A typo or wrong method is a compile error at the template's file
and line. The generated request expression is unchanged.

Checked pages and components use their existing `event` helper:

```elixir
use StarView.Page, checked_events: true
# or: use StarView.Component, checked_events: true

# Inside their ~STAR template:
# data-on:click={event("save")}
# data-on:input={event("search", verb: :get)}
```

Names must be literal strings. Page/component `event/2` options must be a
literal keyword list with a literal `:verb` when supplied. Other option values
can still be expressions. Put varying record IDs in signals rather than
building names such as `"save:#{id}"`.

Each named handler must put the method in its conn pattern. Both
`%{method: "POST"} = conn` and `%Plug.Conn{method: "POST"} = conn` work, in
either assignment order. Supported methods are GET, POST, PUT, PATCH and
DELETE. A method checked only in a guard, or a dynamic/prefix event-name
pattern, cannot supply this contract and fails compilation in checked mode.
Guards on input values and permissions remain ordinary Elixir.

A plain variable first argument is a fallback and does not register more
events. It can handle invalid input for an already registered event. Unknown
names cannot reach it through the checked dispatcher. Programmatic handler
changes after the contract's `before_compile` hook are unsupported and rejected.
Inherited and overridden handlers use the effective final clauses, so replaced
event names do not remain registered.
Guards on a wildcard event argument do not register names either. A wildcard
override forwarding to `super` cannot expose the old names; keep literal outer
clauses for the events the checked dispatcher should accept.

## What dispatch enforces

Both controller/component dispatch and page dispatch check the derived
contract before consuming signals or starting SSE:

- An unknown event returns HTTP 404.
- A registered event with the wrong method returns HTTP 405 and an `Allow` header.
- A valid name and method proceed through the existing signal parsing and
  callback lifecycle. Input validation and authorization still run there.

Modules without `checked_events: true` retain their existing dispatch behavior.
The option is independent of authentication, CSRF and route method allowlists.

## Boundaries

Compile-time checking covers **local helpers in that checked module's
`~STAR` expressions**. Explicit `StarView.Actions.post(OtherModule, "save")`,
cross-module calls, raw JavaScript action strings and ordinary `~H` expressions
are outside this first compiler check. Requests to a checked target still
receive its runtime name/method validation.

This integration uses `StarView.Dispatch` and `StarView.Page.Plug`. The legacy
conn-first `StarView.Plug.Dispatch` interface is outside the checked-event
integration; do not route these checked controllers through it.

The router must still mount the intended endpoint and method. GET requires the
existing read-event opt-in; extra unsafe methods require `:event_methods`.
This feature does not statically prove router mounting, host constraints,
`location.pathname`, `data-ds-base` or runtime prefixes. Phoenix `~p` checks URL
shape, not the named event or HTTP method. Avoiding cross-module and router
compile dependencies keeps incremental compilation and ordinary module cycles
predictable.

Checked events were added in StarView 0.6.0 and are absent from 0.5.0. Native
`~STAR` also has its own [experimental compiler requirements](../examples/star_templates.md).
