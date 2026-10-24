#!/usr/bin/env bash
# Fail if a private-source marker shows up in the public tree.
# Patterns are generic (host shapes, emails, token shapes, home paths).
# Do not add a tailnet name, an employer name, or a model pin.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
cd "$root"

# This file is excluded so the pattern text itself is not a hit.
# "--" keeps a pattern that starts with "-" from being read as an option.
grep_tree() {
  grep -R -n -E -I --exclude-dir=.git --exclude=privacy-grep.sh -- "$@" .
}

patterns=(
  '\.ts\.net'
  'CODEX_AUTH_'
  'on-premise'
  'ghp_'
  'glpat-'
  'sk-'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '/home/'
  '/Users/'
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
)

status=0
for pat in "${patterns[@]}"; do
  rc=0
  grep_tree "$pat" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    status=1
  elif [[ "$rc" -ne 1 ]]; then
    printf 'privacy grep failed\n' >&2
    exit 2
  fi
done

# Self-hosted GitLab hosts contain "gitlab." (gitlab.<name> or <name>.gitlab.<name>).
# gitlab.com and gitlab.io are public, so those hosts are ignored.
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
printf 'privacy grep clean\n'
