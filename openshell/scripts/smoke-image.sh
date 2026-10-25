#!/usr/bin/env bash
# Run the harness smoke test against one local image. Does not push.
# The container user is the image USER. Do not pass --user.
# The Pi fixture is mounted for this container only.
set -euo pipefail

# First semver token on the first line. 2.1.31 does not match 2.1.310.
version_token() {
  local line=$1
  line=${line%%$'\n'*}
  if [[ "$line" =~ ([0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

if [[ "${1:-}" == "--parse-version" ]]; then
  [[ $# -eq 2 ]] || exit 2
  version_token "$2"
  exit
fi

if [[ $# -ne 2 ]]; then
  printf 'usage: smoke-image.sh agent-cli|python|rust|go|pi|codex|codex-pi|claude IMAGE\n' >&2
  exit 2
fi

recipe=$1
image=$2
root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'image %s is not loaded\n' "$image" >&2
  exit 1
fi

pinned() {
  local key=$1 file=$2 line
  line=$(grep -E "^${key}=" "$file" | head -n 1) || true
  [[ -n "$line" ]] || {
    printf 'missing %s in %s\n' "$key" "$file" >&2
    exit 1
  }
  printf '%s' "${line#*=}"
}

run_cli() {
  local entrypoint=$1
  shift
  timeout 120 docker run --rm --network none \
    --entrypoint "$entrypoint" \
    "$image" \
    "$@"
}

# The image USER must be agent. A --user override would hide a root default.
assert_unprivileged() {
  local uid name
  uid=$(run_cli id -u)
  name=$(run_cli id -un)
  uid=${uid//[[:space:]]/}
  name=${name//[[:space:]]/}
  if [[ "$uid" != "1000" || "$name" != "agent" ]]; then
    printf '%s ran as %s (uid %s), want 1000 and name agent\n' "$recipe" "$name" "$uid" >&2
    exit 1
  fi
  if ! run_cli sh -c 'test -w /tmp && test ! -w /usr/local/bin && ! command -v sudo >/dev/null'; then
    printf '%s failed the runtime permission checks\n' "$recipe" >&2
    exit 1
  fi
  # shellcheck disable=SC2016
  if ! run_cli sh -c 'bad=$(find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o \( -type d -o -type f \) -perm -0002 ! -path /tmp ! -path "/tmp/*" -print); test -z "$bad"'; then
    printf '%s has a world-writable path other than /tmp\n' "$recipe" >&2
    exit 1
  fi
  # shellcheck disable=SC2016
  if ! run_cli sh -c 'bad=$(find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o -type f \( -perm -4000 -o -perm -2000 \) -print); test -z "$bad"'; then
    printf '%s has a setuid or setgid file\n' "$recipe" >&2
    exit 1
  fi
}

expect_version() {
  local key=$1 file=$2 got=$3 want parsed
  want=$(pinned "$key" "$file")
  if ! parsed=$(version_token "$got"); then
    printf '%s version output has no version token: [%s]\n' "$recipe" "$got" >&2
    exit 1
  fi
  if [[ "$parsed" != "$want" ]]; then
    printf '%s version output [%s] parsed as [%s], want %s\n' "$recipe" "$got" "$parsed" "$want" >&2
    exit 1
  fi
}

smoke_pi_extension() {
  local fixture=$root/openshell/pi/smoke/extension.ts help
  [[ -f "$fixture" ]] || {
    printf 'missing Pi extension fixture\n' >&2
    exit 1
  }
  help=$(
    timeout 120 docker run --rm --network none \
      --entrypoint pi \
      -e PI_OFFLINE=1 \
      -e PI_CODING_AGENT_DIR=/tmp/pi-agent \
      -v "$fixture:/smoke/extension.ts:ro" \
      "$image" \
      --offline --no-extensions -e /smoke/extension.ts --help
  )
  if ! grep -F -q -- '--openshell-smoke' <<<"$help" \
    || ! grep -F -q -- 'OPENSHELL_PI_EXTENSION_OK' <<<"$help"; then
    printf 'Pi did not load the extension\n%s\n' "$help" >&2
    exit 1
  fi
}

case "$recipe" in
  agent-cli)
    assert_unprivileged
    run_cli fd --version >/dev/null
    run_cli rg --version >/dev/null
    run_cli just --version >/dev/null
    ;;
  python)
    assert_unprivileged
    expect_version PYTHON_VERSION "$root/openshell/versions/python.env" "$(run_cli python3 --version)"
    expect_version UV_VERSION "$root/openshell/versions/python.env" "$(run_cli uv --version)"
    ;;
  rust)
    assert_unprivileged
    expect_version RUST_VERSION "$root/openshell/versions/rust.env" "$(run_cli rustc --version)"
    run_cli cargo --version >/dev/null
    ;;
  go)
    assert_unprivileged
    expect_version GO_VERSION "$root/openshell/versions/go.env" "$(run_cli go version)"
    ;;
  pi)
    assert_unprivileged
    version=$(run_cli pi --offline --version)
    expect_version PI_VERSION "$root/openshell/versions/pi.env" "$version"
    smoke_pi_extension
    ;;
  codex-pi)
    assert_unprivileged
    version=$(run_cli pi --offline --version)
    expect_version PI_VERSION "$root/openshell/versions/pi.env" "$version"
    version=$(run_cli codex --version)
    expect_version CODEX_VERSION "$root/openshell/versions/codex.env" "$version"
    run_cli pi --offline --list-models >/dev/null
    run_cli fd --version >/dev/null
    run_cli rg --version >/dev/null
    smoke_pi_extension
    ;;
  codex)
    assert_unprivileged
    version=$(run_cli codex --version)
    expect_version CODEX_VERSION "$root/openshell/versions/codex.env" "$version"
    ;;
  claude)
    assert_unprivileged
    version=$(run_cli claude --version)
    expect_version CLAUDE_VERSION "$root/openshell/versions/claude.env" "$version"
    ;;
  *)
    printf 'no smoke test for %s\n' "$recipe" >&2
    exit 2
    ;;
esac

printf 'smoke %s ok\n' "$recipe"
