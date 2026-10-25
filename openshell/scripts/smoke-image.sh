#!/usr/bin/env bash
# Run the harness smoke test against one local image. Does not push.
# The Pi fixture is mounted for this container only.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'usage: smoke-image.sh pi|codex|codex-pi|claude IMAGE\n' >&2
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

expect_version() {
  local key=$1 file=$2 got=$3 want
  want=$(pinned "$key" "$file")
  if ! grep -F -q -- "$want" <<<"$got"; then
    printf '%s --version printed [%s], want it to contain %s\n' "$recipe" "$got" "$want" >&2
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

expect_agent_user() {
  local uid name
  uid=$(run_cli id -u)
  name=$(run_cli id -un)
  uid=${uid//[[:space:]]/}
  name=${name//[[:space:]]/}
  if [[ "$uid" != "1000" || "$name" != "agent" ]]; then
    printf 'expected user agent (uid 1000), got %s (%s)\n' "$name" "$uid" >&2
    exit 1
  fi
}

case "$recipe" in
  pi)
    version=$(run_cli pi --offline --version)
    expect_version PI_VERSION "$root/openshell/versions/pi.env" "$version"
    smoke_pi_extension
    ;;
  codex-pi)
    version=$(run_cli pi --offline --version)
    expect_version PI_VERSION "$root/openshell/versions/pi.env" "$version"
    version=$(run_cli codex --version)
    expect_version CODEX_VERSION "$root/openshell/versions/codex.env" "$version"
    run_cli pi --offline --list-models >/dev/null
    run_cli fd --version >/dev/null
    run_cli rg --version >/dev/null
    expect_agent_user
    smoke_pi_extension
    ;;
  codex)
    version=$(run_cli codex --version)
    expect_version CODEX_VERSION "$root/openshell/versions/codex.env" "$version"
    ;;
  claude)
    version=$(run_cli claude --version)
    expect_version CLAUDE_VERSION "$root/openshell/versions/claude.env" "$version"
    ;;
  *)
    printf 'no smoke test for %s\n' "$recipe" >&2
    exit 2
    ;;
esac

printf 'smoke %s ok\n' "$recipe"
