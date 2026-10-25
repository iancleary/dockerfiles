#!/usr/bin/env bash
# Push the image ci-build.sh loaded, by digest, after the smoke test.
# The second build is the cached result of that load. The pushed config
# digest has to match the image that was smoked. Every recipe uses this path.
set -euo pipefail

: "${PLATFORM:?PLATFORM is required}"
: "${IMAGE:?IMAGE is required}"
: "${RECIPE:?RECIPE is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

case "$RECIPE" in
  agent-cli | python | rust | go | pi | codex | claude) ;;
  *)
    printf 'unknown recipe %s\n' "$RECIPE" >&2
    exit 1
    ;;
esac

local_tag="openshell-ci-${RECIPE}:smoke"
if ! docker image inspect "$local_tag" >/dev/null 2>&1; then
  printf 'smoked image %s is not loaded\n' "$local_tag" >&2
  exit 1
fi
local_id=$(docker image inspect --format '{{.Id}}' "$local_tag")
if [[ ! "$local_id" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'smoked image id is not a digest: %s\n' "$local_id" >&2
  exit 1
fi

flags=(--platform "$PLATFORM" --provenance=false --sbom=false)
meta=${RUNNER_TEMP}/meta-push.json
flags+=(--metadata-file "$meta")
flags+=(--output "type=image,name=${IMAGE},push-by-digest=true,name-canonical=true,push=true")

export OPENSHELL_BUILDX=1
export OPENSHELL_NO_TAG=1
export OPENSHELL_BUILD_FLAGS="${flags[*]}"

just "openshell::${RECIPE}"

digest=$(jq -r '."containerimage.digest" // empty' "$meta")
if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'missing image digest in push metadata\n' >&2
  exit 1
fi

remote_config=
attempt=1
while ((attempt <= 3)); do
  if remote=$(docker buildx imagetools inspect --raw "${IMAGE}@${digest}" 2>/dev/null); then
    remote_config=$(jq -r '.config.digest // empty' <<<"$remote")
    if [[ -n "$remote_config" ]]; then
      break
    fi
  fi
  sleep 2
  attempt=$((attempt + 1))
done
if [[ "$remote_config" != "$local_id" ]]; then
  printf 'pushed %s config %s does not match smoked image %s\n' \
    "${IMAGE}@${digest}" "${remote_config:-missing}" "$local_id" >&2
  exit 1
fi

mkdir -p "${RUNNER_TEMP}/digests"
: >"${RUNNER_TEMP}/digests/${digest#sha256:}"
printf 'digest=%s\n' "$digest" >>"$GITHUB_OUTPUT"
