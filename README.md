<p align="center">
  <img src="https://raw.githubusercontent.com/Neophen/star_view/main/assets/logo.png" alt="StarView logo" width="128" />
</p>

# StarView — Datastar SSE for Plug and Phoenix

<p align="center">
  <a href="https://hexdocs.pm/star_view"><img src="https://img.shields.io/github/v/release/Neophen/star_view?color=lawn-green" alt="Version" /></a>
  <a href="https://hex.pm/packages/star_view"><img src="https://img.shields.io/hexpm/dw/star_view?style=flat&label=downloads&color=blue" alt="Downloads" /></a>
  <img src="https://img.shields.io/badge/Erlang/OTP-27+-blue" alt="Requires Erlang/OTP 27+" />
  <a href="https://github.com/Neophen/star_view/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Neophen/star_view" alt="MIT license" /></a>
</p>

StarView sends [Datastar](https://data-star.dev) Server-Sent Events from ordinary
Plug requests. Phoenix helpers let you update browser signals and patch HEEx
function components while threading the current connection.

It requires Elixir 1.17+ and Erlang/OTP 27+; JSON uses OTP's built-in `:json`.
Phoenix and its component support are optional integrations. StarView owns the
server protocol; your application owns its Datastar client, authentication,
authorization, and durable business actions.

## What it solves

| Repeated work | StarView's API |
| --- | --- |
| Keep a render assign and browser signal in sync | `signal/3` assigns and patches together |
| Render one changed region after an event | `patch_element/3` accepts a HEEx function component |
| Read raw signal JSON without losing the updated conn | `Signals.fetch/2` returns the conn on success and error |
| Construct dispatch URLs with quotes, slashes, or Unicode | `Actions` encodes segments and JavaScript string values |
| End PubSub streams without leaking ownership across keep-alive requests | `StarView.Stream.open/2` and `StarView.Stream.run/2` own probes and exact claim release |

For one-module page callbacks or shared UI with event handlers, v0.5.0 adds the
optional `StarView.Page`, `StarView.Component` and `StarView.Router` surface.
Follow [pages, streams and components](guides/phoenix/pages.md). Existing
controller entrypoints remain supported.

Version 0.6.1 improves experimental `~STAR` rendering and common template syntax.
The [native-template guide](guides/examples/star_templates.md#rendering-performance-in-061)
includes measured builder, schedule and film workloads and explains why smaller
patches, rendering speed and retained-baseline costs need separate evaluation.

Start with [Thinking in Phoenix, Datastar and StarView](guides/introduction/mental_model.md)
for the controller/backend model and the inspiration from Jacob O'Bryant's Biff.
StarView 0.6.0 adds optional [coalesced reactive rendering](guides/examples/reactive_rendering.md)
to the existing stream lifecycle.

Version 0.7.0 compiles static HTML and evaluated values into native rendering
programs. Compiled-tree inspection uses `Template.nodes/1`; the planner still
materializes both trees. Read the [representation and performance notes](guides/examples/star_templates.md#compiled-rendering-in-070)
before upgrading experimental callers.

The separate experimental [STAR template compiler](guides/examples/star_templates.md)
uses `~STAR` and a StarView-owned representation for initial HTML and selected element
patches. It currently requires the tested LiveView 1.2.12 parser adapter.
Opt-in [checked events](guides/core/checked_events.md) validate literal local
helpers such as `post("save")` against the actual handler names and methods.

The checkout includes a copyable [Datastar agent skill](guides/introduction/agent_skill.md)
at `skills/datastar/`, bundled in Hex builds, for Codex, Claude Code and other skill-capable agents.

A short Phoenix event looks like this:

```elixir
def handle_event("increment", %{"count" => count}, %{method: "POST"} = conn)
    when is_integer(count) and count >= 0 and count < 1_000_000 do
  conn
  |> Plug.Conn.assign(:label, "Count")
  |> signal(:count, count + 1)
  |> patch_element(&summary/1)
end

def handle_event(_event, _signals, conn), do: conn
```

Dispatch validates signal input and starts SSE before calling that handler.
`signal/3` sends its update immediately; there is no final flush step. The
submitted count is browser UI state in this example. A saved counter should be
updated by an authorized application action using trusted actor/tenant context.

Follow the [complete counter example](guides/examples/phoenix_counter.md) for the
page mount, layout, component, validation, and error state.

## Installation

For a Phoenix project with Igniter:

```sh
mix igniter.install star_view
```

The installer adds the dependency, dedicated `:star_view` web entrypoint,
layout, POST dispatch route and CSRF renaming plug, sample search page/controller, optional stream registry,
and HTTPS development setup. To skip optional parts:

```sh
mix igniter.install star_view --no-stream-dedup --no-https --no-example
```

`--no-example` skips the sample search page/controller. It retains the default
POST dispatch route and CSRF plug. For an existing manual integration,
`mix star_view.setup.dispatch` adds that routing/plug setup independently.

When using the generated HTTPS development configuration, install `mkcert`
and run `mix star_view.trust` before `mix dev`. The trust step writes local
certificate files and may require permission to update the host entry. See
[installation](guides/introduction/installation.md) and
[development server](guides/phoenix/development_server.md) for the full setup.

For manual installation:

```elixir
def deps do
  [{:star_view, "~> 0.7.0"}]
end
```

For Phoenix, add the [dedicated web entrypoint](guides/phoenix/web_module.md)
and [layout](guides/phoenix/layout.md), then route the dispatcher through your
browser pipeline:

```elixir
pipeline :browser do
  # Existing session/authentication plugs run before dispatch.
  plug StarView.Plug.RenameCsrfParam
  plug :protect_from_forgery
end

scope "/", MyAppWeb do
  pipe_through :browser
  post "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

An existing Phoenix browser pipeline also needs its normal plugs and the
endpoint's JSON parser. The fragment above shows the CSRF ordering, not a
replacement for the complete pipeline. Cookie-authenticated mutations need
CSRF protection, and each event still needs application authorization.
The default route handles POST. If using GET, DELETE, PUT, or PATCH helpers,
register those verbs explicitly and check the method in shared event handlers;
see [action routing](guides/core/actions.md). GET must remain read-only.

## Bundle the browser client

Import your chosen Datastar ES module from the application's asset entrypoint,
for example:

```javascript
// assets/js/app.js (or the application's public entrypoint)
import "../vendor/datastar.js"
```

The path is an application-owned, locally acquired module. Preserve its license
notice, follow its version/API requirements, and load the client once. The
installer's layout includes a free CDN client by default; remove that script
when bundling locally. StarView does not ship or grant a license for Datastar Pro.

Keep simple controls as server-rendered HTML with ordinary Datastar signals.
Consider [Rocket](https://data-star.dev/reference/rocket) for reusable controls
that need their own browser state and lifecycle; its API is currently beta.
Rocket provides browser state and lifecycle. `StarView.Component` colocates
Phoenix function components with server event handlers; it creates no server
process or persistent component state.

## Choose your server integration

| Integration | Handler contract | Streaming starts |
| --- | --- | --- |
| Phoenix marker dispatcher | `handle_event(event, signals, conn)` on a marked controller/component | Before the callback |
| Optional page routes | `StarView.Page` mount/render/event callbacks; optional connect/info/disconnect | Before event/connect callbacks |
| Allowlisted `StarView.Plug.Dispatch` | `handle_event(conn, event, signals)` in a `modules:` entry | Before the callback unless `start: false` |
| Manual Plug endpoint | Fetch/validate with your own Plug | When you call `StarView.start/1` |
| Long-running subscription | `StarView.Stream.open/2`, then `StarView.Stream.run/2` callbacks | On successful `open/2` |

A dispatchable marker selects a handler; it does not authorize its operations.
The [manual endpoint guide](guides/examples/plug_endpoints.md) explains input
limits, callback orders, auth gates, and why HTTP rejection must happen before
SSE. Once streaming starts, patch the existing error state instead of calling
`put_status`, setting cookies, or sending another HTTP response.

## Assigns, signals, and HTML

| Operation | Server component sees the value | Browser sees the value |
| --- | --- | --- |
| `Plug.Conn.assign(conn, :key, value)` | Yes | Only if rendered as HTML |
| `StarView.Controller.signal(conn, :key, value)` | Yes | JSON signal, initially or during SSE |
| `StarView.patch_signals(conn, map)` | No assign update | JSON signal patch |

Component code uses `Phoenix.Component.assign/3` for its assigns map. In
v0.4.0, `patch_element/3` supplies missing render metadata for plain Plug
assigns, so the same function component can derive values during initial
rendering and during an event patch. Each event is a new request; load/set every
assign its component requires. See [component patches](guides/core/patch_element.md).

## Worked examples and diagnostics

- [Phoenix counter](guides/examples/phoenix_counter.md): complete action, HEEx component, validation, and partial DOM update.
- [Actions and quoted values](guides/core/actions.md): explicit targets, module signal contract, encoded paths, and double-quote migration.
- [Manual Plug endpoints](guides/examples/plug_endpoints.md): thread fetched conns and reject bad input before streaming.
- [PubSub streams](guides/examples/pubsub_stream.md): authentication, subscription cleanup, exact ownership, and fixed-deadline probes.
- [Reactive rendering](guides/examples/reactive_rendering.md): scoped invalidation, reconnect snapshots, coalescing and unchanged-patch detection (added in 0.6.0).
- [Compression](guides/phoenix/compression.md): check HTTP server, proxy and CDN compression while preserving SSE latency.
- [Troubleshooting](guides/reference/troubleshooting.md): malformed params, silent client mistakes, CSRF, stream 503s, and transport errors.

The optional [AshAuthentication magic-link generator](guides/phoenix/auth.md),
`mix star_view.setup.auth`, renders StarView sign-in pages and exchanges the token through a
normal form POST so session cookies are set before redirecting. It requires
the application's AshAuthentication resource/strategy and domain interfaces.

## API and compatibility

Start with the [API overview](guides/reference/api_overview.md) or
[HexDocs](https://hexdocs.pm/star_view). Raw/query signal input defaults to a
1,000,000-byte limit and must be an object. Bound already-parsed input with
`Plug.Parsers` too. Prefer `StarView.fetch_signals/2` when raw bodies are involved.

Action strings in v0.4.0 use JSON double quotes. Avoid reverse-parsing them
with a single-quote-only string matcher. Use HEEx expression attributes or
HTML-escape the whole expression when constructing raw HTML. Expected closed/reset/broken-pipe SSE
writes end normally through typed transport errors; timeouts and application
exceptions remain errors. Read the [changelog](CHANGELOG.md) when upgrading
this pre-1.0 package, especially from [Dstar](guides/reference/migration_from_dstar.md).

## License

StarView is MIT licensed. The action-safety and stream-lifecycle implementations
include work adapted from [dstar](https://github.com/ricotrevisan/dstar),
Copyright (c) 2025 Rico Trevisan. Attribution is retained in source and [LICENSE](LICENSE).
Datastar and any licensed client bundle retain their own terms.

## Test emitted updates

`StarView.Test` adds `sse_events/1`, `patched_signals/1`,
`assert_patched_signals/2` and `assert_patched_element/2` for Plug/Phoenix tests.
These inspect emitted updates; they do not replay the browser's initial state.

`mix star_view.setup.stream_page` creates a removable PubSub demo page and ticker
with the page/component API and cleanup wiring. See
[pages and streams](guides/phoenix/pages.md).
