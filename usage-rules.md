# StarView usage rules

## Choose the existing rendering boundary

StarView is a Plug SSE SDK with optional Phoenix integrations. Keep existing
controller pages on `use MyAppWeb, :star_view`. The opt-in `StarView.Page`
behavior colocates new page templates, events and stream callbacks;
`StarView.Component` colocates shared UI and its handlers. Plain display
components can continue using `Phoenix.Component` or the application's
component helper entrypoint without a dispatch marker.

See the worked [page/component guide](guides/phoenix/pages.md) and
[controller counter](guides/examples/phoenix_counter.md). Pages do not require
rewriting existing controllers or durable application actions.

## HTTP and authorization

- Route pages with `StarView.Router.star_view/2`, and shared marked components
  with `star_view_components/1` or the existing POST dispatch route.
- Put authentication, session, trusted actor/tenant resolution and CSRF
  protection in the route pipeline. Run `StarView.Plug.RenameCsrfParam` before
  `Plug.CSRFProtection`.
- Mount runs only for initial GET rendering. Authorize every mutation and stream
  subscription independently using the conn's trusted actor/tenant context.
- Router macros default to POST events. Extra unsafe methods use `:event_methods`.
  Page GET requires `get_events: true`; component GET requires a marked-module
  list (`get_events: [ReadOnlyComponent]`) that excludes other controllers.
- Use method guards for mutations. GET bypasses CSRF and must be read-only;
  a callback clause accepting every method can expose a write through GET.
- The library starts SSE before event/connect callbacks. Return the conn and
  chain patches; do not call `StarView.start/1` again in those callbacks.
- Validate submitted signal keys, types, bounds and referenced IDs. Browser
  signals are untrusted UI state, not the authorization boundary.
- Keep persistent operations in the application's native action layer, such as
  authorized Ash actions. StarView owns transport, not business policies.

## Signals and expressions

`StarView.Signals.fetch/2` returns `{:ok, signals, conn}` or
`{:error, reason, conn}`. Always thread the conn after consuming a raw body.
GET/DELETE read the `datastar` query parameter; other methods read the body.
Raw/query signals default to 1,000,000 bytes and must be JSON objects. The
compatibility `StarView.read_signals/1` returns a map and raises on errors.

Use `Actions` for controller URLs and `event/2` for page/component URLs.
Helpers encode literal path segments and JavaScript strings. `:opts` on the
page/component helper is trusted developer JavaScript emitted verbatim; never
assemble it from submitted signals. Use `StarView.JSON.encode!/1` for literal
values in custom expressions, and let HEEx escape HTML attributes.

```heex
<div data-signals:name={StarView.JSON.encode!(@name)}>
  <span id="name" data-text="$name"></span>
</div>
```

Keep `data-text` elements empty. Leading-underscore signals are client-only.
For header-based CSRF, also exclude the CSRF signal from URL requests; merely
adding `x-csrf-token` does not remove it from a Datastar GET/DELETE query.
Redact token-bearing URLs from logs. See the [CSRF guide](guides/core/csrf.md).

## Rendering and assigns

Use `~H` and Phoenix function components. `StarView.Page.Assigns` provides
`assign/2,3`, `assign_new/3` and `update/3` on Plug conns and Phoenix assigns.
`patch(conn, &component/1, assigns, opts)` adds missing HEEx change metadata.
Supply all required assigns when patching. Components targeted without a
selector need an explicit root ID.

Page rendering disables inherited root layouts before mount. The generated
StarView `Layout.app/1` owns the document; mount can explicitly select a Phoenix
root layout instead. Bundled client assets remain the application's job.

## Streams and cleanup

Prefer the shared `StarView.Stream.open/2` and `run/2` lifecycle for manual
streams. Pages call it for `handle_connect/2` and `handle_info/2`; do not build
another receive loop. It preserves adapter messages, probes on fixed deadlines
and releases exact ownership generations. A keyed claim failure returns 503
before SSE/subscription; malformed signals return 400/413.

For keyed replacement, supervise `StarView.StreamRegistry` and submit a usable
`tabId` signal. Compute keys from trusted request context. Use the public
registry ownership API; it is a coordinator, not Elixir's `Registry`.

A page's optional `handle_disconnect/1` runs once after release on normal ends,
takeover and callback errors. It receives the latest completed callback conn.
Unsubscribe there because HTTP/1 keep-alive owners can survive the stream. A
manual `Stream.run/2` normal-disconnect callback is not an exception finalizer;
use `try ... after` for manual application resource cleanup.

Closed/reset writes end normally. Timeout and application errors propagate.
Unmatched page `handle_info/2` heads are ignored with a warning; exceptions in
matched clauses propagate. Keep debug browser exception relay disabled in
production.

## Testing

Use `Plug.Test`/`Phoenix.ConnTest` and `StarView.Test` to inspect emitted SSE:

```elixir
import StarView.Test

# Start with the authenticated conn and CSRF setup from your ConnCase.
conn = Plug.Conn.put_req_header(conn, "content-type", "application/json")
conn = post(conn, "/counter/_event/increment", StarView.JSON.encode!(%{count: 0}))
assert_patched_signals(conn, %{count: 1})
assert_patched_element(conn, "#history")
```

These helpers inspect emitted patch documents, not final browser state or
`onlyIfMissing` behavior against initial signals. Cover authorization, method
guards, invalid input, transport failures, and stream resource cleanup.
