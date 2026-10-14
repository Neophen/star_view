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
