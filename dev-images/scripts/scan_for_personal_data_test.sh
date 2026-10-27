#!/usr/bin/env bash
# The scanner rejects a private-source marker and accepts this tree.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
scanner=$root/dev-images/scripts/scan_for_personal_data.sh
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

printf 'clean text\n' >"$temporary/note.txt"
bash "$scanner" --root "$temporary"

marker=$(printf '%s%s' 'gh' 'p_example')
printf '%s\n' "$marker" >"$temporary/note.txt"
if bash "$scanner" --root "$temporary" >/dev/null 2>&1; then
  printf 'FAIL private marker was accepted\n' >&2
  exit 1
fi

bash "$scanner"
printf 'personal data scan tests passed\n'
