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

When rejecting a polling or live refresh after access is revoked, stop its
recurring activity as well. Use the existing SDK to redirect or replace the
bounded polling root without its interval. An empty SSE reply can be protocol-safe
while leaving a stale page polling indefinitely. Test granted access followed by
revocation, not only a user who never had access.

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
component tree called from the native subtree, including shared inputs and
Phoenix helpers that return HEEx, such as `Phoenix.Component.form/1`.
Do not add an automatic bridge.
Phoenix's component-tag dispatcher expects its own rendered type; STAR's
dispatcher expects ours. Ordinary form data/changesets can still be used.

An existing HEEx HTTP document or shell can interpolate a native value such as
`{content(assigns)}` through `Phoenix.HTML.Safe`. This is outward serialization;
the native subtree still cannot consume HEEx. Keep that boundary explicit and
describe a partially native screen accurately. It avoids migrating every shared
shell merely to check one page's event references.

Every binding still evaluates on each template invocation. Dependency metadata
does not currently skip rendering or database reads. There is no new GenServer
runtime or automatic update scheduler. Browser-owned, ignored and foreign-content
subtrees need conservative patch boundaries. Preserve Rocket/editor lifecycle
and signal ownership before adopting a template on an actual page.

Measure complete rendering plus HTML encoding and actual SSE bytes, both raw
and compressed, before expanding adoption. Native node allocation and validation
can cost more than HEEx; changing sigils alone need not shrink a response. When
bulk rows gain nothing, retain their existing renderer and put checked request
controls in small native subtrees. `patch_element/3` does not automatically keep
prior templates or choose diffs across independent requests. An offline diff is
potential, not an enabled application saving.

Use actual component trees and transitions when judging adoption. Compare against
the application's existing targeted patches as well as whole-page rendering.
Measure render/encoding, diff planning and SSE framing separately; count queries
that occur during rendering. Repeat the HEEx baseline and report reductions
alongside noisy wall times. HEEx work can run during HTML encoding, so trace
queries across rendering and encoding together. Prepare shared navigation or
permission-dependent presentation once for the fragments emitted in one reply;
recompute it from trusted context on later requests instead of retaining a stale
connection assign or global cache. Action authorization still runs independently.
Reachable term words for HEEx closures and native trees are not equivalent
memory measurements. Compression estimates are not
proof of production SSE encoding. Generated request IDs, CSRF and other volatile
fields must remain in actual patch measurements; do not suppress them in the
library to create a saving. Native rendering improvements do not enable retained
baselines or skipped binding evaluation.

In 0.6.1, the compiler adds case/cond clauses, guard-safe assigns and conditional
named slots, and fixes parser comments/compile-only hints. Its render/diff hot
paths are faster than 0.6.0; the representation can still cost more than HEEx.
Verify these APIs in the installed source and read the benchmark limitations in
`guides/examples/star_templates.md` before recommending a broader migration.

The 0.7.0 compiled renderer replaces eager node construction with merged
static markup and evaluated value tuples, including compile-time escaping of
fixed text inside interpolated attributes. Compiled templates have `nodes: nil`;
use `StarView.Template.nodes/1` when that API is installed. Hand-built trees still
validate normally. Recompile all native helpers after upgrading; do not pass
old snapshots across releases. Generated external program captures support code
reloads; a removed program resets diffing, including nested component changes.
Moduleless or late-hook programs and arbitrary closure values retain ordinary
local-function lifetime limits.

Faster rendering does not imply faster diffing: the current planner materializes
both trees. Compare complete render/diff/framing costs against bounded patches.
Do not add a Rust NIF from a microbenchmark alone; first identify a substantial
bulk hotspot and include term conversion, allocation and scheduler costs.
These changes require 0.7.0 and are absent from 0.6.1. Check installed APIs before use.

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
