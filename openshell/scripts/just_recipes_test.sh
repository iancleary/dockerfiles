#!/usr/bin/env bash
# Child image recipes build agent-cli when OPENSHELL_BASE_IMAGE is unset.
# Inside the openshell module, justfile() is the root justfile, which has
# no agent-cli recipe. Dry-run only: Docker is not started.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
cd "$root"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

command -v just >/dev/null 2>&1 || fail "just is not on PATH"
unset OPENSHELL_BASE_IMAGE

module_just=$root/openshell/justfile
[[ -f "$module_just" ]] || fail "missing module justfile"

expect_fallback() {
  local recipe=$1 out
  out=$(just --dry-run "openshell::${recipe}" 2>&1) || fail "dry-run openshell::${recipe}"
  if ! grep -F -q "just --justfile '${module_just}' agent-cli" <<<"$out"; then
    printf '%s\n' "$out" >&2
    fail "${recipe} does not build agent-cli from the module justfile"
  fi
  if grep -F -q "just --justfile '${root}/justfile' agent-cli" <<<"$out"; then
    fail "${recipe} calls agent-cli on the root justfile"
  fi
}

for recipe in python rust go pi codex codex-pi claude; do
  expect_fallback "$recipe"
done

just --justfile "$module_just" --dry-run agent-cli >/dev/null 2>&1 \
  || fail "module justfile has no agent-cli recipe"
just --dry-run openshell::all >/dev/null 2>&1 || fail "dry-run openshell::all"

list=$(just --dry-run openshell 2>&1)
if ! grep -F -q "just --justfile '${module_just}' --list" <<<"$list"; then
  printf '%s\n' "$list" >&2
  fail "openshell default does not list the module justfile"
fi

printf 'just recipe tests passed\n'
