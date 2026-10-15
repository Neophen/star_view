# Live resources and performance

The reviewed Biff implementation at
[`7f6cad6`](https://github.com/jacobobryant/biff/tree/7f6cad6738ab743ee23957dd1b11d130db48d94a/libs/datastar)
coalesces refresh epochs, rerenders a resource, suppresses identical output and
flushes a stream compressor. These are useful mechanisms, not a requirement to
copy the entire architecture or add a live connection to every page.

## Choose the lifecycle

Direct event responses fit ordinary actions. Use an ongoing read stream when
updates must arrive independently of the user's current request. Subscribe
before the initial snapshot, invalidate after committed changes, and reload
current authorized state. Notifications are invalidations, not trusted records.

Use scoped PubSub topics and the SDK's existing stream loop. Coalesce bursts
with timers so ownership probes and disconnect work stay responsive. Release
subscriptions on disconnect and get a fresh baseline on reconnect. Reauthorize
long-lived reads as needed. Do not add a GenServer solely to wrap stateless
functions; use a supervised, bounded process only for actual state/lifetime needs.

Browser tab IDs are untrusted identity inputs, not authorization or storage.
Combine them with server-chosen scope. Session storage may be copied when a tab
is duplicated; a per-document ID avoids that when reload persistence is not
needed. Test duplicate ownership and delayed disconnect cleanup.

## Suppression and drafts

Keyed `only_changed` output suppression compares what a stream emitted, not
the current browser DOM. Keep regions independently owned and non-overlapping;
other requests and scripts can invalidate the baseline. Native template diffs
also require one owner and a valid previous snapshot. Neither is event replay.

Keep signal/stream initialization outside refreshed content where possible.
Initialize drafts only if missing. Reset them deliberately for accepted writes,
record changes and explicit reloads. Preserve stable IDs, focus, selection,
scroll and Rocket/editor ownership. Large morphs still need browser verification.

Separate read-stream reconnection from mutation retries. Check the installed
client's generated request options: in the reviewed Datastar Pro 1.0.4 bundle,
disabling network-error retries required both `retry: 'never'` and
`retryMaxCount: 0`. Choose a read reconnect policy deliberately; a stream ending
cleanly need not have the same policy as a failed write. Use existing action
idempotency for retryable durable operations.

## Measure before optimizing

Measure query count, render cost, patch bytes, connection memory and update
bursts on realistic data. Batch reads and use existing caches with clear
tenant/actor/locale boundaries. Keep reads out of template loops and do not
invent a parallel browser record store or automatic database dependency tracker.

Compression must negotiate encodings and preserve per-event/heartbeat flushing
through the adapter and proxy. Inspect headers and time-to-first-event on a
multi-event stream before changing configuration. Biff's unconditional Brotli
headers are not a drop-in Plug integration. No new compressor dependency or
infrastructure change is justified solely by the reference implementation.

Cache content-hashed assets immutably where configured. Give personalized HTML
and data appropriate private cache boundaries. A smaller wire payload does not
prove lower server cost; the native STAR prototype still evaluates all bindings.
