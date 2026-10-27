#!/usr/bin/env bash
# Push the image build_image.sh loaded, by digest, after the smoke test.
# The second build is the cached result of that load. Both exports rewrite
# timestamps to the Unix epoch, and the pushed config digest has to match
# the image that was smoked.
set -euo pipefail

: "${PLATFORM:?PLATFORM is required}"
: "${IMAGE:?IMAGE is required}"
: "${RECIPE:?RECIPE is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

if [[ "$RECIPE" != base ]]; then
  printf 'unknown recipe %s\n' "$RECIPE" >&2
  exit 1
fi

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$script_directory/build_image.sh"

local_tag=dev-images-ci-base:smoke
if ! docker image inspect "$local_tag" >/dev/null 2>&1; then
  printf 'smoked image %s is not loaded\n' "$local_tag" >&2
  exit 1
fi
# docker image inspect reports the manifest digest when the containerd image
# store is in use. The registry comparison uses the image config blob.
if [[ -f "${RUNNER_TEMP}/dev-images-smoked-config" ]]; then
  local_id=$(tr -d '[:space:]' <"${RUNNER_TEMP}/dev-images-smoked-config")
else
  local_id=$(docker image inspect --format '{{.Id}}' "$local_tag")
fi
if [[ ! "$local_id" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'smoked image id is not a digest: %s\n' "$local_id" >&2
  exit 1
fi

flags=(--platform "$PLATFORM" --provenance=false --sbom=false)
metadata_file=${RUNNER_TEMP}/meta-push.json
flags+=(--metadata-file "$metadata_file")
flags+=(--output "type=image,name=${IMAGE},push-by-digest=true,name-canonical=true,push=true,rewrite-timestamp=true")

export DEV_IMAGES_BUILD_FLAGS="${flags[*]}"
export DEV_IMAGES_NO_TAG=1
unset DEV_BASE_TAG

run_development_base_build

digest=$(jq -r '."containerimage.digest" // empty' "$metadata_file")
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
