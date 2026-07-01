# Linux StarView trust smoke test

This smoke test exercises `mix star_view.trust` end-to-end on Linux without
modifying the real `/etc/hosts` file or requiring a real `mkcert` installation.
It uses:

- `--hosts-file` pointed at temporary files
- `mix local.hex --force` and `mix deps.get` so it is runnable from a clean checkout/container
- a fake `sudo` to exercise and assert both cached `sudo -n` success and fallback sudo paths
- a fake `mkcert` that writes placeholder certificate files

Run locally on Linux:

```sh
bash test/docker/linux_trust_smoke_test.sh
```

Run from Docker:

```sh
docker run --rm \
  -v "$PWD":/workspace \
  -w /workspace \
  elixir:1.18 \
  bash test/docker/linux_trust_smoke_test.sh
```

If the exact image tag is unavailable, replace it with another recent Debian-based
Elixir image that satisfies the package's Elixir requirement.

For local syntax/debug runs on non-Linux hosts, set
`STAR_VIEW_ALLOW_NON_LINUX_SMOKE=1`. Non-Linux debug runs only exercise the cached
sudo path to avoid platform-specific fallbacks such as macOS `osascript`; do not
treat them as Linux coverage. Use the Docker command above for Linux behavior.
