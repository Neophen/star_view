# Changelog

## v0.7.0 — 2026-10-16

### Changed

- Compile native templates into merged static HTML and evaluated value tuples,
  with hidden named rendering programs that do not pin old module code.
  Reuse the existing escaping/validation for dynamic values and spreads.
- Build component assigns and unconditional unique slots as maps; pre-escape
  literal class prefixes and fixed binary-attribute portions without caching
  submitted or runtime HTML. Binary operands all evaluate before type validation,
  preserving failure-side effects before later template content.
- **Experimental representation change:** compiled `Template.nodes` is now nil.
  Use `Template.nodes/1` for the evaluated tree. Hand-built node trees remain
  supported. Recompile native callers when upgrading; snapshots are not a
  transport/storage format.
- Diff materializes both trees and keeps the existing conservative patch rules.
  Missing compiled programs after reload reset the baseline. No expressions,
  authorization or data reads are skipped, and no connection process is added.

### Added

- CI checks compile, tests, documentation and package assembly on the minimum
  supported Elixir/OTP pair and Octafest's current pair, using the current
  toolchain for canonical formatting.

### Fixed

- Keep function-local aliases in evaluated keys, reject void children during
  compilation, and preserve moduleless template evaluation.

## v0.6.1

### Added

- Native `case`/`cond` EEx clauses with pattern bindings, guards and conservative
  branch patching, plus `:if` on named slots. Legacy HEEx results remain incompatible.

### Changed

- Replace per-element and per-attribute ASCII regex validation with equivalent
  byte scanners, validate dynamic names once, and avoid repeated module-loading
  checks and successful-component error-message formatting during rendering.
- Keep patch accumulation and duplicate-key checks linear while preserving
  document order, missing-key precedence and existing patch boundaries.

### Fixed

- Accept the pinned parser's normalized EEx comment nodes without emitting them,
  and consume compiler-only formatting/interpolation hints without DOM attributes.

### Documentation

- Clarify incremental native subtree adoption through existing HEEx HTTP hosts,
  and require separate rendering and actual patch measurements before expanding
  STAR use. The bundled skill explains the same boundary and retained-baseline limits.

## v0.6.0

### Added

- Portable Datastar/StarView/Rocket agent skill bundled in `skills/datastar`,
  with copying instructions for Codex, Claude Code and other skill-capable agents.
- Opt-in `checked_events: true` derives event registration from final public
  handler clauses, checks literal local request helpers in `~STAR`, and rejects
  unknown names or wrong methods before SSE with HTTP 404/405.
- Experimental `~STAR` compiler and a StarView-owned template/node representation
  with initial HTML rendering and conservative HTML patch planning. The adapter
  is gated to Phoenix LiveView 1.2.12; no new page process or dependency upgrade.
- Optional coalesced rendering on the existing stream loop: `:render`,
  `:render_interval`, `:render_on_connect` and `StarView.invalidate/1`.
  `StarView.Page.handle_refresh/1` exposes the same lifecycle with
  `:refresh_interval`. Connections take a fresh snapshot after subscribing.
- Opt-in keyed `only_changed: true` element patches compare SHA-256 digests
  within a stream, with bounded tracking and a fresh comparison on reconnect.
- Explicit `connect(retry: ...)` policy for pages, preserving the existing
  default. `:always` opts into reconnecting clean stream endings; `:never`
  also sets a zero retry count for clients that retry network errors separately.
- A Phoenix/backend mental-model guide and reactive rendering example,
  crediting Jacob O'Bryant's article and Biff's Datastar implementation.

### Fixed

- Controller `StarView.Actions` helpers now preserve trusted JavaScript `:opts`,
  matching page/component event helpers. Fetch cancellation, payload filters
  and retry options are emitted rather than silently ignored.
- Stream identity examples use a document UUID rather than a copied
  session-storage ID, avoiding accidental replacement between duplicated tabs.

## v0.5.0

### Added

- Reconciled the unpublished local Page, Component and Router work into an
  optional stable Phoenix surface. Existing controller/core APIs remain supported.
- `StarView.Page` colocates mount, render, event and stream callbacks;
  `StarView.Component` colocates shared UI with marked event handlers.
- Page streams use the existing `StarView.Stream` lifecycle and coordinator;
  there is no separate receive loop or process framework. Optional
  `handle_disconnect/1` runs once after exact claim release on normal ends,
  takeover and raised callbacks, using the latest completed callback conn.
- New router macros default to POST-only events. Extra unsafe methods are
  explicit; page GET is opt-in and component GET is restricted to an explicit
  marked-module allowlist via additive `Dispatch` `:only` options.
