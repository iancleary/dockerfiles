#!/usr/bin/env bash
# Tag every image with the calver and :latest, then create the git release.
# The release job calls this only after every image manifest succeeded.
# Digests are still checked first, and no image is tagged if one is missing.
set -euo pipefail

: "${GIT_TAG:?GIT_TAG is required}"
: "${IMAGE_VERSION:?IMAGE_VERSION is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

if [[ ! "$GIT_TAG" =~ ^openshell-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  printf 'refusing to create tag %s\n' "$GIT_TAG" >&2
  exit 1
fi
if [[ "$GIT_TAG" != "openshell-${IMAGE_VERSION}" ]]; then
  printf 'git tag %s does not match image version %s\n' "$GIT_TAG" "$IMAGE_VERSION" >&2
  exit 1
fi
if [[ ! "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'GITHUB_SHA must be 40 lowercase hex characters\n' >&2
  exit 1
fi

images=(
  agent-cli
  python
  rust
  go
  pi
  codex
  codex-pi
  claude
)

registry=ghcr.io/iancleary
refs=()
for id in "${images[@]}"; do
  var=DIGEST_${id//-/_}
  if [[ ! -v $var ]]; then
    printf 'refusing to tag any image; missing digest for %s\n' "$id" >&2
    exit 1
  fi
  digest=${!var}
  if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    printf 'refusing to tag any image; missing digest for %s\n' "$id" >&2
    exit 1
  fi
  refs+=("${registry}/openshell-${id}@${digest}")
done

if [[ -n "${OPENSHELL_RELEASE_PRINT:-}" ]]; then
  for ref in "${refs[@]}"; do
    image=${ref%@*}
    printf '%s\n' -t "${image}:${IMAGE_VERSION}" -t "${image}:latest" "$ref"
  done
  printf 'git_tag=%s\n' "$GIT_TAG"
  exit 0
fi

for ref in "${refs[@]}"; do
  image=${ref%@*}
  docker buildx imagetools create \
    -t "${image}:${IMAGE_VERSION}" \
    -t "${image}:latest" \
    "$ref"
done

git fetch --tags origin
if git rev-parse -q --verify "refs/tags/${GIT_TAG}^{}" >/dev/null; then
  existing=$(git rev-parse "refs/tags/${GIT_TAG}^{}")
  if [[ "$existing" != "$GITHUB_SHA" ]]; then
    printf 'tag %s already points at %s\n' "$GIT_TAG" "$existing" >&2
    exit 1
  fi
  printf 'tag %s already exists on this commit\n' "$GIT_TAG"
  exit 0
fi

notes=$(
  cat <<EOF
OpenShell images ${IMAGE_VERSION}.

Multi-arch (linux/amd64, linux/arm64) manifest lists, also tagged :latest:

- ghcr.io/iancleary/openshell-agent-cli:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-python:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-rust:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-go:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-pi:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-codex:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-codex-pi:${IMAGE_VERSION}
- ghcr.io/iancleary/openshell-claude:${IMAGE_VERSION}

:edge is unchanged by this release.

Commit: ${GITHUB_SHA}
EOF
)

gh release create "$GIT_TAG" --title "$GIT_TAG" --notes "$notes" --target "$GITHUB_SHA"
