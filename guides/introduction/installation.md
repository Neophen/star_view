# Installation

StarView can be installed with Igniter, or wired manually in a Phoenix project.

## Quick Install

```bash
mix igniter.install star_view
```

The installer sets up the recommended Phoenix development flow:

- Adds the dependency.
- Adds `StarView.StreamRegistry` to your supervision tree.
- Adds a dedicated `star_view` section to your web module after `controller`.
- Generates `YourAppWeb.Components.StarView.Layout` for the StarView document
  layout and page wrapper.
- Configures HTTPS and `https://<hyphenated-otp-app>.test:4001` as the dev URL.
- Provides `mix star_view.trust` to add the local host entry and generate a
  browser-trusted HTTPS certificate with `mkcert`.
- Patches your router with `/search` and `/ds/:module/:event` routes.
- Generates a sample search controller.
- Provides `mix dev`, which delegates to `mix star_view.server`.

Install `mkcert` first:

```bash
brew install mkcert nss
```

Then run the trust step directly after install:

```bash
mix star_view.trust
```

It adds the `.test` host to `/etc/hosts`, runs `mkcert -install`, and writes
`priv/cert/selfsigned.pem` plus `priv/cert/selfsigned_key.pem`. It may prompt
for sudo privileges. Run it before `mix dev` so Phoenix can find the configured
certificate files.

Skip parts you do not want:

```bash
mix igniter.install star_view --no-stream-dedup --no-https --no-example
```

| Option | What it does |
| --- | --- |
| `--no-stream-dedup` | Skips adding `StarView.StreamRegistry` to your supervision tree. |
| `--no-https` | Skips StarView dev URL and HTTPS configuration. |
| `--no-example` | Skips generating the sample controller/handler. |

## Manual Dependency

```elixir
def deps do
  [
    {:star_view, "~> 0.3.18"}
  ]
end
```

Add `StarView.StreamRegistry` to your supervision tree if you want per-tab
stream deduplication:

```elixir
children = [
  StarView.StreamRegistry,
  # ...
]
```

The remaining manual Phoenix setup is covered in the Phoenix web module and
layout guides.
