# Per-Tab Stream Deduplication

Add `StarView.StreamRegistry` to the supervision tree to give each user and tab
one active SSE stream. The coordinator orders claims atomically. A replacement
signals the old owner immediately and gives it 1,000ms to release before kill
escalation; configure the handover with `{StarView.StreamRegistry, grace_ms: n}`.

```elixir
children = [
  StarView.StreamRegistry,
  # ...
]
```

Initialize a public id once per document, outside the root you refresh:

```heex
<body data-signals:tab-id__ifmissing="crypto.randomUUID()">
```

Use `tab-id` in the attribute: HTML lowercases `tabId`, while Datastar camelizes
hyphenated names. Avoid an underscore prefix, which keeps the signal client-only.
The id remains stable across stream reconnects in this document. A full reload
gets a new id, and the old connection ends through disconnect detection. Avoid
using a blindly copied `sessionStorage` id: duplicated tabs inherit that storage
and can replace each other's streams. Persistent tab state needs an explicit
application identity/expiry policy; the registry does not provide storage or
authorize access to a resource.

Prefer the library-owned loop:

```elixir
case StarView.Stream.open(conn, key: current_user.id) do
  {:ok, conn} ->
    StarView.Stream.run(conn,
      connect: &subscribe/1,
      info: &handle_update/2,
      disconnect: &unsubscribe/1,
      idle_check: 30_000
    )

  {:error, conn} -> conn
end
```

Callbacks thread the current conn. The info callback may return `{:halt, conn}`.
Probes run on a fixed deadline even while messages arrive; Bandit's HTTP/2
flow-control messages remain available to the adapter. Stream takeovers use
ordinary messages carrying the exact generation, including for non-trapping
HTTP/2 owners. Stale messages cannot halt a newer stream on a reused keep-alive
process. Release happens before replacement and disconnect callbacks, so slow
cleanup cannot trigger an old generation's escalation.

`open/2` returns plain halted 400/413 for bad signals and 503 when a keyed claim
fails, before subscriptions or SSE begin. Missing or invalid `tabId` values retain
an ordinary unkeyed stream. A usable tab id is a non-whitespace string of 1–256
bytes.

Manual loops can still use `StarView.start_stream/2`, which returns a conn and
preserves the legacy `{:EXIT, pid, :replaced}` signal. Check that the returned
conn is chunked before subscribing, handle that exit, and always call
`StarView.StreamRegistry.release(conn)` when the stream ends. The release is
synchronous and generation-specific; a stale conn cannot remove a newer claim.
Prefer `StarView.Stream` for generation-tagged mailbox handling.

`replace_and_register/1` remains a manual-key helper returning `:ok` on a
successful claim or `{:error, reason}` when the coordinator is unavailable.
Pair it with `unregister_self/0` before reusing the process. Inspect ownership
through `StreamRegistry.owner/1` rather than `Registry.lookup/2`.

The coordinator and lifecycle concepts adapt dstar under its MIT license.
