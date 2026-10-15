# STAR Templates (Experimental)

`~STAR` compiles familiar HEEx syntax into **StarView's own template representation**.
The result is a `StarView.Template`; it does not wrap a `Phoenix.LiveView.Rendered`.
The unreleased compiled renderer holds merged static markup in generated code
and already-evaluated values in a tuple. Its equivalent `StarView.Template.Node`
tree is built only when inspection or patch planning needs it.

This is the first compiler proof, not a new page process or a complete HEEx
replacement. Existing StarView controllers and Page APIs are unchanged.
This experimental API was added in StarView 0.6.0 and is absent from 0.5.0.

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
- Default and named slots, including `:let` patterns and conditional named slots.
- Element/component `:if`, `:for` and explicit `:key` directives.
- Output `if`, `unless`, `case`, `cond` and plain `for` EEx blocks.
- Datastar attributes as ordinary HTML attributes.

Components and slots must return native template subtrees. **Legacy `~H`
values are incompatible.** An inline `~H` sigil fails at compilation; a legacy
component or slot result raises a clear conversion error during evaluation.
There is no automatic compatibility bridge. Convert the native subtree and its
called components together, including Phoenix helpers that return HEEx (such as
`Phoenix.Component.form/1`) and existing shared `~H` input components.
Phoenix routing, controllers, changesets and request security remain usable.

Inside `~STAR`, component tags call our dispatcher and expect our template
type. Ordinary `~H` tags still call Phoenix's dispatcher, which expects
`Phoenix.LiveView.Rendered`; these rendering systems cannot be mixed through
component tags.

## Incremental adoption through an HTTP host

An existing HEEx document or shell can interpolate a native value through
`Phoenix.HTML.Safe`. Keep the page's native content in a separate function:

```elixir
def render(assigns) do
  ~H"""
  <div id="existing-host">{content(assigns)}</div>
  """
end

defp content(assigns) do
  ~STAR"""
  <p id="count">Count: {@count}</p>
  """
end
```

This reduced example shows the direction of serialization; an application can
keep its complete existing HTTP document and shell around that native value.
The native subtree never consumes HEEx. Its component tags and slots still
require `StarView.Template`, while the host retains its ordinary HEEx components.
Only the native subtree participates in native diff planning. Keep IDs unique
across both layers and do not describe this as a fully native page.

For a patch-heavy screen, compare complete rendering plus HTML encoding and
actual SSE bytes before converting its bulk content. All bindings still run,
and building/validating a native tree can add cost. A diff that falls back to
the full existing root can add selector metadata without shrinking the HTML.
Small native request-control subtrees may provide checked event references
while keeping bulk rows in their existing renderer.

Measure initial mounting separately from later region patches. Include accepted
compression when comparing bytes, and distinguish offline diff potential from
updates an application actually emits. `patch_element/3` does not retain a prior
native tree or automatically choose diffs between independent requests. Use a
bounded, authorized baseline only when the existing lifecycle needs one.

## Compiled rendering (unreleased)

The compiler uses Phoenix's parser once during compilation. Adding another HTML
parser at runtime would not remove the previous renderer's repeated tree walk.
Like HEEx, compiled STAR now merges static markup and processes dynamic values
at runtime. It also pre-escapes fixed portions of binary interpolation and
concatenation in attributes, rather than rebuilding and scanning long JavaScript
strings for every row. It retains its own native type, checked events and conservative HTML
patch planner.

A `StarView.Template.Program` holds a generated `run/2` function and an evaluated
value tuple. One skeleton generates its HTML and tree clauses. Static structure
lives in code, so there is no mutable `trusted?` flag or HTML cache that can drift
from a public node tree. Dynamic values are still escaped on every encoding;
spread and nested attribute names are validated at runtime. Chosen expressions
run once in source order during construction, including keys before item bodies.
Rendering, inspection and diffing do not rerun them.

Compiled templates have `nodes: nil`. Read their tree with:

```elixir
nodes = StarView.Template.nodes(template)
```

Hand-built `%Template{nodes: [...]}` values still use the fully validated tree
renderer. Setting both `nodes` and `program` raises. This is an experimental
representation change after 0.6.1; recompile the application and its native
helpers when upgrading. Native snapshots are ordinary server values, not a
serialization or persistence format.

Module programs use hidden exported functions with stable names derived from
their skeleton. External captures do not pin old module code. Recompiling an
unchanged program preserves existing snapshots; removing a program causes a
clear stale-program error on rendering and `:template_changed` from diffing,
including a changed nested component. Source locations are part of the skeleton,
so moving a template can require a new baseline. Moduleless evaluation and late
compiler-hook expansion use local functions for immediate use and retain their
ordinary code-lifetime limits. User values containing closures can also retain
old code.

The patch planner currently materializes both full trees before comparing them.
That can make planning slower even when HTML rendering is much faster. Measure
`render + diff + SSE framing` against the application's existing bounded patch;
do not turn it on based on rendering speed or gzip bytes alone. No automatic
baseline storage or dirty-assign skipping is enabled.

Rust acceleration remains deferred until a measured bulk operation justifies it.
A NIF call stays in-process, but decoding trees, allocating results and scheduling
large native jobs can consume a kernel-only speedup. Compare complete workloads,
including boundary costs, before adding a native dependency.

### Real-page follow-up

The same 14 Octafest regions, 200 samples each with repeated HEEx baselines,
use 29–53% fewer reductions than 0.6.1 with the compiled renderer. Rendering work
is 0.922–1.007 times the first HEEx baseline. Wall times remain noisy on the
shared host; these figures do not prove a universal latency win.

