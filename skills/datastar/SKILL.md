---
name: datastar
description: Build and review server-rendered Datastar pages, StarView for Elixir/Phoenix, and Rocket browser controls. Use for forms, filters, dialogs, HTML patches and live updates in projects using or adopting Datastar. Preserve an existing framework unless a migration is requested.
---

# Datastar, StarView and Rocket

Use Datastar as the default for new interactive work in projects adopting this skill. Start
with server-rendered HTML and signals. Choose Rocket when a reusable control
owns browser state, typed props and lifecycle. Follow the application's current
rendering boundary and established framework; installing the skill does not
authorize unrelated migrations.

## Inspect the integration

Read the page, its callers, shared components, asset entrypoint and pinned
dependencies before changing it. Verify the installed APIs against matching
source and docs; a checkout and a published Hex version can differ.

- For Plug/Phoenix and native `~STAR`, read [StarView](references/star-view.md).
- For an owned browser control, read [Rocket](references/rocket.md).
- For live streams, caching or performance, read [server reactivity](references/server-reactivity.md).

Load one Datastar runtime. Import Rocket from that same installed runtime when
available. Keep static display content as ordinary markup.

## Assign state to one owner

| State | Owner |
| --- | --- |
| Records, permissions, validation and business operations | Server action layer |
| Shareable search, filters and pagination | URL |
| Input drafts, open panels and pending requests | Datastar signals |
| A reusable browser control's internal state | Rocket instance |
| Public control configuration | Rocket props |
| Cached data or tab state | Existing server runtime, only when required |

Browser signals are untrusted UI input. Keep them small, scope repeated controls
explicitly, and filter outgoing signals to the operation's needs. DOM nesting
does not make normal signals private. Underscore-prefixed signals are excluded
from default transmission, not protected secrets. Keep CSRF and credentials out
of query URLs.

## Build the interaction

1. Reuse server views/components for initial HTML and later patches. Give patch
   roots and controls stable, unique IDs. Load authorized data before rendering;
   avoid per-record queries or external calls inside templates.
2. Use signals for drafts and immediate local interactions. Initialize
   browser-owned state only if missing; reset it explicitly for accepted writes
   or record changes. Use the installed `data-bind`, `data-show`, `data-text`,
   `data-class`, `data-attr` and computed-value APIs.
3. Keep request triggers explicit, such as `data-on:click={post("save")}` in a
   StarView controller. Put `data-indicator` on the element starting the request;
   an ancestor indicator does not track a descendant request. Settle errors and
   pending state on failure too.
4. Resolve actor, tenant and locale from trusted context. Validate submitted
   names, values, bounds and IDs; authorize each mutation and subscription.
   Invoke the application's business actions. Page access and event registration
   do not grant permission to perform a write.
5. Return authoritative HTML patches and deliberate UI/error signal patches.
   Prefer a cohesive morph of a stable root over coordinating many tiny edits.
   Preserve drafts, focus, selection, scroll and browser-owned widget boundaries.

Encode submitted values as JSON and escape HTML. HTML escaping does not sanitize
JavaScript or URLs; never concatenate submitted text into executable expressions.
Keep expressions short and handlers flat, using guards and named helpers.

## Verify actual behavior

Check initial rendering, success, invalid input, forbidden access and relevant
transport failures. For controls, check two instances, an unrelated patch,
removal/reinsertion, focus and cleanup. For live resources, check disconnect,
reconnect, superseded ownership and access revocation. An SSE assertion proves
what the server emitted, not the final DOM or preserved browser signals.

Use existing project checks and isolation rules. Capture interface evidence for
visual changes when the repository requires it. Do not provision extra services
or databases to work around testing conflicts.

The resource-rendering approach draws inspiration from Jacob O'Bryant's
[Understanding Datastar](https://biffweb.com/p/understanding-datastar/).
Use [Datastar's guide](https://data-star.dev/guide/the_tao_of_datastar) with the
installed runtime's actual contract.
