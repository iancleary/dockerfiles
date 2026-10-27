#!/usr/bin/env bash
# Tag selection for the manifest list, and exact digest artifact names.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
merge=$root/dev-images/scripts/merge_image_manifests.sh
image=ghcr.io/iancleary/dev-base
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
amd64_digest=$(printf 'a%.0s' $(seq 1 64))
arm64_digest=$(printf 'b%.0s' $(seq 1 64))
: >"$temporary/$amd64_digest"
: >"$temporary/$arm64_digest"

output=$(
  DEV_IMAGES_MERGE_PRINT=1 \
    IMAGE="$image" PUBLISH=edge SHORT_SHA=0123456 DIGEST_DIR="$temporary" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:edge
-t
${image}:sha-0123456
${image}@sha256:${amd64_digest}
${image}@sha256:${arm64_digest}
primary=${image}:edge
EOF
)
if [[ "$output" != "$expected" ]]; then
  printf 'edge manifest tags mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$output") || true
  exit 1
fi

output=$(
  DEV_IMAGES_MERGE_PRINT=1 \
    IMAGE="$image" PUBLISH=release IMAGE_VERSION=2026.10.24.01 SHORT_SHA=0123456 DIGEST_DIR="$temporary" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:sha-0123456
${image}@sha256:${amd64_digest}
${image}@sha256:${arm64_digest}
primary=${image}:sha-0123456
EOF
)
if [[ "$output" != "$expected" ]]; then
  printf 'release manifest tags mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$output") || true
  exit 1
fi

if DEV_IMAGES_MERGE_PRINT=1 \
  IMAGE="$image" PUBLISH=release IMAGE_VERSION=edge DIGEST_DIR="$temporary" \
  bash "$merge" >/dev/null 2>&1; then
  printf 'calver check did not fail\n'
  exit 1
fi

four=$temporary/four
mkdir "$four"
for hex in a b c d; do
  name=$(printf '%s' "$hex"; printf '0%.0s' $(seq 1 63))
  : >"$four/$name"
done
if DEV_IMAGES_MERGE_PRINT=1 \
  IMAGE="$image" PUBLISH=edge SHORT_SHA=0123456 DIGEST_DIR="$four" \
  bash "$merge" >/dev/null 2>"$temporary/four-error"; then
  printf 'four arch digests did not fail\n'
  exit 1
fi
if ! grep -F -q 'expected 2 arch digests, found 4' "$temporary/four-error"; then
  printf 'four arch digests failed for the wrong reason\n'
  exit 1
fi

if grep -n ':latest' "$merge" | grep -v -E '^[0-9]+:[[:space:]]*#'; then
  printf 'per-image merge must not publish :latest\n'
  exit 1
fi

build_workflow=$root/.github/workflows/dev-images-build-single-image.yml
if grep -n -E '^[[:space:]]+pattern:' "$build_workflow"; then
  printf 'digest download must use an exact artifact name, not a pattern\n'
  exit 1
fi
# shellcheck disable=SC2016
grep -F -q 'name: dev-images-digest_${{ inputs.recipe }}_${{ matrix.suffix }}' "$build_workflow" \
  || {
    printf 'digest upload name is not exact\n'
    exit 1
  }
# shellcheck disable=SC2016
grep -F -q 'name: dev-images-digest_${{ inputs.recipe }}_amd64' "$build_workflow" \
  || {
    printf 'amd64 digest download is not exact\n'
    exit 1
  }
# shellcheck disable=SC2016
grep -F -q 'name: dev-images-digest_${{ inputs.recipe }}_arm64' "$build_workflow" \
  || {
    printf 'arm64 digest download is not exact\n'
    exit 1
  }

printf 'manifest tag tests passed\n'
