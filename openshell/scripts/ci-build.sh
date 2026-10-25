#!/usr/bin/env bash
# Native-arch build used by the OpenShell image workflow.
# Every image is loaded locally and not pushed. The smoke step runs next,
# and ci-push.sh pushes that image by digest only if the smoke passes.
# The manifest job applies tags.
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

local_tag="openshell-ci-${RECIPE}:smoke"
printf 'load %s for %s\n' "$local_tag" "$IMAGE"
case "$RECIPE" in
  agent-cli) export OPENSHELL_AGENT_CLI_TAG=$local_tag ;;
  python) export OPENSHELL_PYTHON_TAG=$local_tag ;;
  rust) export OPENSHELL_RUST_TAG=$local_tag ;;
  go) export OPENSHELL_GO_TAG=$local_tag ;;
  pi) export OPENSHELL_PI_TAG=$local_tag ;;
  codex) export OPENSHELL_CODEX_TAG=$local_tag ;;
  claude) export OPENSHELL_CLAUDE_TAG=$local_tag ;;
esac
flags+=(--output=type=docker)
export OPENSHELL_BUILDX=1
unset OPENSHELL_NO_TAG
export OPENSHELL_BUILD_FLAGS="${flags[*]}"
just "openshell::${RECIPE}"
if ! docker image inspect "$local_tag" >/dev/null 2>&1; then
  printf 'build did not load %s\n' "$local_tag" >&2
  exit 1
fi
printf 'smoke=true\n' >>"$GITHUB_OUTPUT"
printf 'local_tag=%s\n' "$local_tag" >>"$GITHUB_OUTPUT"
