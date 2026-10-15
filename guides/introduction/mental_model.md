# Thinking in Phoenix, Datastar and StarView

A StarView page starts as an ordinary Phoenix request. Your browser pipeline
resolves the session, actor, tenant and locale. A controller loads authorized
application data and renders HEEx. Datastar makes that HTML interactive, and
StarView lets subsequent requests return signals and HTML patches over SSE.

The useful shift is to think about the HTML you want to show after an operation.
The application still owns its business actions, validation and policies.

## Start with the controller and backend

An initial GET loads the page. An event is a new request with its own conn;
it does not inherit the previous request's assigns. Load the context and data
needed for that event, authorize the operation, call your application's action
layer, and render the resulting state.

For an approval button, the flow is:

1. The browser submits an order identifier and any edited fields.
2. The handler validates those inputs and uses the actor and tenant resolved
   by the request pipeline to call an authorized approval action.
3. On success, the handler reloads the relevant summary and patches its HEEx
   component. On failure, it patches the existing error region.

In an Ash application, keep the operation in an Ash action or domain interface.
StarView is the transport between that backend and the rendered page; it adds
no persistence layer or business authorization policy. An earlier page load
does not authorize a later event, and a submitted tenant ID is not trusted scope.

The dispatcher starts SSE before invoking the event handler. At that point the
HTTP status and headers have been sent: return the conn or patch an error state.
Reject with an HTTP status, set cookies or redirect through a normal HTTP
response before streaming starts. See [manual endpoints](../examples/plug_endpoints.md).

## Put each kind of state where it belongs

| State | Owner |
| --- | --- |
| Saved records, permissions and business rules | Application backend |
| Data needed to render the current response | Conn assigns |
| Input drafts, visibility and small reactive interactions | Datastar signals |
| A reusable widget's browser state, typed props and cleanup | Datastar Rocket, when appropriate |

`assign/3` prepares server rendering data. `signal/3` also exposes a value to
the browser. Use the latter deliberately: sending entire loaded records as
signals increases request payloads and exposes data the page may not need.
Browser signals are untrusted, including ones initialized by the server.

Plain Datastar markup is enough for most forms and inline actions. Rocket can
help a reusable control manage timers, drag state or browser integrations.
Check your bundled Rocket beta API and its signal scoping before adopting it.
`StarView.Component` instead colocates Phoenix markup and server handlers; it
does not create persistent client state or a component process.

## Choose direct responses or live refreshes

For an ordinary interaction, patch the affected region directly from the event
response. A persistent subscription is useful when changes can also come from
other users, workers or integrations.

For that live page, commit the backend change, then publish a scoped invalidation.
The stream subscribes before taking its initial snapshot. On invalidation it
reloads authorized data and renders the current view. Coalesce bursts and use
`only_changed: true` for an independently owned region when identical patches
can safely be skipped. A reconnect takes another snapshot rather than assuming
every event was delivered. Follow the [reactive rendering example](../examples/reactive_rendering.md).

Derive subscriptions from trusted actor/tenant context, keep reads bounded,
and recheck permissions during long-lived streams. Authorization captured at
connection time can become stale. Avoid broadcasting a global refresh after
every database transaction: most pages need a narrower topic.

Keep the connection initializer outside the region being patched. Initialize
draft signals only if missing, and choose explicit reset points. If another
request or browser code can change the same region, an unchanged server render
alone cannot prove the browser still has that HTML.

## Inspiration and integration choices

Jacob O'Bryant's [Understanding Datastar](https://biffweb.com/p/understanding-datastar/)
describes a model where “the page is rendered by a single function”. That is a
useful way to think about rendering a fresh view of backend state instead of
maintaining a second application model in the browser.

We also studied [Biff's Datastar implementation at commit 7f6cad6](https://github.com/jacobobryant/biff/tree/7f6cad6738ab743ee23957dd1b11d130db48d94a/libs/datastar).
Its render loop, refresh coalescing, unchanged-output comparison and reconnect
snapshot informed StarView's optional refresh workflow. StarView keeps its
existing Plug lifecycle, scoped PubSub choices and controller architecture.
Biff's global refresh mechanism and unconditional Brotli encoding are not
requirements for that model.

Compression belongs to the deployed HTTP stack. Check the actual origin,
proxy and CDN responses, negotiate supported encodings, and measure SSE flush
latency before adding compression. Returning a conn through StarView does not
by itself enable Brotli. Keep shared responses independent of browser-owned
drafts, and make mutation retry policy explicit in your application.
See [compression in the HTTP stack](../phoenix/compression.md) for deployment checks.
