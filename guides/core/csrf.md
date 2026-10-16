# CSRF

Put the CSRF token in a non-prefixed `csrf` signal and rename it before Phoenix's
CSRF protection runs. Cookie-authenticated mutations need CSRF protection even
when they use Datastar instead of forms.

```elixir
plug StarView.Plug.RenameCsrfParam
plug :protect_from_forgery
```

The generated client (Datastar v1.0.1) transports POST, PUT, and PATCH signals in
the JSON body, and GET/DELETE signals in the JSON `datastar` query parameter.
StarView uses that method contract; verify it when changing your bundled client.
See the [versioned client source](https://github.com/starfederation/datastar/blob/v1.0.1/library/src/plugins/actions/fetch.ts).
The v0.5.0 helper checks also used an application-owned Datastar Pro v1.0.4
bundle and confirmed the same GET/DELETE query behavior, `data-init`, the
`__window` event modifier and unlimited `retryMaxCount: Infinity` option.
StarView does not distribute licensed client assets.
DELETE still needs a valid CSRF token.
The renaming plug handles both channels. Existing body `_csrf_token` values take
precedence, followed by the body signal, Datastar query JSON, and a top-level
`csrf` param. A query `_csrf_token` cannot suppress a valid signal token.

GET is not checked by `Plug.CSRFProtection`; use it only for side-effect-free reads.
Tokens in the Datastar GET/DELETE query can appear in access logs and referrers.
Redact the complete `datastar` query value and set an appropriate Referrer-Policy.
Sending an `x-csrf-token` header alone does **not** remove the public `csrf` signal
from the query. To keep it out of the URL, exclude it from transmitted signals
too, retaining the default exclusion of underscore-prefixed signals:

```heex
<button
  id="preference-delete"
  data-on:click="@delete('/ds/my_app_web-preferences_controller/remove', {headers: {'x-csrf-token': $csrf}, filterSignals: {exclude: /(^|\.)_|^csrf$/}})"
>Remove preference</button>
```

This literal example assumes the page initialized `$csrf` and an authorized
`PreferencesController` handler exists. Register the matching route:

```elixir
scope "/", MyAppWeb do
  pipe_through :browser
  delete "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

Use `StarView.Actions.delete/3` for generated event URLs when no custom client
options are needed. For a read-only GET, omit `csrf` with the same filter; no
CSRF header is needed. See [action routing](actions.md) for method checks.

## Verify the transport in Phoenix tests

`Phoenix.ConnTest.build_conn/0` and `recycle/1` disable CSRF protection by default.
A passing POST alone therefore does not prove that a filtered request retained
its token. Re-enable protection after the final recycle in tests of this boundary:

```elixir
conn =
  conn
  |> Phoenix.ConnTest.recycle()
  |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
```

Send the token through the channel the browser uses, such as the JSON `csrf`
signal without an extra CSRF header. Check that this request succeeds and that
the same request without its token is rejected before SSE starts. Retain the
application's normal session, parser and browser pipeline in that check.
