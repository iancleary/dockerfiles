#!/usr/bin/env bash
# Hermetic checks for the release gate and path filters.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
plan=$root/dev-images/scripts/plan_release.sh
sha=0123456789abcdef0123456789abcdef01234567
short=0123456
fail=0

expect() {
  local name=$1
  local expected=$2
  shift 2
  local output status
  set +e
  output=$(bash "$plan" "$@" 2>/dev/null)
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf 'FAIL %s (plan exited %s)\n' "$name" "$status"
    bash "$plan" "$@" >&2 || true
    fail=1
    return
  fi
  if [[ "$output" != "$expected" ]]; then
    printf 'FAIL %s\n' "$name"
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$output") || true
    fail=1
  else
    printf 'ok %s\n' "$name"
  fi
}

record() {
  local publish=$1 version=$2 git_tag=$3 no_cache=$4 build_base=$5
  cat <<EOF
publish=${publish}
image_version=${version}
git_tag=${git_tag}
short_sha=${short}
git_sha=${sha}
no_cache=${no_cache}
build_base=${build_base}
EOF
}

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

printf '%s\n' 'dev-images-2026.10.22.01' 'dev-images-2026.10.24.01' >"$temporary/tags"
: >"$temporary/empty-tags"
printf '%s\n' 'dev-images-2026.10.24.01' 'dev-images-2026.10.24.02' >"$temporary/same-day"
printf '%s\n' 'dev-images-2026.09.24.01' >"$temporary/tags-30"
printf '%s\n' 'dev-images-2026.09.25.01' >"$temporary/tags-29"
printf '%s\n' 'dev-images/versions/jq.env' >"$temporary/files-tool"
printf '%s\n' 'dev-images/README.md' >"$temporary/files-readme"
printf '%s\n' 'README.md' >"$temporary/files-root"
printf '%s\n' 'openshell/versions/base.env' >"$temporary/files-openshell"
printf '%s\n' 'dev-images/base/Dockerfile' 'README.md' >"$temporary/changes-base"
: >"$temporary/changes-empty"
printf '%s\n' 'README.md' >"$temporary/changes-root"
printf '%s\n' '.github/workflows/dev-images-build-single-image.yml' >"$temporary/changes-workflow"
printf '%s\n' 'justfile' >"$temporary/changes-just"
printf '%s\n' 'openshell/README.md' >"$temporary/changes-openshell"

DEV_IMAGES_NOW=2026-10-26 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-base" \
  expect 'schedule not due after 2 days even when inputs changed' \
  "$(record skip '' '' false false)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-27 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-empty" \
  expect 'schedule skips a 3-day-old tag when nothing changed' \
  "$(record skip '' '' false false)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-27 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-root" \
  expect 'schedule ignores changes outside the image inputs' \
  "$(record skip '' '' false false)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-27 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-openshell" \
  expect 'schedule ignores OpenShell changes' \
  "$(record skip '' '' false false)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-27 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-base" \
  expect 'schedule due on day 3 when inputs changed' \
  "$(record release 2026.10.27.01 dev-images-2026.10.27.01 true true)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-27 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-workflow" \
  expect 'schedule treats an image workflow change as an input' \
  "$(record release 2026.10.27.01 dev-images-2026.10.27.01 true true)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-27 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-just" \
  expect 'schedule treats the root justfile as an input' \
  "$(record release 2026.10.27.01 dev-images-2026.10.27.01 true true)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-24 DEV_IMAGES_TAGS_FILE="$temporary/tags-30" DEV_IMAGES_CHANGES_FILE="$temporary/changes-empty" \
  expect 'schedule forces a release when the tag is 30 days old' \
  "$(record release 2026.10.24.01 dev-images-2026.10.24.01 true true)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-24 DEV_IMAGES_TAGS_FILE="$temporary/tags-29" DEV_IMAGES_CHANGES_FILE="$temporary/changes-empty" \
  expect 'schedule does not force a 29-day-old tag' \
  "$(record skip '' '' false false)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-26 DEV_IMAGES_MINIMUM_AGE_DAYS=2 DEV_IMAGES_TAGS_FILE="$temporary/tags" DEV_IMAGES_CHANGES_FILE="$temporary/changes-base" \
  expect 'schedule minimum age is configurable' \
  "$(record release 2026.10.26.01 dev-images-2026.10.26.01 true true)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-24 DEV_IMAGES_TAGS_FILE="$temporary/empty-tags" \
  expect 'first schedule with no tag is due' \
  "$(record release 2026.10.24.01 dev-images-2026.10.24.01 true true)" \
  --event schedule --sha "$sha"

DEV_IMAGES_NOW=2026-10-24 DEV_IMAGES_TAGS_FILE="$temporary/same-day" DEV_IMAGES_CHANGES_FILE="$temporary/changes-empty" \
  expect 'manual release ignores the age and change gates' \
  "$(record release 2026.10.24.03 dev-images-2026.10.24.03 true true)" \
  --event workflow_dispatch --publish release --sha "$sha"

DEV_IMAGES_NOW=2026-10-24 DEV_IMAGES_TAGS_FILE="$temporary/same-day" \
  expect 'manual edge builds dev-base' \
  "$(record edge edge '' false true)" \
  --event workflow_dispatch --publish edge --sha "$sha"

expect 'tool version file publishes edge' \
  "$(record edge edge '' false true)" \
  --event push --sha "$sha" --files "$temporary/files-tool"

expect 'family readme publishes edge' \
  "$(record edge edge '' false true)" \
  --event push --sha "$sha" --files "$temporary/files-readme"

expect 'root readme does not publish' \
  "$(record skip '' '' false false)" \
  --event push --sha "$sha" --files "$temporary/files-root"

expect 'OpenShell file does not publish dev-base' \
  "$(record skip '' '' false false)" \
  --event push --sha "$sha" --files "$temporary/files-openshell"

expect 'all files publishes edge' \
  "$(record edge edge '' false true)" \
  --event push --sha "$sha" --all-files

set +e
bash "$plan" --event push --sha short >/dev/null 2>&1
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  printf 'FAIL short sha was accepted\n'
  fail=1
else
  printf 'ok short sha rejected\n'
fi

workflow=$root/.github/workflows/dev-images-publish.yml
grep -q 'cron: "45 15 \* \* \*"' "$workflow" || {
  printf 'FAIL publish cron\n'
  fail=1
}
grep -q 'group: dev-images-publish' "$workflow" || {
  printf 'FAIL publish concurrency\n'
  fail=1
}
grep -q 'cancel-in-progress: false' "$workflow" || {
  printf 'FAIL publish concurrency cancels\n'
  fail=1
}
grep -q "needs.plan.outputs.publish == 'release'" "$workflow" || {
  printf 'FAIL release job is not limited to publish=release\n'
  fail=1
}
grep -q "needs.base.result == 'success'" "$workflow" || {
  printf 'FAIL release job does not require base\n'
  fail=1
}
grep -q 'Dev images scheduled publish failed' "$workflow" || {
  printf 'FAIL scheduled publish notice\n'
  fail=1
}
grep -q "github.event_name == 'schedule'" "$workflow" || {
  printf 'FAIL scheduled notice is not limited to the schedule\n'
  fail=1
}

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
printf 'plan release tests passed\n'