- Page/component helpers reuse safe JSON/segment encoding. Browser pathname and
  component dispatch bases are validated as local paths before any request.
- Added `StarView.Test` assertions for emitted Plug/Phoenix SSE, including
  multiline JSON, nested expected keys and explicit null patches.
- Added a removable `mix star_view.setup.stream_page` PubSub demo with supervised
  ticker, routing and CSRF wiring, plus disconnect unsubscribe.
- Added the page/component guide and packaged usage rules. The published 0.4.0
  transport/security/installer fixes and dependency lock remain in place.
- Fixed optional installer task compilation in Plug-only consumers without
  Igniter; optional dependencies remain optional.

The new page/component/routing design adapts dstar's MIT work. The original
unpublished checkout remains separate; stale version and registry implementations
were not carried into the release.

## v0.4.0

### Compatibility and security changes

- Action expressions now use JSON double-quoted URL strings. Code that parses
  action text must support both quote styles instead of matching a single quote;
  prefer keeping module/event data rather than parsing expressions. Hand-built
  HTML must escape the action value with `Phoenix.HTML` instead of interpolating
  it into a double-quoted attribute. HEEx handles attribute escaping automatically.
- Custom `module: "$signal"` expressions are no longer accepted: `$`-prefixed
  overrides raise `ArgumentError` instead of being treated as executable
  JavaScript. The default `"$_star_view_module"` signal remains supported;
  other overrides are literal module names. Safe relative prefixes still
  normalize to local absolute paths.
- The optional Igniter integration now requires the tested `~> 0.8.4` API.
- Script attribute names must be plain names; pass values using map/tuple
  attributes instead of bare `type="module"` fragments.
- `StreamRegistry` is now a GenServer coordinator rather than Elixir's
  `Registry`. Use its public ownership API; direct `Registry.lookup/2` calls
  and `Registry` child options are incompatible.
- `start_stream/2` returns a halted HTTP 400/413 for invalid/oversized signals
  rather than opening an unkeyed stream. Raw/query signal input defaults to
  1,000,000 bytes, lower than the previous raw-body reader's 8 MB limit. Empty
  `datastar=` values and parsed non-object JSON wrappers now return HTTP 400.
- Legacy manual streams still receive `:replaced` exits and must trap exits to
  clean up. Owners that retain a retired claim past `:grace_ms` are killed;
  release the exact claim before returning to an HTTP/1 keep-alive request.
  The new `StarView.Stream` lifecycle uses tagged ordinary takeover messages.

### Added

- Added `StarView.Signals.fetch/2` and `StarView.fetch_signals/2` to return the
  consumed Plug conn with object-only signals and configurable raw/query limits.
- Added opt-in `StarView.Stream.open/2` and `run/2` for a shared SSE lifecycle:
  fixed-deadline liveness probes, adapter mailbox handling, exact-generation
  takeover, explicit claim release, and one normal disconnect callback.
- Added `StreamRegistry.release/1`, `unregister_stream/1`, `unregister_self/0`,
  and `owner/1` for explicit ownership cleanup and inspection.

### Fixed

- Action helpers percent-encode literal event/module values as route segments,
  serialize JavaScript strings, validate local prefixes, and encode dynamic
  modules. `module:` overrides are literal values; empty and dot segments raise.
- Stream claims are linearizable. Replacement handover no longer blocks on a
  keep-alive process dying, and released generations cannot be escalated later.
  Refused keyed claims return plain HTTP 503 before SSE starts.
- Both dispatchers thread the fetched conn and reject malformed/non-object
  signals with HTTP 400, oversized signals with 413 before invoking handlers.
- Closed SSE writes use `StarView.SSE.TransportError` and halt dispatch normally;
  `:econnreset` and `:epipe` also end normally through the shared disconnect
  predicate. Other transport failures and application exceptions still propagate.
- Formatting failures retain their original exception type rather than becoming
  transport errors. SSE values cannot inject CR/LF event fields or frames, and
  CR-only HTML/JSON patches retain the Datastar field prefix on every line.
- Script closing-tag escaping preserves message case and validates attribute
  names so attribute strings cannot break out of the generated tag.
- CSRF renaming reads DELETE's Datastar query signals, preserves existing body
  tokens, and prevents query `_csrf_token` from suppressing a valid signal token.
  Unfetched raw bodies remain readable when query tokens are copied to the CSRF
  header, and explicit existing CSRF headers retain precedence.
- Component patches supply HEEx change tracking without changing conn assigns.
- Installer updates replace whole function definitions and keep generated auth
  functions/attributes at module level.
- Dispatch and CSRF setup run independently of sample generation, so
  `mix star_view.install --no-example` still configures Phoenix events.
