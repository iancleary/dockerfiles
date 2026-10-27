#!/usr/bin/env bash
# Fail if a private-source marker shows up in the development image tree.
# Patterns match openshell/scripts/privacy-grep.sh. The image holds no
# secrets and no personal configuration, and the files that build it must
# not record any.
set -euo pipefail

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -P -- "$script_directory/../.." && pwd -P)

scan_root=
if [[ "${1:-}" == "--root" ]]; then
  [[ $# -eq 2 ]] || exit 2
  scan_root=$2
fi

# Fragments stay split so this file does not contain the markers it searches for.
# openshell/scripts/privacy-grep.sh scans the whole repository and excludes only itself.
patterns=(
  "$(printf '%s%s' '\.ts' '\.net')"
  "$(printf '%s%s' 'CODEX_' 'AUTH_')"
  "$(printf '%s%s' 'on-pre' 'mise')"
  "$(printf '%s%s' 'gh' 'p_')"
  "$(printf '%s%s' 'gl' 'pat-')"
  "$(printf '%s%s' 's' 'k-')"
  "$(printf '%s%s' '-----BEGIN [A-Z ]*PRIVATE ' 'KEY-----')"
  "$(printf '%s%s' '/ho' 'me/')"
  "$(printf '%s%s' '/Us' 'ers/')"
  "$(printf '%s%s' '[A-Za-z0-9._%+-]+@' '[A-Za-z0-9.-]+\.[A-Za-z]{2,}')"
)

grep_tree() {
  if [[ -n "$scan_root" ]]; then
    grep -R -n -E -I --exclude-dir=.git -- "$@" "$scan_root"
  else
    grep -R -n -E -I --exclude-dir=.git \
      --exclude=scan_for_personal_data.sh \
      --exclude='*_test.sh' \
      -- "$@" \
      "$repository_root/dev-images" \
      "$repository_root/.github/workflows/dev-images-publish.yml" \
      "$repository_root/.github/workflows/dev-images-build-single-image.yml" \
      "$repository_root/.github/workflows/dev-images-update-pinned-versions.yml" \
      "$repository_root/.github/workflows/dev-images-verify-pull-request.yml"
  fi
}

status=0
for pattern in "${patterns[@]}"; do
  command_status=0
  grep_tree "$pattern" || command_status=$?
  if [[ "$command_status" -eq 0 ]]; then
    status=1
  elif [[ "$command_status" -ne 1 ]]; then
    printf 'personal data scan failed\n' >&2
    exit 2
  fi
done

if hits=$(grep_tree 'gitlab\.' || true); [[ -n "$hits" ]]; then
  while IFS= read -r line; do
    stripped=$(printf '%s\n' "$line" | sed -E 's/gitlab\.(com|io)([^[:alnum:]-]|$)/ /g')
    if printf '%s\n' "$stripped" | grep -q 'gitlab\.'; then
      printf '%s\n' "$line"
      status=1
    fi
  done <<<"$hits"
fi

if [[ "$status" -ne 0 ]]; then
  printf 'private markers found\n' >&2
  exit 1
fi
printf 'personal data scan clean\n'
