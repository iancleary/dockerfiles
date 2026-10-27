#!/usr/bin/env bash
# latest_stable policy and catalog shape. Does not download.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
updater=$root/dev-images/scripts/update_pinned_versions.sh
# shellcheck disable=SC1090,SC1091
source "$updater"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local name=$1 actual=$2 expected=$3
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL %s: got [%s] want [%s]\n' "$name" "$actual" "$expected" >&2
    exit 1
  fi
}

assert_equal "newest stable" \
  "$(choose_latest_stable_version demo 1.2.3 1.2.0 1.10.0 1.3.0)" \
  "1.10.0"
assert_equal "current remains when it is newest" \
  "$(choose_latest_stable_version demo 1.2.3 1.2.3 1.2.0)" \
  "1.2.3"
assert_equal "prerelease candidate is skipped" \
  "$(choose_latest_stable_version demo 1.0.0 1.2.3-rc1 1.1.0)" \
  "1.1.0"

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
status=0
(choose_latest_stable_version demo 2.0.0 1.9.0) >"$temporary/downgrade.out" 2>"$temporary/downgrade.err" || status=$?
if [[ "$status" -ne 2 ]]; then
  fail "downgrade exited $status"
fi
grep -F -q 'refusing to downgrade' "$temporary/downgrade.err" || fail "downgrade message"

for forbidden in 'go.dev' 'nodejs.org' 'static.rust-lang.org' 'python-build-standalone' 'claude' 'codex'; do
  if grep -F -q "$forbidden" "$updater"; then
    fail "updater tracks $forbidden"
  fi
done

grep -F -q 'latest_stable' "$updater" || fail "policy name"
grep -F -q 'versions/debian.env' "$updater" || fail "debian version file"
grep -F -q 'openshell/versions/base.env' "$updater" || fail "openshell debian pin"
grep -F -q 'DEBIAN_IMAGE' "$updater" || fail "debian image key"
if grep -n '^  bump_debian$' "$root/openshell/scripts/bump-versions.sh"; then
  fail "OpenShell Monday update still writes the Debian digest"
fi

version_directory=$root/dev-images/versions
for version_file in "$version_directory"/*.env; do
  base=$(basename "$version_file" .env)
  [[ "$base" == debian ]] && continue
  grep -F -q "update_github_release_tool ${base} " "$updater" || fail "catalog omits $base"
done

openshell_digest=$(grep -E '^DEBIAN_IMAGE=' "$root/openshell/versions/base.env")
development_digest=$(grep -E '^DEBIAN_IMAGE=' "$version_directory/debian.env")
[[ "$openshell_digest" == "$development_digest" ]] || fail "debian digests start unequal"

grep -F -q 'AHI_VERSION=0.1.3' "$version_directory/ahi.env" || fail "ahi version"
grep -F -q 'AHI_SHA256_AMD64=59479bee2dc0a3fd092aaa9705472d44ca953ea3f2e6dbef0e93df925441e4df' \
  "$version_directory/ahi.env" || fail "ahi amd64 checksum"
grep -F -q 'AHI_SHA256_ARM64=bae5d3cba3c116e2224c02fe37d5020fb9db2bf9ad843221fb090bed783da181' \
  "$version_directory/ahi.env" || fail "ahi arm64 checksum"
grep -F -q 'ahi-0.1.3-sha256sums.txt' "$version_directory/ahi.env" || fail "ahi checksum source"

workflow=$root/.github/workflows/dev-images-update-pinned-versions.yml
grep -q 'cron: "30 13 \* \* 1"' "$workflow" || fail "update cron"
grep -F -q 'group: dev-images-update-pinned-versions' "$workflow" || fail "update concurrency"
grep -F -q 'cancel-in-progress: false' "$workflow" || fail "update concurrency cancels"
grep -F -q 'git fetch origin main' "$workflow" || fail "fetch before push"
grep -F -q 'git rebase origin/main' "$workflow" || fail "rebase before push"
grep -F -q 'Dev images pinned version update failed' "$workflow" || fail "failure issue title"
grep -F -q 'just dev-images::all' "$workflow" || fail "verify does not build"
grep -F -q 'publish=release' "$workflow" || fail "release dispatch"
grep -F -q 'openshell/versions/base.env' "$workflow" || fail "update commit omits the OpenShell Debian pin"
if grep -E -q 'contents: write' "$workflow" && ! grep -n 'contents: write' "$workflow" | grep -q 'publish:'; then
  :
fi
publish_permissions=$(awk '
  /^  publish:$/ { in_job=1; next }
  in_job && /^  [a-z]/ { exit }
  in_job && /contents: write/ { found=1 }
  END { if (found) print "yes" }
' "$workflow")
[[ "$publish_permissions" == yes ]] || fail "publish job lacks contents write"

printf 'pinned version update tests passed\n'
