#!/usr/bin/env bash
# Tag selection for the manifest list. Does not call docker.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
merge=$root/openshell/scripts/ci-merge.sh
image=ghcr.io/iancleary/openshell-pi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
amd=$(printf 'a%.0s' $(seq 1 64))
arm=$(printf 'b%.0s' $(seq 1 64))
: >"$tmp/$amd"
: >"$tmp/$arm"

out=$(
  OPENSHELL_MERGE_PRINT=1 \
    IMAGE="$image" PUBLISH=edge SHORT_SHA=0123456 DIGEST_DIR="$tmp" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:edge
-t
${image}:sha-0123456
${image}@sha256:${amd}
${image}@sha256:${arm}
primary=${image}:edge
EOF
)
if [[ "$out" != "$expected" ]]; then
  printf 'edge manifest tags mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$out") || true
  exit 1
fi

out=$(
  OPENSHELL_MERGE_PRINT=1 \
    IMAGE="$image" PUBLISH=release IMAGE_VERSION=2026.10.24.01 DIGEST_DIR="$tmp" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:2026.10.24.01
-t
${image}:latest
${image}@sha256:${amd}
${image}@sha256:${arm}
primary=${image}:2026.10.24.01
EOF
)
if [[ "$out" != "$expected" ]]; then
  printf 'release manifest tags mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$out") || true
  exit 1
fi

if OPENSHELL_MERGE_PRINT=1 \
  IMAGE="$image" PUBLISH=release IMAGE_VERSION=edge DIGEST_DIR="$tmp" \
  bash "$merge" >/dev/null 2>&1; then
  printf 'calver check did not fail\n'
  exit 1
fi

printf 'manifest tag tests passed\n'
