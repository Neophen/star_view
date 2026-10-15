# STAR Templates (Experimental)

`~STAR` compiles familiar HEEx syntax into **StarView's own template tree**.
The result is a `StarView.Template`, containing `StarView.Template.Node`
elements, values, branches, collections and components. It does not wrap a
`Phoenix.LiveView.Rendered` as its native representation.

This is the first compiler proof, not a new page process or a complete HEEx
replacement. Existing StarView controllers and Page APIs are unchanged.
Octafest's installed StarView 0.5.0 does not include this experimental API.

## Render and compare

```elixir
defmodule MyAppWeb.CounterTemplate do
  use Phoenix.Component
  import StarView.Template.Sigils

  def render(assigns) do
    ~STAR"""
    <main id="counter-page">
      <p id="count">{@count}</p>
      <h1 id="title">{@title}</h1>
    </main>
    """
  end
end
```

`StarView.Template.to_html/1` produces the initial HTML. The template also
implements `Phoenix.HTML.Safe` when the optional Phoenix dependencies are
available for serialization through the Phoenix host. This protocol support
does not allow legacy HEEx values inside the native template tree.

```elixir
previous = MyAppWeb.CounterTemplate.render(%{count: 1, title: "Counter"})
next = MyAppWeb.CounterTemplate.render(%{count: 2, title: "Counter"})

StarView.Template.to_html(previous)
{:ok, [patch]} = StarView.Template.diff(previous, next)
# patch targets #count and contains the complete <p id="count">2</p> element.
```

The planner returns either `{:ok, patches}` or `{:reset, reason}`. A reset
means the caller must render a complete baseline inside its existing content
root. It is not an instruction to replay commands or bypass authorization.
Template source changes invalidate the baseline.

Each patch contains `selector`, `elements`, `mode` and `namespace`. The
existing `StarView.patch_elements/3` transport can send that HTML. The planner
does not own a connection, start SSE, open a GenServer, or write to the browser.
Only the request process owns its Plug connection.

## What is preserved

- HTML structure, static entities, attribute escaping and dynamic values.
- `@assigns`, local and remote function components, and ordinary `attr` and
  `slot` declarations from `Phoenix.Component`.
- Default and named slots, including `:let` patterns.
- Element/component `:if`, `:for` and explicit `:key` directives.
- Output `if`, `unless` and plain `for` EEx blocks.
- Datastar attributes as ordinary HTML attributes.

Components and slots must return native template subtrees. **Legacy `~H`
values are incompatible.** An inline `~H` sigil fails at compilation; a legacy
component or slot result raises a clear conversion error during evaluation.
There is no automatic compatibility bridge. Convert the page and its called
components together, including Phoenix helpers that return HEEx (such as
`Phoenix.Component.form/1`) and existing shared `~H` input components.
Phoenix routing, controllers, changesets and request security remain usable.

Inside `~STAR`, component tags call our dispatcher and expect our template
type. Ordinary `~H` tags still call Phoenix's dispatcher, which expects
`Phoenix.LiveView.Rendered`; these rendering systems cannot be mixed through
component tags.

IDs must remain unique across the complete document. Trusted raw HTML is
still opaque; duplicate checks cannot inspect IDs hidden inside that markup.

Changed text without an addressable element bubbles to an existing ancestor.
Branch insertion/removal and keyed membership/order changes also select an
ancestor. A batch selects an ancestor or its descendants, never both. This
proof uses existing, simple DOM IDs; it does not inject wrappers or generate
browser identities. Stable, non-nil list keys are required for keyed lists.

## Evaluation and browser ownership

Expressions are evaluated when the template function runs. The tree records
assign dependency metadata, but this version does **not** skip binding
evaluation or database work. Load authorized data before rendering and keep
reads out of templates. Locale, time and permissions should be explicit
inputs when they affect output; this avoids hidden dependencies in later
optimizations.

Compare snapshots from one owner. Another request or browser script can change
the DOM independently; a server baseline does not prove what the browser
currently displays. A reconnect should get a fresh authorized baseline.

The planner keeps browser-owned and foreign-content subtrees conservative.
Keep Rocket/editor ownership and ignore-morph boundaries intact, preserve
draft signals with the correct only-if-missing initialization, and verify
focus and lifecycle behavior in the browser before adopting a template on a
real page. This proof is not a Rocket integration or draft-recovery system.

## Compiler compatibility

The adapter currently requires **Phoenix LiveView 1.2.12**. Its parser is
private. The ordinary Phoenix compiler is also run for validation and
component-call diagnostics, but its generated rendering code is discarded.
StarView's lowering emits the actual tree. Keeping this adapter narrow avoids
pretending that private parser tuples are a stable public API.

`case`, `cond`, non-output EEx statements, macro components (`:type`), and
conditional/repeated named slots are not supported in this first proof. They
fail at compile time; move that control flow into a helper returning native
templates or ordinary values.
HTML escaping is not JavaScript or URL sanitization.

Evaluated class lists omit empty entries and join with one space. HEEx's
static-prefix optimization can retain a trailing space; class tokens agree,
but their serialized attribute bytes can differ.

Register `StarView.Template.Formatter` in the application's formatter plugins
to format `~STAR` contents using Phoenix's HTML formatter. Editor highlighting
and language-server support for the new sigil are separate integration work.

## Event expressions

Keep the existing Datastar attributes and request helpers, such as
`data-on:click={post("save")}` in a StarView controller. The HTTP helper still
chooses how the browser sends the event; the new template representation does
not change transport or turn an Elixir function into a browser callback.

This proof does **not** validate named event targets. Current helpers produce
request-expression strings. Phoenix's verified routes check URL shape, but
do not prove that a particular HTTP method is mounted or that an event string
matches a `handle_event/3` clause. Declaring a module dispatchable alone proves
neither. Keep authorization and input validation in the actual handler.

The compiler design was cross-checked against Phoenix LiveView 1.2.12 and its
[compiler source](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/tag_engine/compiler.ex).
The aim is a shared representation for SSR and safe Datastar patches;
process lifetime, async loading, data caching and automatic update scheduling
remain separate decisions.