- Updated the dependency lock to current compatible releases.

URL, stream ownership, and CSRF improvements adapt concepts from dstar (MIT).

## v0.3.18

### Added

- Added `mix star_view.setup.auth`, which generates StarView-powered
  AshAuthentication magic-link pages: an `AuthController` sign-in page at
  `/auth/sign-in` and an `Auth.MagicSignIn` landing page at
  `/magic_link/:token`.
- The auth setup task replaces existing AshAuthentication `sign_in_route` /
  `magic_sign_in_route` calls with the generated pages and adds
  `sign_out_route AuthController` when the router uses
  `AshAuthentication.Phoenix.Router`.
- Added `Layout.auth/1` to the generated StarView layout — a full-height
  layout variant for auth screens. Existing layouts without it are patched by
  the auth setup task.
- Added a Phoenix auth guide covering the generated pages, router changes, and
  the required AshAuthentication code interfaces.

### Changed

- The generated StarView root layout now accepts `:theme`, `:html_class`, and
  `:body_class` attrs (`data-theme` on `<html>` plus class pass-through), and
  the placeholder headings were removed from the layout template.
- Updated README and guide installation examples for v0.3.18.

### Fixed

- `mix star_view.setup.web_module` no longer reports an "already exists" issue
  when the layout module was generated by a previous run.

## v0.3.17

### Changed

- Changed the generated StarView layout so `Layout.app/1` renders the document
  wrapper and disables Phoenix's controller root layout.
- Updated README and guide installation examples for v0.3.17.

### Fixed

- Added `StarView.Plug.RenameCsrfParam` before `:protect_from_forgery` when the
  installer patches the Phoenix browser pipeline.

## v0.3.16

### Added

- Added generated `Web.Components.StarView.Layout` modules for Phoenix
  projects.
- Added a Phoenix layout guide covering `Layout.app/1` and the StarView root
  layout.
- Added the SVG icon asset to the package.

### Changed

- Updated the generated `:star_view` web-module section to alias the generated
  layout and set it as the controller root layout.
- Updated the generated search controller to render through `Layout.app/1`.
- Updated README and guide installation examples for v0.3.16.

## v0.3.15

### Changed

- Changed `mix star_view.trust` to use `mkcert` for browser-trusted development
  certificates instead of trusting Phoenix's generated self-signed leaf
  certificate directly.
- Changed the Igniter installer to print the `mix star_view.trust --host ...`
  command and mkcert install instructions instead of queueing
  `mix phx.gen.cert`.
- Updated README and guide installation examples for v0.3.15.

## v0.3.14

### Fixed

- Stopped queueing `mix star_view.trust` from the Igniter installer because
  Igniter child tasks do not reliably receive interactive stdin. The installer
  now prints the direct command to run after installation.

### Changed

- Updated README and guide installation examples for v0.3.14.

## v0.3.13

### Fixed

- Fixed the `mix star_view.trust` confirmation prompt so the `[Y/n]` options
  appear on the active input line.
- Accepted confirmation answers case-insensitively and made sudo execution more
  explicit in the task output.

### Changed

- Updated README and guide installation examples for v0.3.13.

## v0.3.12

### Added

- Added `mix star_view.trust`, an optional setup task that can add the generated
  development host to `/etc/hosts` and trust the self-signed HTTPS certificate.

### Fixed

- Fixed generated development hostnames to use DNS-safe hyphens instead of
  underscores.

### Changed

- `mix igniter.install star_view` now queues the optional trust setup after
  certificate generation and documents that the step requires sudo privileges.
- Updated README and guide installation examples for v0.3.12.

## v0.3.11

### Fixed

- Fixed `mix igniter.install star_view` so the generated `star_view` web-module
  section is inserted as a top-level sibling after `controller`, not inside the
  `controller` function body.

### Changed

- Updated README and guide installation examples for v0.3.11.

## v0.3.10

### Fixed

- Restored README and generated docs logo references to the PNG logo asset.

### Changed

- Updated README and guide installation examples for v0.3.10.

## v0.3.9

### Fixed

- Changed the generated Phoenix dispatch route to use `StarView.Dispatch` with
  `alias: false`, avoiding the noisy `Elixir.StarView.Dispatch` form while
  still preventing Phoenix scope aliasing from resolving the plug as
  `<AppWeb>.StarView.Dispatch`.

### Changed

- Updated README and guide installation examples for v0.3.9.
- Switched the README and generated docs logo reference to the SVG asset.

## v0.3.8

### Changed

- Reworked HexDocs guides into a Phoenix-style sidebar with Introduction,
  Phoenix, Core Concepts, Comparison, Reference, and Release Notes sections.

