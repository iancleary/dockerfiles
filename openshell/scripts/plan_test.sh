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
printf '%s\n' 'openshell-2026.09.24.01' >"$tmp/tags-30"
printf '%s\n' 'openshell-2026.09.25.01' >"$tmp/tags-29"
printf '%s\n' 'openshell/python/Dockerfile' 'openshell/README.md' >"$tmp/files-python"
printf '%s\n' 'openshell/versions/tools.env' >"$tmp/files-common"
printf '%s\n' 'openshell/agent-cli/Dockerfile' >"$tmp/files-base"
printf '%s\n' 'openshell/pi/Dockerfile' 'openshell/codex/install-codex.sh' >"$tmp/files-harness"
printf '%s\n' 'openshell/README.md' 'README.md' 'openshell/scripts/plan.sh' >"$tmp/files-docs"
printf '%s\n' 'openshell/versions/claude.env' >"$tmp/changes-claude"
: >"$tmp/changes-empty"
printf '%s\n' 'README.md' >"$tmp/changes-root"
printf '%s\n' '.github/workflows/openshell-build-image.yml' >"$tmp/changes-workflow"
printf '%s\n' 'justfile' >"$tmp/changes-just"
printf '%s\n' 'openshell/README.md' >"$tmp/changes-docs"
printf '%s\n' 'openshell/versions/base.env' >"$tmp/files-debian"
printf '%s\n' 'openshell/versions/python.env' >"$tmp/files-pyver"
printf '%s\n' 'openshell/versions/rust.env' >"$tmp/files-rustver"
printf '%s\n' 'openshell/versions/go.env' >"$tmp/files-gover"
printf '%s\n' 'openshell/versions/pi.env' >"$tmp/files-piver"
printf '%s\n' 'openshell/versions/codex.env' >"$tmp/files-codexver"
printf '%s\n' 'openshell/versions/claude.env' >"$tmp/files-claudever"
printf '%s\n' 'openshell/versions/future.env' >"$tmp/files-future"
printf '%s\n' 'openshell/common/install-agent-cli.sh' >"$tmp/files-install"

OPENSHELL_NOW=2026-10-26 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-claude" \
  expect 'schedule not due after 2 days even when inputs changed' \
  "$(record skip '' '' false "$all_false")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-empty" \
  expect 'schedule skips a 3-day-old tag when nothing changed' \
  "$(record skip '' '' false "$all_false")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-root" \
  expect 'schedule ignores changes outside the image inputs' \
  "$(record skip '' '' false "$all_false")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-claude" \
  expect 'schedule due on day 3 when inputs changed' \
  "$(record release 2026.10.27.01 openshell-2026.10.27.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-workflow" \
  expect 'schedule treats an image workflow change as an input' \
  "$(record release 2026.10.27.01 openshell-2026.10.27.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-just" \
  expect 'schedule treats the root justfile as an input' \
  "$(record release 2026.10.27.01 openshell-2026.10.27.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-27 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-docs" \
  expect 'schedule treats files under openshell as inputs' \
  "$(record release 2026.10.27.01 openshell-2026.10.27.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-11-02 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-claude" \
  expect 'schedule due across a month boundary when inputs changed' \
  "$(record release 2026.11.02.01 openshell-2026.11.02.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/tags-30" OPENSHELL_CHANGES_FILE="$tmp/changes-empty" \
  expect 'schedule forces a release when the tag is 30 days old' \
  "$(record release 2026.10.24.01 openshell-2026.10.24.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/tags-29" OPENSHELL_CHANGES_FILE="$tmp/changes-empty" \
  expect 'schedule does not force a 29-day-old tag' \
  "$(record skip '' '' false "$all_false")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-26 OPENSHELL_MIN_AGE_DAYS=2 OPENSHELL_TAGS_FILE="$tmp/tags" OPENSHELL_CHANGES_FILE="$tmp/changes-claude" \
  expect 'schedule minimum age is configurable' \
  "$(record release 2026.10.26.01 openshell-2026.10.26.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/empty-tags" \
  expect 'first schedule with no tag is due' \
  "$(record release 2026.10.24.01 openshell-2026.10.24.01 true "$all_true")" \
  --event schedule --sha "$sha"

OPENSHELL_NOW=2026-10-24 OPENSHELL_TAGS_FILE="$tmp/sameday" OPENSHELL_CHANGES_FILE="$tmp/changes-empty" \
  expect 'manual release ignores the age and change gates' \
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

expect 'tool version file rebuilds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --files "$tmp/files-common"

expect 'base image pin rebuilds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --files "$tmp/files-debian"

expect 'install script rebuilds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --files "$tmp/files-install"

expect 'python version file rebuilds python only' \
  "$(record edge edge '' false "$(flags false true false false false false false)")" \
  --event push --sha "$sha" --files "$tmp/files-pyver"

expect 'rust version file rebuilds rust only' \
  "$(record edge edge '' false "$(flags false false true false false false false)")" \
  --event push --sha "$sha" --files "$tmp/files-rustver"

expect 'go version file rebuilds go only' \
  "$(record edge edge '' false "$(flags false false false true false false false)")" \
  --event push --sha "$sha" --files "$tmp/files-gover"

expect 'pi version file rebuilds pi only' \
  "$(record edge edge '' false "$(flags false false false false true false false)")" \
  --event push --sha "$sha" --files "$tmp/files-piver"

expect 'codex version file rebuilds codex only' \
  "$(record edge edge '' false "$(flags false false false false false true false)")" \
  --event push --sha "$sha" --files "$tmp/files-codexver"

expect 'claude version file rebuilds claude only' \
  "$(record edge edge '' false "$(flags false false false false false false true)")" \
  --event push --sha "$sha" --files "$tmp/files-claudever"

expect 'unknown version file rebuilds every layer' \
  "$(record edge edge '' false "$all_true")" \
  --event push --sha "$sha" --files "$tmp/files-future"

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
