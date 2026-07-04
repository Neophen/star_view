#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" && "${STAR_VIEW_ALLOW_NON_LINUX_SMOKE:-}" != "1" ]]; then
  echo "This smoke test is intended to run on Linux. Use the Docker command in test/docker/README.md." >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

mix local.hex --force
mix deps.get

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/cert"

cat > "$tmpdir/bin/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

mode="${FAKE_SUDO_MODE:-probe_success}"
log_file="${FAKE_SUDO_LOG:?FAKE_SUDO_LOG is required}"
printf '%s\n' "$*" >> "$log_file"

if [[ "${1:-}" == "-n" ]]; then
  if [[ "$mode" == "probe_fail" ]]; then
    exit 1
  fi

  shift
  exec "$@"
fi

if [[ "${1:-}" == "-p" ]]; then
  shift 2
  exec "$@"
fi

exec "$@"
SH

cat > "$tmpdir/bin/mkcert" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-install" ]]; then
  echo "fake mkcert CA installed"
  exit 0
fi

cert_file=""
key_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -cert-file)
      cert_file="$2"
      shift 2
      ;;
    -key-file)
      key_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$cert_file" ]] || { echo "missing -cert-file" >&2; exit 1; }
[[ -n "$key_file" ]] || { echo "missing -key-file" >&2; exit 1; }

printf 'fake certificate\n' > "$cert_file"
printf 'fake private key\n' > "$key_file"
SH

chmod +x "$tmpdir/bin/sudo" "$tmpdir/bin/mkcert"

run_case() {
  local mode="$1"
  local host="$2"
  local hosts_file="$tmpdir/${mode}.hosts"
  local cert_dir="$tmpdir/${mode}-cert"
  local sudo_log="$tmpdir/${mode}.sudo.log"

  mkdir -p "$cert_dir"
  touch "$hosts_file"

  PATH="$tmpdir/bin:$PATH" FAKE_SUDO_MODE="$mode" FAKE_SUDO_LOG="$sudo_log" MIX_ENV=test mix star_view.trust \
    --yes \
    --host "$host" \
    --hosts-file "$hosts_file" \
    --cert "$cert_dir/selfsigned.pem" \
    --key "$cert_dir/selfsigned_key.pem"

  grep -Fx "127.0.0.1 $host" "$hosts_file"
  test -s "$cert_dir/selfsigned.pem"
  test -s "$cert_dir/selfsigned_key.pem"

  grep -F -- "-n /bin/sh -c" "$sudo_log"

  if [[ "$mode" == "probe_success" ]]; then
    ! grep -F -- "-p Password:" "$sudo_log"
  else
    grep -F -- "-p Password:" "$sudo_log"
  fi
}

run_case probe_success docker-smoke-cached.test

if [[ "$(uname -s)" == "Linux" ]]; then
  run_case probe_fail docker-smoke-fallback.test
else
  echo "Skipping Linux fallback-sudo case on non-Linux debug run."
fi

echo "Linux StarView trust smoke test passed."