## v0.3.7

### Changed

- `mix igniter.install star_view` now inserts the generated `star_view` web
  module section immediately after the existing `controller` section when
  possible.
- Cleaned up README, guide, and module docs so setup examples consistently
  describe StarView, `:star_view`, `mix dev`, and the current router setup.
- Removed the duplicate legacy `StarView.StarView` behaviour module from the
  public API surface.

## v0.3.6

### Fixed

- Fixed generated Phoenix routes so they do not get double-prefixed inside
  aliased router scopes.
- Updated the post-install certificate instruction to include the generated
  `.test` hostname, avoiding browser TLS errors with Phoenix's default
  localhost-only dev certificate.
- `mix igniter.install star_view` now automatically queues
  `mix phx.gen.cert <otp_app>.test localhost` when HTTPS setup is enabled.

## v0.3.5

### Fixed

- Fixed the generated search controller to use `use MyAppWeb, :star_view`
  instead of the old `:starview` section name.

### Changed

- `mix igniter.install star_view` now adds a dedicated `star_view` section to
  the Phoenix web module instead of patching the existing `controller` section.
- The generated Phoenix endpoint URL now includes the HTTPS dev port
  (`https://<otp_app>.test:4001`) so `mix star_view.server` opens the actual
  listening endpoint.
- Renamed the development server task to `mix star_view.server` and added
  `mix dev` as a shortcut.

## v0.3.4

### Fixed

- Fixed `mix igniter.install star_view` with the default Phoenix example
  enabled by rendering the generated search controller template with the
  expected EEx bindings.
- Fixed the generated search controller template so it no longer nests a
  `defmodule` inside the module generated by Igniter.

## v0.3.3

### Added

- Added `mix star_view.dev`, a convenience task that starts `mix phx.server`
  with browser opening enabled. Use `--no-open` to start the server without
  opening the browser.

### Changed

- `mix igniter.install star_view` now configures the Phoenix endpoint URL for
  dev as `https://<otp_app>.test`, so Phoenix's browser-open flow lands on the
  expected local app host.
- Updated the StarView installer notice and README quick-start instructions to
  point users at `mix star_view.dev`.

## v0.3.2

### Changed

- Improved the guide documentation.

## v0.3.1

### Changed

- `StarView.mount/2` signature is `(conn, params)` — conn first argument to
  work with Phoenix's default action dispatch (`get "/", SearchController`).
- Only `handle_event/3` is optional — `mount/2` and `render/1` are now required
  callbacks on `StarView`.
- SearchController demo template extracted to `priv/templates/search_controller.ex.eex`
  for easier maintenance. The generated controller now demonstrates smart change
  detection with `maybe_patch_list/2` and `data-text` for client-side signal display.

### Added

- `guides/comparison/liveview_vs_star_view.md` — side-by-side comparison of
  StarView vs LiveView using the same active search example, including transport
  trade-offs (SSE vs WebSocket) and event payload differences (JSON vs forms).

## v0.3.0

### Changed

- **Breaking:** Renamed `StarView` callbacks for clarity and consistency with LiveView:
  - `show/2` → `mount/2` (sets up initial signals and assigns)
  - `html/1` → `render/1` (renders the HEEx template)
  - `handle_event/3` argument order changed from `(conn, event, signals)` to
    `(event, signals, conn)` to match the Phoenix LiveView convention

## v0.2.1

### Changed

- Improved the Search demo example.

## v0.2.0

### Changed

- `mix igniter.install star_view` delegates to composable setup subtasks
  instead of duplicating logic, removing ~270 lines of duplicated code.

## v0.1.2

### Fixed

- `mix igniter.install star_view` now correctly detects Phoenix projects and
  applies all patches (web module, HTTPS config, routes, demo controller).

### Changed

- Installer split into composable setup subtasks
  (`star_view.setup.streaming`, `star_view.setup.datastar`,
  `star_view.setup.web_module`, `star_view.setup.search_controller`) for
  better modularity and independent invocation.

## Early development notes

### Added

- `StarView.StreamRegistry` for opt-in per-tab SSE stream deduplication
  (ported from [dstar](https://github.com/RicoTrevisan/dstar), MIT).
- `StarView.start_stream/2` and `StarView.check_connection/1` on the facade.

### Changed

- `StarView.read_signals/1` now returns a bare signal map (like dstar); plugs
  should use `StarView.Signals.read/1` for `{:ok, map()} | {:error, term()}`.
- Removed `StarView.Actions.form/4` and Phoenix `post_form/put_form/patch_form`
  helpers in favor of the `csrf` signal + `StarView.Plug.RenameCsrfParam` flow.
