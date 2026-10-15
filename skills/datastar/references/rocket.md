# Rocket controls

Use Rocket when a reusable browser control benefits from owned state, typed
props and lifecycle: a picker, media control or widget adapter. Ordinary server
markup with Datastar signals is often sufficient. Wrapping an imperative custom
element solely to rename lifecycle methods is not automatically an improvement.

Verify bundle availability, licensing and the installed beta API against the
[official reference](https://data-star.dev/reference/rocket). The current
`datastar-rocket.js` bundle includes Datastar; use it as the sole runtime when
adopting that distribution. Older installed bundles may expose Rocket differently.
Import registration from the asset entrypoint. Do not duplicate a runtime or
copy a licensed client bundle into the skill.

- Define the public prop/event/property contract before moving state. Props are
  configuration, not automatically local signals; use supported observation for
  later prop changes.
- Choose light or shadow DOM deliberately. Light DOM integrates with server
  children and shared styles, but remains a state boundary.
- Put setup, DOM-dependent initialization and render work in their installed
  lifecycle hooks. Keep subscriptions and timers out of repeated rendering.
- Register cleanup for listeners, observers, timers, animation frames, third-party
  instances and async work. Prevent stale results from updating a removed or
  superseded instance.
- Preserve native input properties and `input`/`change` events when integrating
  with forms. Avoid competing page and control stores for one value.

In the reviewed Rocket beta 2 runtime, light-DOM scoping rewrites Datastar
bindings in server-rendered host children even when the control has no render
function. Wrapping existing markup can redirect page-owned `data-bind` and
signal initialization into an instance scope. `$pageSignal` and local `$$value`
have distinct roles. Check the installed behavior before assuming otherwise.

Test typing and submission, prop changes, server morphs, two instances and
removal/reinsertion. Verify the actual transformed bindings and ownership, not
just the registration call. Keep a thin adapter if Rocket adds no useful public
contract or reactive ownership.
