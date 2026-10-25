#!/usr/bin/env bash
# Static checks for the harness smoke test. Does not start Docker.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
cd "$root"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

fixture=openshell/pi/smoke/extension.ts
[[ -f "$fixture" ]] || fail "missing fixture"
files=$(find openshell/pi/smoke -type f | wc -l | tr -d ' ')
[[ "$files" == 1 ]] || fail "pi/smoke should contain one file"

grep -F -q 'import { VERSION, type ExtensionAPI } from "@earendil-works/pi-coding-agent"' "$fixture" || fail "pi value import"
grep -F -q 'from "typebox"' "$fixture" || fail "typebox import"
grep -F -q 'typeof VERSION' "$fixture" || fail "VERSION is unused"
grep -F -q 'registerFlag("openshell-smoke"' "$fixture" || fail "flag"
grep -F -q 'OPENSHELL_PI_EXTENSION_OK' "$fixture" || fail "marker"
if grep -n 'pi/smoke' openshell/pi/Dockerfile; then
  fail "Dockerfile copies the fixture"
fi
grep -F -q 'pi/smoke' openshell/.dockerignore || fail "dockerignore"

workflow=.github/workflows/openshell-build-image.yml
line_of() {
  grep -n -F "$1" "$workflow" | head -n 1 | cut -d: -f1
}
smoke_line=$(line_of 'name: Smoke test')
push_line=$(line_of 'name: Push smoked image by digest')
attest_line=$(line_of 'name: Attest arch image')
[[ -n "$smoke_line" && -n "$push_line" && -n "$attest_line" ]] || fail "workflow steps"
[[ "$smoke_line" -lt "$push_line" && "$push_line" -lt "$attest_line" ]] || fail "smoke must run before push"

grep -F -q 'smoke-image.sh "$RECIPE" "$LOCAL_TAG"' "$workflow" || fail "workflow smoke command"
grep -F -q 'bash openshell/scripts/ci-push.sh' "$workflow" || fail "workflow push command"
grep -F -q 'steps.push.outputs.digest || steps.build.outputs.digest' "$workflow" || fail "digest selection"

if grep -n 'push=true' openshell/scripts/ci-build.sh | grep -v 'type=image'; then
  fail "ci-build push flag drifted"
fi
push_hits=$(grep -c 'push=true' openshell/scripts/ci-build.sh)
[[ "$push_hits" == 1 ]] || fail "ci-build should push only the non-harness path"
grep -F -q 'smoke=true' openshell/scripts/ci-build.sh || fail "load path"
grep -F -q 'openshell-ci-${RECIPE}:smoke' openshell/scripts/ci-push.sh || fail "push tag"
grep -F -q -- '--network none' openshell/scripts/smoke-image.sh || fail "network"
grep -F -q -- '--offline' openshell/scripts/smoke-image.sh || fail "offline"
grep -F -q -- '--openshell-smoke' openshell/scripts/smoke-image.sh || fail "flag marker"
grep -F -q 'OPENSHELL_PI_EXTENSION_OK' openshell/scripts/smoke-image.sh || fail "text marker"
grep -F -q 'just openshell::smoke-pi' openshell/README.md || fail "docs"
grep -F -q 'just openshell::smoke-codex-pi' openshell/README.md || fail "codex-pi docs"
grep -F -q 'smoke-pi:' openshell/justfile || fail "smoke-pi recipe"
grep -F -q 'smoke-codex-pi:' openshell/justfile || fail "smoke-codex-pi recipe"
grep -F -q 'all: stacks pi codex codex-pi claude smoke' openshell/justfile || fail "all runs smoke"
grep -F -q 'pi/install-pi.sh' openshell/codex-pi/Dockerfile || fail "codex-pi should reuse install-pi.sh"
grep -F -q 'codex/install-codex.sh' openshell/codex-pi/Dockerfile || fail "codex-pi should reuse install-codex.sh"
if grep -R -n 'github.com/earendil-works/pi' openshell/codex-pi; then
  fail "pi download URL duplicated"
fi
if grep -R -n 'github.com/openai/codex' openshell/codex-pi; then
  fail "codex download URL duplicated"
fi

printf 'smoke tests passed\n'