| Render + encode | HEEx first / repeat | 0.6.1 | Candidate |
| --- | ---: | ---: | ---: |
| Builder canvas | 4.15 / 3.61 ms | 4.10 ms | 2.89 ms |
| Schedule workspace | 5.04 / 6.25 ms | 7.90 ms | 6.24 ms |
| Film form (two queries) | 3.65 / 5.04 ms | 5.80 ms | 3.48 ms |
| Login (2,000 samples) | 25 µs | 33 µs | 25 µs |
| Native picker (2,000 samples) | 105 / 104 µs | 349 µs | 89 µs |

The full picker remains 2,078 gzip SSE bytes. Raw evidence is retained in the
repository at bench/octafest-compiled-results.json. The released baseline uses
the complete installed 0.6.1 SDK. Both phases recompile native form/input helpers,
so the manifest has 78 modules. Workloads and transitions are unchanged.
No production page migration or retained baseline is enabled.

Render/diff/framing remains slower than existing targeted patches in the builder,
schedule and film-slot cases. Keep those bounded updates. Repeated materialization
is the next planner problem; a Rust kernel would not remove that architectural cost.

## Rendering performance in 0.6.1

The 0.6.1 renderer avoids repeated ASCII regex validation, duplicate dynamic-name
validation, per-value loading checks and successful-component error formatting.
The diff planner also avoids quadratic patch-list and duplicate-key bookkeeping.
Names and dynamic values retain their validation/escaping contracts; this is not
a trusted-metadata bypass or a change to snapshot ownership.

Controlled Octafest trials used actual component code for a 16-block builder,
a 48-screening schedule and film forms/detail tabs. These are local test-fixture
measurements on Elixir 1.20.4 / OTP 29.0.6 and LiveView 1.2.12, with four schedulers,
200 samples after warm-up, and repeated HEEx phases to expose wall-time noise.
Median render plus HTML encoding, milliseconds:

| Region | HEEx first / repeat | 0.6.0 runtime | 0.6.1 runtime |
| --- | ---: | ---: | ---: |
| Builder canvas | 5.36 / 5.64 | 13.84 | 5.28 |
| Builder open editor | 1.64 / 1.80 | 10.84 | 3.32 |
| Schedule workspace | 6.53 / 9.32 | 32.92 | 10.73 |
| Bounded schedule revalidation | 1.83 / 1.81 | 7.85 | 3.24 |
| Film screening filter | 0.238 / 0.387 | 1.449 | 0.422 |

Both native variants use the same working compiler compatibility fixes; released
0.6.0 cannot compile these component trees unchanged. The measurements isolate
its older render/diff runtime. The optimized native paths still use approximately
1.4–2.0 times the HEEx reductions across the 14 trials. Reductions do not fully
count regex/NIF work. Small wall-time differences are not evidence of a native
win. A separate full film-form trial includes two queries and reports their time
separately. Reachable term sizes describe different object graphs and exclude
off-heap binaries; they are not a comparison of RSS or per-tab retained memory.

Patch size and CPU must be assessed together. A native diff of the whole schedule
still targets its custom-element root and is larger than the application's
existing bounded revalidation. A diff of that bounded response reduces 12,338
gzip bytes to 6,536, while render/diff/framing takes 15.03ms versus HEEx's
2.74–2.95ms. A film slot change reduces 5,485 gzip bytes to 929 at 3.04ms versus
1.01–1.61ms. These are hypothetical retained-baseline region plans, not enabled
application savings or complete HTTP/event latency. Gzip estimates do not imply
that the production SSE path is compressed.

Generated request IDs remain in actual diff/byte measurements. Only formatting,
class-token spacing and hidden request/CSRF values are normalized for DOM parity.
Browser-bound editor changes can leave HTML unchanged; an empty diff does not
mean bindings were skipped. The benchmark converted 76 actual modules inside
its own VM, with explicit native helper adapters and no captured-HEEx substitution.

From a Git checkout with the `v0.6.0` tag, reproduce the small renderer benchmark:

```sh
mix run --no-start bench/template_render.exs
```

The captured real-page results are in `bench/octafest-results.json` in the source
repository. Keep broad page migrations paused unless the feature demonstrates
simpler code or a worthwhile update lifecycle. Smaller existing regions can
avoid both excess HTML and the cost of retaining full native snapshots.

## Patch boundaries

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
StarView's lowering emits the native program and its equivalent tree. Keeping this adapter narrow avoids
pretending that private parser tuples are a stable public API.

`case` and `cond` use separate EEx tags for their clauses, just as in ordinary
multiline HEEx. Patterns, bound variables and guards are retained. Changing
which clause is selected bubbles to an existing ancestor; a changed value
within the same clause can target a stable descendant. Guard assign access
uses guard-safe map access, so a missing assign can cause the guard to fail.

Non-output EEx statements, macro components (`:type`), and repeated named slots
are not supported. They
fail at compile time; move that control flow into a helper returning native
templates or ordinary values.
HTML escaping is not JavaScript or URL sanitization.

The native compiler does not reproduce LiveView's generated runtime markers or
colocated CSS/hook integration. Keep those dependency-owned boundaries in HEEx.

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

Opt into [checked event references](../core/checked_events.md) with
`checked_events: true` to verify literal local helpers against the actual
handler names and methods. Unknown names and wrong methods are also rejected
before SSE. Router mounting and runtime URL context remain separate: Phoenix's
verified routes check URL shape, and declaring a module dispatchable alone
does not prove that a named event or method is handled. Keep authorization and
input validation in the actual handler.

The compiler design was cross-checked against Phoenix LiveView 1.2.12 and its
[compiler source](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/tag_engine/compiler.ex).
The aim is a shared representation for SSR and safe Datastar patches;
process lifetime, async loading, data caching and automatic update scheduling
remain separate decisions.
