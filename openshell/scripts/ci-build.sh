#!/usr/bin/env bash
# Native-arch build used by the OpenShell image workflow.
# Pushes by digest only. The manifest job applies tags.
set -euo pipefail

: "${PLATFORM:?PLATFORM is required}"
: "${IMAGE:?IMAGE is required}"
: "${RECIPE:?RECIPE is required}"
: "${NO_CACHE:?NO_CACHE is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

case "$RECIPE" in
  agent-cli | python | rust | go | pi | codex | claude) ;;
  *)
    printf 'unknown recipe %s\n' "$RECIPE" >&2
    exit 1
    ;;
esac

case "$(uname -m):${PLATFORM}" in
  x86_64:linux/amd64 | aarch64:linux/arm64) ;;
  *)
    printf 'runner %s cannot build %s natively\n' "$(uname -m)" "$PLATFORM" >&2
    exit 1
    ;;
esac

if [[ "$RECIPE" != agent-cli ]]; then
  if [[ ! "${OPENSHELL_BASE_IMAGE:-}" =~ ^ghcr\.io/iancleary/openshell-[a-z0-9-]+@sha256:[a-f0-9]{64}$ ]]; then
    printf 'parent image must be a ghcr digest ref\n' >&2
    exit 1
  fi
  if [[ ! "${OPENSHELL_BASE_DIGEST:-}" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    printf 'parent digest missing\n' >&2
    exit 1
  fi
fi

flags=(--platform "$PLATFORM" --pull --provenance=false --sbom=false)
if [[ "$NO_CACHE" == "true" ]]; then
  flags+=(--no-cache)
fi
meta=${RUNNER_TEMP}/meta.json
flags+=(--metadata-file "$meta")
flags+=(--output "type=image,name=${IMAGE},push-by-digest=true,name-canonical=true,push=true")

export OPENSHELL_BUILDX=1
export OPENSHELL_NO_TAG=1
export OPENSHELL_BUILD_FLAGS="${flags[*]}"

just "openshell::${RECIPE}"

digest=$(jq -r '."containerimage.digest" // empty' "$meta")
if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'missing image digest in build metadata\n' >&2
  exit 1
fi

mkdir -p "${RUNNER_TEMP}/digests"
: >"${RUNNER_TEMP}/digests/${digest#sha256:}"
printf 'digest=%s\n' "$digest" >>"$GITHUB_OUTPUT"
