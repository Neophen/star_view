# Troubleshooting

First separate the initial HTTP page, the request's signal input, and the SSE
response. The browser network panel should show a normal HTML page followed by
`text/event-stream` for a valid event. The server cannot change HTTP status once
that stream has started.

| Symptom | Cause and fix |
| --- | --- |
| `Plug.Conn.AlreadySentError` in a denied event | Dispatch already called `send_chunked(200)`. Return the conn or patch the existing error signal. Put route authentication/HTTP rejection before dispatch. `mount/2` can still return an HTTP error before streaming. |
| Event lacks a signal that exists in the browser | A leading underscore marks a Datastar signal client-only. Use a non-underscore key for submitted form data, CSRF, or `tabId`. The dynamic `_star_view_module` is intentionally client-only because it constructs the URL. |
| Visibility/position flickers or a region stops reacting | `data-show` controls `style.display`; a reactive `data-attr:style` on the same element can overwrite it. Put visibility on a wrapper and positioning on a child. A static initial `style="display: none"` with `data-show` is a different case. |
| `data-text` does unexpected DOM work | Give it an empty element. For server-rendered initial content, render ordinary HEEx text and update that component, or let Datastar own an empty text node. |
| URLs break when names contain quotes or slashes | Use action helpers for dispatch URLs and `StarView.JSON.encode!/1` for values inside custom expressions. HEEx attribute escaping does not itself quote a JavaScript value. |
| Code cannot extract an action URL after upgrading | v0.4.0 helpers use JSON double quotes, not hand-built single quotes. A regex/string match for only `@post('...')` is obsolete. Keep module/event data rather than reverse-parsing expressions. |
| A button's raw HTML breaks after upgrading | Action expressions now contain JSON double quotes. HEEx expression attributes escape them; hand-built HTML must HTML-escape the whole expression with `Phoenix.HTML.html_escape/1`. Do not interpolate it directly into a double-quoted attribute. |
| CSRF still appears in GET/DELETE URLs after adding a header | A header does not remove the public `csrf` signal. Exclude it with `filterSignals`, keeping the underscore exclusion too, or redact the complete `datastar` query from logs. |
| Script attributes such as `type="module"` raise | Pass attribute values as tuples or a map, such as `attributes: [{"type", "module"}]`. A bare string is a validated attribute name, not an HTML fragment. The SDK handles value escaping. |
| A dynamic action reports an invalid/missing module | Initialize `$_star_view_module` explicitly using `Actions.encode_module/1`, or use an explicit controller action helper. Custom `$signal` overrides are rejected; `module:` is literal data except for the standard default signal. |
| HTTP 400 before any SSE event | Signals must be a JSON object. Arrays, scalars, null, malformed JSON, and an empty `datastar=` are rejected. Valid objects still need application validation of keys, types, and referenced records. |
| HTTP 413, or parsed requests bypass a custom raw limit | Raw/query input defaults to 1,000,000 bytes. Set `max_bytes:` when fetching manually and configure `Plug.Parsers`' body length too. Parsed maps no longer retain their original byte size. |
| Later middleware sees an empty or unfetched body | Thread the conn returned by `Signals.fetch/2` or `StarView.fetch_signals/2`. The compatibility read API discards it. |
| CSRF fails only for a raw body with a query/params token | Run the renaming plug before protection. v0.4.0 preserves the raw body and sets `x-csrf-token` from the available token; an explicit existing header takes precedence. GET is read-only; DELETE still needs CSRF protection. |
| A handler is not found, or its conn argument looks like a string | Phoenix marker dispatch uses `handle_event(event, signals, conn)`. Allowlisted Plug dispatch uses `handle_event(conn, event, signals)` and needs `modules:`. Both return 404 for an unavailable target. |
| A component calling `Phoenix.Component.assign/3` fails during a patch | v0.4.0 adds missing `:__changed__` metadata to plain Plug assigns in `patch_element/3`. Use `Plug.Conn.assign/3` for conns and `Phoenix.Component.assign/3` for component maps. Supply all required assigns on each event. |
| Stream returns HTTP 503 | A usable keyed claim needs a supervised `StreamRegistry`. Check that `open/2` returned `{:ok, conn}` before subscribing. Do not silently continue as though the stream opened. |
| An old takeover interrupts a later keep-alive request | Prefer generation-aware `StarView.Stream.open/2` and `StarView.Stream.run/2`. Manual streams must synchronously release their exact claim. Old-generation cleanup cannot release a new owner. |
| Busy PubSub traffic hides a disconnected client | Use the library loop's fixed-deadline probes. A hand-written `receive ... after` that restarts its timeout per message can postpone probes forever. |
| An SSE write reports `:timeout` | It is a transport failure, not the ordinary disconnected case. Typed `TransportError` distinguishes it from `:closed`, `:econnreset`, and `:epipe`; investigate and let it propagate. Exceptions with similar text are not transport errors. |
| Subscriptions remain after a handler exception | `StarView.Stream.run/2` releases its claim on exceptions, but its normal disconnect callback is not an exception finalizer. Put application resource cleanup in `try ... after`, as in the PubSub example. |

The SDK speaks the Datastar server protocol. It does not install application
policies, save browser state, supply licensed Pro assets, or replay missed
PubSub events. Verify the [counter](../examples/phoenix_counter.md), [manual endpoint](../examples/plug_endpoints.md),
and [stream](../examples/pubsub_stream.md) examples against the client you bundle.
