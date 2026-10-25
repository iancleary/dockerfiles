#!/usr/bin/env bash
# Static checks for image users, workflow permissions, and download pinning.
# Does not start Docker and does not download artifacts.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
cd "$root"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

final_user() {
  local file=$1 line last=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^USER[[:space:]]+ ]] || continue
    last=${line#USER }
    last=${last%%#*}
    last=${last%"${last##*[![:space:]]}"}
  done <"$file"
  printf '%s' "$last"
}

assert_final_user() {
  local file=$1 got
  got=$(final_user "$file")
  [[ "$got" == "agent" ]] || fail "${file} final USER is [${got}], want agent"
}

for dockerfile in openshell/*/Dockerfile; do
  assert_final_user "$dockerfile"
  if grep -q '^ARG BASE_IMAGE=' "$dockerfile"; then
    grep -q '^USER root$' "$dockerfile" || fail "${dockerfile} does not switch to root for install"
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'FROM scratch\nUSER root\n' >"$tmp/Dockerfile"
got=$(final_user "$tmp/Dockerfile")
[[ "$got" == "root" ]] || fail "USER parser missed root"
if (assert_final_user "$tmp/Dockerfile") 2>/dev/null; then
  fail "root final USER was accepted"
fi

curl_line_ok() {
  local line=$1 trimmed
  trimmed=${line#"${line%%[![:space:]]*}"}
  [[ "$trimmed" == \#* ]] && return 0
  [[ "$trimmed" == "command -v curl "* ]] && return 0
  # A curl invocation, not a helper name such as github_curl.
  if [[ "$trimmed" != curl[[:space:]]* && "$trimmed" != *"(curl "* && "$trimmed" != *"=curl "* ]]; then
    return 0
  fi
  # shellcheck disable=SC2016
  if [[ "$trimmed" == *'curl "${args[@]}"'* ]]; then
    return 0
  fi
  [[ "$line" == *"--proto '=https'"* && "$line" == *'--tlsv1.2'* ]]
}

check_downloads() {
  local file=$1 line trimmed code
  code=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ "$trimmed" == \#* ]] && continue
    printf '%s\n' "$line"
  done <"$file" >"$code"
  if grep -E -q 'wget|rustup|cargo install|uv python install|uv tool install|npm |npx ' "$code"; then
    fail "${file} has a floating installer"
  fi
  if grep -E -q 'curl[^|]*\|[[:space:]]*(sh|bash)|wget[^|]*\|[[:space:]]*(sh|bash)' "$code"; then
    fail "${file} pipes a download into a shell"
  fi
  if grep -q 'pip install' "$code" && ! grep -q -- '--require-hashes' "$code"; then
    fail "${file} installs Python packages without --require-hashes"
  fi
  if grep -E -q '(^|[^[:alnum:]_-])curl[[:space:]]' "$code"; then
    grep -q -- "--proto '=https'" "$code" || fail "${file} curl is not https-only"
    grep -q -- '--tlsv1.2' "$code" || fail "${file} curl does not pin TLS 1.2"
    grep -q 'sha256sum -c' "$code" || fail "${file} downloads without sha256sum -c"
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    curl_line_ok "$line" || fail "${file} curl is missing https flags: ${line}"
  done <"$code"
  rm -f "$code"
}

while IFS= read -r file; do
  check_downloads "$file"
done < <(find openshell -type f \( -name 'install-*.sh' -o -name 'Dockerfile' -o -name 'bump-versions.sh' \))

for installer in openshell/common/install-agent-cli.sh openshell/python/install-python.sh \
  openshell/rust/install-rust.sh openshell/go/install-go.sh openshell/pi/install-pi.sh \
  openshell/codex/install-codex.sh openshell/claude/install-claude.sh; do
  grep -q 'harden_runtime' "$installer" || fail "${installer} does not harden the runtime"
done

grep -q '%2B' openshell/python/install-python.sh || fail "CPython URL must encode the plus in the asset name"
grep -q -- '--require-hashes' openshell/python/install-python.sh || fail "pre-commit install dropped --require-hashes"
pre_ver=$(grep -E '^PRE_COMMIT_VERSION=' openshell/versions/python.env | cut -d= -f2-)
grep -q "^pre-commit==${pre_ver} " openshell/versions/pre-commit-requirements.txt \
  || fail "pre-commit requirements do not pin ${pre_ver}"
grep -q -- '--hash=sha256:' openshell/versions/pre-commit-requirements.txt \
  || fail "pre-commit requirements have no hashes"
# shellcheck disable=SC1091
. openshell/scripts/bump-versions.sh
requirements_lines_ok openshell/versions/pre-commit-requirements.txt \
  || fail "pre-commit requirements have an unexpected line"

assert_top_permissions() {
  local file=$1 count next
  count=$(grep -c '^permissions:$' "$file")
  [[ "$count" -eq 1 ]] || fail "${file} has ${count} top-level permissions blocks"
  next=$(grep -A1 '^permissions:$' "$file" | tail -n 1)
  [[ "$next" == "  contents: read" ]] || fail "${file} top-level permissions are not contents: read"
}

job_permissions() {
  awk '
    /^jobs:/ { jobs=1; next }
    jobs && /^  [A-Za-z0-9-]+:$/ {
      if (job != "" && !saw) print "MISSING " job
      job=$1
      sub(/:$/, "", job)
      saw=0
      collecting=0
      next
    }
    jobs && job != "" && /^    permissions:$/ { saw=1; collecting=1; next }
    jobs && collecting && /^      [A-Za-z0-9-]+: [A-Za-z]+$/ {
      key=$1
      sub(/:$/, "", key)
      print job " " key " " $2
      next
    }
    jobs && collecting && /^      / {
      print "BADPERM " job " " $0
      collecting=0
      next
    }
    jobs && collecting { collecting=0 }
    END { if (job != "" && !saw) print "MISSING " job }
  ' "$1"
}

expect_jobs() {
  local file=$1 got want
  shift
  got=$(job_permissions "$file" | sort)
  want=$(printf '%s\n' "$@" | sort)
  if [[ "$got" != "$want" ]]; then
    printf '%s\n' "$got" >&2
    fail "${file} job permissions drifted"
  fi
}

for workflow in .github/workflows/openshell-images.yml \
  .github/workflows/openshell-bump.yml \
  .github/workflows/openshell-build-image.yml; do
  assert_top_permissions "$workflow"
  if grep -n -E 'uses:[[:space:]]*[^[:space:]@]+@' "$workflow" | grep -v -E 'uses:[[:space:]]*[^[:space:]@]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$'; then
    fail "${workflow} has an action that is not pinned to a full SHA and version comment"
  fi
done

job_lines() {
  local job=$1 line
  shift
  for line in "$@"; do
    printf '%s %s\n' "$job" "$line"
  done
}
build_lines() {
  job_lines "$1" "attestations write" "contents read" "id-token write" "packages write"
}
expect_jobs .github/workflows/openshell-images.yml \
  "$(job_lines plan "contents read")" \
  "$(job_lines resolve-parent "contents read" "packages read")" \
  "$(build_lines agent-cli)" \
  "$(build_lines python)" \
  "$(build_lines rust)" \
  "$(build_lines go)" \
  "$(build_lines pi)" \
  "$(build_lines codex)" \
  "$(build_lines claude)" \
  "$(job_lines release "contents write")"
expect_jobs .github/workflows/openshell-bump.yml \
  "$(job_lines bump "contents read")" \
  "$(job_lines verify "contents read")" \
  "$(job_lines publish "actions write" "contents write")" \
  "$(job_lines notify "issues write")"
expect_jobs .github/workflows/openshell-build-image.yml \
  "$(build_lines build)" \
  "$(build_lines merge)"

if grep -n 'actions: write' .github/workflows/openshell-images.yml .github/workflows/openshell-build-image.yml; then
  fail "actions: write is only for the bump publish job"
fi
if grep -n 'issues: write' .github/workflows/openshell-images.yml .github/workflows/openshell-build-image.yml .github/workflows/openshell-bump.yml | grep -v 'openshell-bump.yml'; then
  fail "issues: write leaked outside the bump workflow"
fi
issues_jobs=$(awk '
  /^  [A-Za-z0-9-]+:$/ { job=$1; sub(/:$/, "", job) }
  /^      issues: write$/ { print job }
' .github/workflows/openshell-bump.yml)
[[ "$issues_jobs" == "notify" ]] || fail "issues: write is not limited to notify"
actions_jobs=$(awk '
  /^  [A-Za-z0-9-]+:$/ { job=$1; sub(/:$/, "", job) }
  /^      actions: write$/ { print job }
' .github/workflows/openshell-bump.yml)
[[ "$actions_jobs" == "publish" ]] || fail "actions: write is not limited to publish"

printf 'supply chain tests passed\n'
