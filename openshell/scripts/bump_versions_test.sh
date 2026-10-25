#!/usr/bin/env bash
# Offline checks for the version bump helpers and the pin layout.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
# shellcheck disable=SC1091
. "$root/openshell/scripts/bump-versions.sh"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local name=$1 got=$2 want=$3
  [[ "$got" == "$want" ]] || fail "${name}: got [${got}] want [${want}]"
}

status=0
got=$(newest_matching minor 1.2.3 1.2.0 1.2.4 1.3.0 1.2.4-rc.1) || status=$?
[[ "$status" -eq 0 ]] || fail "newest minor status ${status}"
assert_eq "newest minor" "$got" "1.2.4"

status=0
got=$(newest_matching zero 0.13.5 0.13.4 0.14.0 1.0.0) || status=$?
[[ "$status" -eq 0 ]] || fail "newest zero status ${status}"
assert_eq "newest zero" "$got" "0.14.0"

status=0
newest_matching minor 1.2.3 1.2.0 1.2.2 || status=$?
[[ "$status" -eq 2 ]] || fail "downgrade status ${status}"

status=0
newest_matching minor 1.2.3 1.3.0 1.3.1 || status=$?
[[ "$status" -eq 1 ]] || fail "no match status ${status}"

status=0
got=$(pick_action_tag 4 refs/tags/v4.4.1 refs/tags/v4.5.0 refs/tags/v5.0.0 refs/tags/v4.5.0-rc.1) || status=$?
[[ "$status" -eq 0 ]] || fail "action tag status ${status}"
assert_eq "action tag" "$got" "v4.5.0"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' \
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  one.tar.gz" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb *two.tar.gz" \
  >"$tmp/sums"
assert_eq "named checksum" "$(checksum_for_name "$tmp/sums" one.tar.gz)" \
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
assert_eq "star checksum" "$(checksum_for_name "$tmp/sums" two.tar.gz)" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf '%s\n' "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  only.tar.gz" >"$tmp/one"
assert_eq "single sidecar" "$(checksum_for_name "$tmp/one" "")" \
  "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
if checksum_for_name "$tmp/sums" missing.tar.gz; then
  fail "missing checksum should fail"
fi

printf '%s\n' 'FD_VERSION=1.0.0' 'FD_SHA256_AMD64=abc' >"$tmp/env"
set_kv "$tmp/env" FD_VERSION 1.0.1
assert_eq "set version" "$(kv "$tmp/env" FD_VERSION)" "1.0.1"
assert_eq "untouched checksum" "$(kv "$tmp/env" FD_SHA256_AMD64)" "abc"
set_kv "$tmp/env" FD_VERSION 1.0.1
assert_eq "set same value" "$(kv "$tmp/env" FD_VERSION)" "1.0.1"

cat >"$tmp/channel.toml" <<'EOF'
[pkg.rustc]
version = "1.99.1 (58cf8f9c3 2026-10-13)"

[pkg.rustc.target.x86_64-unknown-linux-gnu]
xz_hash = "2ff05ff9c08a90861e7f6e4065b40a8b87463b4576186fd613871c3e37f2091f"
EOF
assert_eq "toml semver" "$(toml_value "$tmp/channel.toml" pkg.rustc version semver)" "1.99.1"
assert_eq "toml sha" \
  "$(toml_value "$tmp/channel.toml" pkg.rustc.target.x86_64-unknown-linux-gnu xz_hash sha256)" \
  "2ff05ff9c08a90861e7f6e4065b40a8b87463b4576186fd613871c3e37f2091f"

cd "$root"
[[ ! -f renovate.json ]] || fail "renovate.json should be gone"
[[ ! -f openshell/common/versions.env ]] || fail "common/versions.env should be gone"
[[ ! -f openshell/versions/node.env ]] || fail "node.env should be gone"
[[ -f .github/workflows/openshell-bump.yml ]] || fail "missing bump workflow"

if grep -R -n -E 'RUST_DIST_DATE|ARG (PI|CODEX|CLAUDE)_VERSION=' \
  openshell .github/workflows \
  --include='Dockerfile' --include='*.sh' --include='*.yml' --include='*.env' \
  --exclude=bump_versions_test.sh; then
  fail "hard-coded version arg or rust dist date remains"
fi

if grep -R -n -E 'NODE_VERSION|nodejs\.org|versions/node\.env' \
  openshell .github justfile \
  --include='Dockerfile' --include='*.sh' --include='*.yml' --include='*.env' --include='justfile' \
  --exclude=bump_versions_test.sh; then
  fail "node install pin remains"
fi

if grep -R -n -E '[a-f0-9]{64}' openshell \
  --include='Dockerfile' --include='install-*.sh' --exclude-dir=versions; then
  fail "sha256 pin lives outside versions/"
fi

dupes=$(grep -h -E '^[A-Z0-9_]+=' openshell/versions/*.env | cut -d= -f1 | sort | uniq -d || true)
[[ -z "$dupes" ]] || fail "duplicate version keys: ${dupes}"

debian=$(grep -E '^DEBIAN_IMAGE=' openshell/versions/base.env | cut -d= -f2-)
[[ "$debian" =~ ^debian:bookworm-slim@sha256:[a-f0-9]{64}$ ]] || fail "bad DEBIAN_IMAGE"

grep -q 'cron: "0 16 \* \* 1"' .github/workflows/openshell-bump.yml || fail "bump cron"
grep -q 'contents: write' .github/workflows/openshell-bump.yml || fail "contents write"
grep -q 'actions: write' .github/workflows/openshell-bump.yml || fail "actions write"
grep -q 'group: openshell-version-bump' .github/workflows/openshell-bump.yml || fail "concurrency group"
grep -q 'publish=release' .github/workflows/openshell-bump.yml || fail "release dispatch"

printf 'bump version tests passed\n'
