# API Overview

The full API is documented in the module reference. These are the primary
entry points.

```elixir
StarView.start(conn)
StarView.start_stream(conn, user_id)
StarView.check_connection(conn)
StarView.Stream.open(conn, key: user_id)
StarView.Stream.run(conn, connect: &subscribe/1, info: &handle_update/2)
StarView.StreamRegistry.release(conn)
StarView.fetch_signals(conn, max_bytes: 1_000_000)

StarView.patch_elements(conn, html, selector: "#target", mode: :replace)
StarView.remove_elements(conn, "#target")

StarView.patch_signals(conn, %{count: 1})
StarView.patch_signals_raw(conn, ~s({"count":1}))
StarView.remove_signals(conn, ["user.email"])

StarView.execute_script(conn, "console.log('done')")
StarView.redirect(conn, "/next")
StarView.console_log(conn, "debug")
StarView.read_signals(conn)
```

StarView 0.6.0 also supports optional `:render`, `:render_interval` and
`:render_on_connect` on `StarView.Stream.run/2`, with `StarView.invalidate/1`
to request a coalesced refresh. `c:StarView.Page.handle_refresh/1` uses the same
loop. Keyed `only_changed: true` element patches can skip identical output
for regions exclusively owned by that stream. See
[reactive rendering](../examples/reactive_rendering.md) for the ownership limits.

For Phoenix controller helpers, see `StarView.Controller` and
`StarView.Dispatch`.

`fetch_signals/2` returns `{:ok, signals, conn}` or `{:error, reason, conn}`.
Thread that conn when raw request bodies are read. The compatibility
`read_signals/1` returns only the map and raises on invalid input.

Action helpers encode event and literal module values as single route segments.
Prefixes must be local application paths; `"admin/"` normalizes to `"/admin"`. Exact empty, `.` and `..`
segments raise because browser normalization would change the route.

`StarView.SSE.TransportError` distinguishes failed writes from application errors.
Dispatch halts `:closed`, `:econnreset`, and `:epipe` writes normally. Timeouts and
other failures propagate.


## Optional Phoenix page layer (v0.5.0)

- `use StarView.Page` — `mount/2`, `render/1`, `handle_event/3`,
  `handle_connect/2`, `handle_info/2`, optional `handle_disconnect/1` and
  `stream_key/1`. The Page plug uses the shared stream lifecycle.
- `use StarView.Component` — function components and marked event handlers.
- `StarView.Router.star_view/2` and `star_view_components/1` — explicit routes.
- `StarView.Page.Helpers.event/2`, `connect/1` and `patch/4` — safe URLs and
  component patches. `:opts` is trusted developer JavaScript text.
- `StarView.Page.Assigns` — one assign API for conns and component maps.

See [the complete examples](../phoenix/pages.md). `handle_disconnect/1` runs once
on normal and exceptional stream ends, after release, using the latest completed
callback conn. This is distinct from manual `StarView.Stream.run/2`'s normal-end
`:disconnect` callback.

`StarView.Test` parses emitted SSE and asserts signal/element patches in Plug
and Phoenix tests. `patched_signals/1` combines emitted JSON documents, including
null removals; it does not reconstruct browser state or apply `onlyIfMissing`
against initial signals.
