#!/usr/bin/env bash
# All-or-nothing calver tagging. Does not call docker or gh.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
publish=$root/dev-images/scripts/publish_release.sh
sha=0123456789abcdef0123456789abcdef01234567
digest=sha256:$(printf 'a%.0s' $(seq 1 64))

output=$(
  DEV_IMAGES_RELEASE_PRINT=1 \
    GIT_TAG=dev-images-2026.10.24.01 \
    IMAGE_VERSION=2026.10.24.01 \
    GITHUB_SHA=$sha \
    DIGEST_base=$digest \
    DIGEST_go=$digest \
    DIGEST_rust=$digest \
    DIGEST_node=$digest \
    DIGEST_python=$digest \
    DIGEST_zig=$digest \
    DIGEST_bun=$digest \
    bash "$publish"
)
expected=$(
  cat <<EOF
-t
ghcr.io/iancleary/dev-base:2026.10.24.01
-t
ghcr.io/iancleary/dev-base:latest
ghcr.io/iancleary/dev-base@${digest}
-t
ghcr.io/iancleary/dev-go:2026.10.24.01
-t
ghcr.io/iancleary/dev-go:latest
ghcr.io/iancleary/dev-go@${digest}
-t
ghcr.io/iancleary/dev-rust:2026.10.24.01
-t
ghcr.io/iancleary/dev-rust:latest
ghcr.io/iancleary/dev-rust@${digest}
-t
ghcr.io/iancleary/dev-node:2026.10.24.01
-t
ghcr.io/iancleary/dev-node:latest
ghcr.io/iancleary/dev-node@${digest}
-t
ghcr.io/iancleary/dev-python:2026.10.24.01
-t
ghcr.io/iancleary/dev-python:latest
ghcr.io/iancleary/dev-python@${digest}
-t
ghcr.io/iancleary/dev-zig:2026.10.24.01
-t
ghcr.io/iancleary/dev-zig:latest
ghcr.io/iancleary/dev-zig@${digest}
-t
ghcr.io/iancleary/dev-bun:2026.10.24.01
-t
ghcr.io/iancleary/dev-bun:latest
ghcr.io/iancleary/dev-bun@${digest}
git_tag=dev-images-2026.10.24.01
EOF
)
if [[ "$output" != "$expected" ]]; then
  printf 'release tag selection mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$output") || true
  exit 1
fi

if DEV_IMAGES_RELEASE_PRINT=1 \
  GIT_TAG=dev-images-2026.10.24.01 \
  IMAGE_VERSION=2026.10.24.01 \
  GITHUB_SHA=$sha \
  bash "$publish" >/dev/null 2>&1; then
  printf 'missing digest was accepted\n'
  exit 1
fi

if DEV_IMAGES_RELEASE_PRINT=1 \
  GIT_TAG=openshell-2026.10.24.01 \
  IMAGE_VERSION=2026.10.24.01 \
  GITHUB_SHA=$sha \
  DIGEST_base=$digest \
  bash "$publish" >/dev/null 2>&1; then
  printf 'OpenShell tag prefix was accepted\n'
  exit 1
fi

if DEV_IMAGES_RELEASE_PRINT=1 \
  GIT_TAG=dev-images-2026.10.24.02 \
  IMAGE_VERSION=2026.10.24.01 \
  GITHUB_SHA=$sha \
  DIGEST_base=$digest \
  bash "$publish" >/dev/null 2>&1; then
  printf 'tag and version mismatch was accepted\n'
  exit 1
fi

workflow=$root/.github/workflows/dev-images-publish.yml
# shellcheck disable=SC2016
grep -F -q 'DIGEST_base: ${{ needs.base.outputs.digest }}' "$workflow" \
  || {
    printf 'release job does not pass the base digest\n'
    exit 1
  }
grep -F -q 'bash dev-images/scripts/publish_release.sh' "$workflow" \
  || {
    printf 'release job does not call publish_release.sh\n'
    exit 1
  }

printf 'publish release tests passed\n'
