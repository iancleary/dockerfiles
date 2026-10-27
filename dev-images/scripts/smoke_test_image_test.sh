#!/usr/bin/env bash
# Version-token parsing and the smoke-test contract. Does not start a container.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
smoke=$root/dev-images/scripts/smoke_test_image.sh

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_token() {
  local name=$1 text=$2 expected=$3
  local actual
  actual=$(bash "$smoke" --print-version-token "$text") || fail "$name"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL %s: got [%s] want [%s]\n' "$name" "$actual" "$expected" >&2
    exit 1
  fi
}

assert_token "jq" "jq-1.8.2" "1.8.2"
assert_token "ripgrep" "ripgrep 15.2.0 (rev abc)" "15.2.0"
assert_token "shellcheck second line" $'ShellCheck - shell script analysis tool\nversion: 0.11.0\nlicense: GNU' "0.11.0"
assert_token "eza second line" $'eza - A modern, maintained replacement for ls\nv0.23.5 [+git]' "0.23.5"
assert_token "gum leading v" "gum version v2.0.2 (879f048)" "2.0.2"
assert_token "short version" "tool 2.1.31" "2.1.31"
assert_token "longer release is its own token" "tool 2.1.310" "2.1.310"
if [[ "$(bash "$smoke" --print-version-token 'tool 2.1.310')" == "2.1.31" ]]; then
  fail "2.1.310 was parsed as 2.1.31"
fi

grep -F -q -- '--network none' "$smoke" || fail "network is not disabled"
if grep -n -- '--user' "$smoke" | grep -v -E '^[0-9]+:[[:space:]]*#'; then
  fail "smoke test overrides the container user"
fi
grep -F -q 'id -u' "$smoke" || fail "uid check"
grep -F -q 'developer' "$smoke" || fail "developer account"
grep -F -q 'command -v sudo' "$smoke" || fail "sudo check"
grep -F -q 'setuid' "$smoke" || fail "setuid check"
grep -F -q 'expect_ahi_version' "$smoke" || fail "ahi check"
# shellcheck disable=SC2016
grep -F -q 'ahi ${want}' "$smoke" || fail "ahi version text"
grep -F -q 'AHI_VERSION' "$smoke" || fail "ahi recorded version"
for recorded in GO_VERSION RUST_VERSION NODE_VERSION PNPM_VERSION PYTHON_VERSION ZIG_VERSION BUN_VERSION; do
  grep -F -q "$recorded" "$smoke" || fail "smoke omits $recorded"
done
grep -F -q 'assert_command_absent node' "$smoke" || fail "bun image may contain node"

workflow=$root/.github/workflows/dev-images-build-single-image.yml
smoke_line=$(grep -n 'smoke_test_image.sh' "$workflow" | head -n 1 | cut -d: -f1)
push_line=$(grep -n 'push_image_by_digest.sh' "$workflow" | head -n 1 | cut -d: -f1)
if [[ -z "$smoke_line" || -z "$push_line" || "$smoke_line" -ge "$push_line" ]]; then
  fail "smoke test does not run before the registry write"
fi

printf 'smoke test contract passed\n'
