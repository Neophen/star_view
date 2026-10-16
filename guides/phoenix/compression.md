# Compression in the HTTP Stack

StarView writes SSE through the Plug adapter. It does not set
`Content-Encoding`, negotiate Brotli, or install a compression middleware.
Compression may already be active in your HTTP server, reverse proxy or CDN.
Check the deployed response before adding another layer.

## Check each response type and hostname

Check HTML, the fingerprinted JavaScript/CSS referenced by that HTML, and a
read-only SSE endpoint. Tenant domains may take different paths through your
infrastructure even when they share one Phoenix application.

```sh
curl -sS -o /dev/null -D - -H 'Accept-Encoding: br' https://example.com/
curl -sS -o /dev/null -D - -H 'Accept-Encoding: gzip' https://example.com/
curl -sS -o /dev/null -D - -H 'Accept-Encoding: zstd' https://example.com/
curl -sS -o /dev/null -D - -H 'Accept-Encoding: identity' https://example.com/
```

Look for `Content-Encoding`, `Vary: Accept-Encoding`, the response type and
cache policy. Measure the actual transferred bytes: an omitted
`Content-Length` on a streamed response does not mean the response is empty.
Never label an uncompressed body as compressed, and retain a fallback for
clients that do not advertise the preferred encoding.

## Keep static assets efficient

Run your normal production asset build, minification and Phoenix digest task.
Serve fingerprinted assets with a long immutable cache policy, and enable the
matching `Plug.Static` precompressed-file options only for files your build
actually produces. Phoenix's Gzip output does not also create Brotli files.

A proxy or CDN can negotiate compression for assets without adding a Brotli
dependency to StarView. Do not apply the static asset cache policy to
authenticated HTML or event streams.

## Preserve streaming latency

SSE must arrive while the connection remains open. Test several timed events
through the complete production path; a small response that finishes quickly
does not prove a persistent stream flushes promptly.

If compressing a stream, use a streaming compressor and flush after each event
without ending the compression context. Watch for proxy buffering and minimum
body-size thresholds that delay the first event. Also check clean disconnects
and reconnect snapshots. Do not add unconditional Brotli encoding based only
on an example from another language or adapter.

### Bandit 1.13.1 and Phoenix

[Bandit 1.13.1](https://hexdocs.pm/bandit/1.13.1/Bandit.html#t:http_options/0)
provides opt-in compression for chunked responses, including StarView SSE. Set a
compatible dependency floor and configure the Phoenix endpoint:

```elixir
# mix.exs
{:bandit, "~> 1.13.1"}

# config/config.exs, or the endpoint's existing runtime HTTP configuration
config :my_app, MyAppWeb.Endpoint,
  http: [http_options: [compress_chunked: true]]
```

Keep the dependency update and option together. Earlier Bandit versions reject
the option. Version 1.12.5 could select gzip or Zstandard but send a chunked
response uncompressed; testing only a deflate request missed the behavior of
normal browser headers. Version 1.13.1 supports gzip streaming and, when compiled
on OTP 29, Zstandard streaming, with per-chunk flushing and encoding fallback.
No StarView wrapper or rewrite of the browser's `Accept-Encoding` is needed.

Exercise a real listener using your endpoint's configured options. A
`Phoenix.ConnTest` connection does not run through Bandit's compressor. Gate
successive events so the client must decode the complete first event before the
server sends the next one. Include a heartbeat, an empty response, a large patch,
encoding refusals and cancellation/reconnection. Decode and compare the received
bytes; a header alone proves neither valid compression nor prompt delivery.
Repeat the live checks through each proxy/CDN path before claiming deployed
persistent-stream behavior.

Compressor state remains allocated until the response ends. Bandit documents a
few hundred KB per gzip/deflate response and up to roughly 3 MB for default
Zstandard. Measure memory and concurrency before enabling many persistent streams.
Sync flushes can also make a tiny signals-only response larger; compare realistic
patches rather than assuming every event saves bytes.

## Check the proxy and CDN

[Caddy's reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
documents immediate flushing for `text/event-stream`, and its
[encode directive](https://caddyserver.com/docs/caddyfile/directives/encode)
documents Gzip and Zstandard support. Verify the deployed Caddy version and
configuration rather than assuming the latest documentation matches it.
[Cloudflare](https://developers.cloudflare.com/speed/optimization/content/compression/)
can negotiate Brotli, Gzip and Zstandard for supported content types; ordinary
HTML compression is not evidence that `text/event-stream` uses the same path.

Choose compression based on measured bandwidth, CPU cost and event latency.
A working Gzip or Zstandard setup may already provide most of the benefit.
