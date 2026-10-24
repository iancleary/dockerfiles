#!/usr/bin/env bash
# Hermetic checks for the 3-day release gate and path filters.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
plan=$root/openshell/scripts/plan.sh
sha=0123456789abcdef0123456789abcdef01234567
short=0123456
fail=0

expect() {
  local name=$1
  local expected=$2
  shift 2
  local out status
  set +e
  out=$(bash "$plan" "$@" 2>/dev/null)
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf 'FAIL %s (plan exited %s)\n' "$name" "$status"
    bash "$plan" "$@" >&2 || true
    fail=1
    return
  fi
  if [[ "$out" != "$expected" ]]; then
    printf 'FAIL %s\n' "$name"
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$out") || true
    fail=1
  else
    printf 'ok %s\n' "$name"
  fi
}

flags() {
  cat <<EOF
build_agent_cli=$1
build_python=$2
build_rust=$3
build_go=$4
build_pi=$5
build_codex=$6
build_claude=$7
EOF
}

all_true=$(flags true true true true true true true)
all_false=$(flags false false false false false false false)

record() {
  local publish=$1 version=$2 git_tag=$3 no_cache=$4 layers=$5
  cat <<EOF
publish=${publish}
image_version=${version}
git_tag=${git_tag}
short_sha=${short}
git_sha=${sha}
no_cache=${no_cache}
${layers}
EOF
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' 'openshell-2026.10.22.01' 'openshell-2026.10.24.01' >"$tmp/tags"
: >"$tmp/empty-tags"
printf '%s\n' 'openshell-2026.10.24.01' 'openshell-2026.10.24.02' >"$tmp/sameday"
printf '%s\n' 'openshell/python/Dockerfile' 'openshell/README.md' >"$tmp/files-python"
printf '%s\n' 'openshell/common/versions.env' >"$tmp/files-common"
printf '%s\n' 'openshell/agent-cli/Dockerfile' >"$tmp/files-base"
printf '%s\n' 'openshell/pi/Dockerfile' 'openshell/codex/install-codex.sh' >"$tmp/files-harness"
printf '%s\n' 'openshell/README.md' 'README.md' 'openshell/scripts/plan.sh' >"$tmp/files-docs"

OPENSHELL_NOW=2026-10-26 OPENSHELL_TAGS_FILE="$tmp/tags" \
  expect 'schedule not due after 2 days' \
  "$(record skip '' '' false "$all_false")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" \
  expect 'schedule due on day 3' \
  "$(record release 2026.10.27.01 openshell-2026.10.27.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-11-02 OPENSHELL_TAGS_FILE="$tmp/tags" \
  expect 'schedule due across a month boundary' \
  "$(record release 2026.11.02.01 openshell-2026.11.02.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/empty-tags" \
  expect 'first schedule with no tag is due' \
  "$(record release 2026.10.24.01 openshell-2026.10.24.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/sameday" \
  expect 'manual release bumps the same-day sequence' \
  "$(record release 2026.10.24.03 openshell-2026.10.24.03 true "$all_true")" \
  --event workflow_dispatch --publish release --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/sameday" \
  expect 'manual edge builds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event workflow_dispatch --publish edge --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/empty-tags" \
  expect 'python-only push' \
  "$(record edge edge '' false "$(flags false true false false false false false)")" \
  --event push --sha "$sha" --files "$tmp/files-python"

expect 'common change rebuilds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --files "$tmp/files-common"

expect 'agent-cli change rebuilds descendants' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --files "$tmp/files-base"

expect 'harness paths do not rebuild unrelated layers' \
  "$(record edge edge '' false "$(flags false false false false true true false)")" \
  --event push --sha "$sha" --files "$tmp/files-harness"

expect 'docs and plan script do not rebuild images' \
  "$(record skip '' '' false "$all_false")" \
  --event push --sha "$sha" --files "$tmp/files-docs"

expect 'unknown before-sha builds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --all-files

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
printf 'plan tests passed\n'
