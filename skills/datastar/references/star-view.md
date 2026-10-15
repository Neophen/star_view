# StarView workflow

Inspect `mix.lock`, the dependency source, the application web entrypoints and
router. Read the matching SDK guides from its checkout or Hex dependency.
Do not infer feature availability from a package version string alone.

## Keep the existing host architecture

StarView owns Datastar SSE transport. Phoenix owns routing, controllers and
request context. The application owns authentication, authorization and durable
actions. Keep existing controller, `StarView.Page` and `StarView.Component`
boundaries instead of migrating a working screen to demonstrate a new API.

Put authentication, trusted tenant/actor resolution and CSRF in the route
pipeline. `StarView.Plug.RenameCsrfParam` runs before `Plug.CSRFProtection`.
GET must remain read-only. Router method/read-module allowlists still apply.

Dispatch starts SSE before invoking an event callback. Thread the returned conn
through patches; do not start SSE again or call HTTP status/render helpers after
streaming begins. Keep the Plug conn in its request process. Capture minimal
actor/tenant/locale values explicitly for background work.

`StarView.Signals.fetch/2` returns the updated conn with success or failure after
reading a body. Do not discard it. Use SDK framing, signal parsing, action
encoding and disconnect handling instead of building a parallel transport.
`:opts` is trusted developer JavaScript, not submitted values.

## Native STAR templates

`~STAR` is an experimental, opt-in compiler. It returns `StarView.Template`,
containing owned elements, values, branches, keyed lists and component subtrees.
`to_html/1` renders HTML; `diff/2` returns patches or a reset. Existing simple,
unique IDs are patch targets. Structural changes bubble to an existing ancestor;
a batch contains an ancestor or its descendants, never both. Use stable, non-nil
keys for keyed lists. A reset requires a fresh authorized baseline.

Native components and slots must return `StarView.Template`. Legacy HEEx values
are incompatible and should produce conversion errors. Convert the called
component tree with the page, including shared inputs and Phoenix helpers that
return HEEx, such as `Phoenix.Component.form/1`. Do not add an automatic bridge.
Phoenix's component-tag dispatcher expects its own rendered type; STAR's
dispatcher expects ours. Ordinary form data/changesets can still be used.

Every binding still evaluates on each template invocation. Dependency metadata
does not currently skip rendering or database reads. There is no new GenServer
runtime or automatic update scheduler. Browser-owned, ignored and foreign-content
subtrees need conservative patch boundaries. Preserve Rocket/editor lifecycle
and signal ownership before adopting a template on an actual page.

The current parser adapter requires exactly LiveView 1.2.12. The compiler rejects
unsupported constructs rather than guessing their meaning. Read
`guides/examples/star_templates.md` in the matching SDK source. Do not widen this
private adapter's supported versions without compatibility evidence.

## Checked event references

When this API is present, opt in with `checked_events: true` on `use StarView`,
`StarView.Page` or `StarView.Component`. Keep the existing syntax:

```elixir
# In a checked controller's ~STAR template:
# <button data-on:click={post("save")}>Save</button>

def handle_event("save", signals, %{method: "POST"} = conn) do
  # Validate and authorize, invoke the domain action, then return the patched conn.
  save_authorized(conn, signals)
end
```

Registration is derived from the final actual public `handle_event/3` clauses.
Do not add a second list of event names/methods. Use literal names and literal
method patterns. Wildcard clauses are fallbacks, not extra registered events.
IDs belong in signals rather than dynamic event-name patterns.

Literal local `post/get/put/patch/delete` references in a checked controller's
`~STAR` are checked at compilation. Pages/components use their existing local
`event("save")` or `event("search", verb: :get)` helpers. `StarView.Dispatch` and
`StarView.Page.Plug` reject
unknown events with 404 and wrong methods with 405/`Allow` before consuming
signals or starting SSE. Guards and authorization still run in the handler.

The check does not prove router mounting, runtime URL prefixes, raw JavaScript,
cross-module `Actions` calls or ordinary `~H` expressions. Phoenix `~p` checks
URL shape, not HTTP method or a matching named event clause. Preserve these
boundaries when explaining what compilation guarantees.
The legacy conn-first `StarView.Plug.Dispatch` is outside this opt-in integration.

Read `guides/core/checked_events.md` and cover handler renames/removal, method
changes, fallbacks and compiler error locations when changing this mechanism.
The experimental native compiler and checked events were added in 0.6.0 and
are absent from 0.5.0. Verify source/API availability before recommending them
to an installed app.
