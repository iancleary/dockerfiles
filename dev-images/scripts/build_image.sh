#!/usr/bin/env bash
# Build dev-base from the recorded version files.
# Local use loads dev-base:local. Continuous integration loads
# dev-images-ci-base:smoke and does not push. The push script publishes
# that loaded image by digest after the smoke test.
set -euo pipefail

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -P -- "$script_directory/../.." && pwd -P)
versions_directory=$repository_root/dev-images/versions
dockerfile=$repository_root/dev-images/base/Dockerfile
build_context=$repository_root/dev-images

read_recorded_value() {
  local version_file=$1 key=$2 line
  line=$(grep -E "^${key}=" "$version_file" | head -n 1) || true
  if [[ -z "$line" ]]; then
    printf 'missing %s in %s\n' "$key" "$version_file" >&2
    exit 1
  fi
  printf '%s' "${line#*=}"
}

compose_development_base_build_command() {
  local debian_image git_sha image_version base_digest tool_versions file key value
  local -a tool_parts=()
  image_build_command=()
  if [[ ! -f "$dockerfile" || ! -d "$build_context" ]]; then
    printf 'missing Dockerfile or build context\n' >&2
    exit 1
  fi
  debian_image=$(read_recorded_value "$versions_directory/debian.env" DEBIAN_IMAGE)
  if [[ ! "$debian_image" =~ ^debian:bookworm-slim@sha256:[a-f0-9]{64}$ ]]; then
    printf 'DEBIAN_IMAGE must be debian:bookworm-slim pinned by digest\n' >&2
    exit 1
  fi
  if [[ -n "${DEV_IMAGES_GIT_SHA:-}" ]]; then
    git_sha=$DEV_IMAGES_GIT_SHA
  elif git_sha=$(git -C "$repository_root" rev-parse HEAD 2>/dev/null); then
    :
  else
    git_sha=unknown
  fi
  image_version=${DEV_IMAGES_IMAGE_VERSION:-local}
  base_digest=${debian_image##*@}
  if [[ ! "$base_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    printf 'base digest is not sha256: %s\n' "$base_digest" >&2
    exit 1
  fi
  while IFS= read -r file; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^([A-Z0-9_]+_VERSION)=(.*)$ ]] || continue
      key=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      tool_parts+=("${key}=${value}")
    done <"$file"
  done < <(printf '%s\n' "$versions_directory"/*.env | LC_ALL=C sort)
  tool_versions=$(IFS=,; printf '%s' "${tool_parts[*]}")
  printf 'building dev-base version=%s revision=%s base=%s tools=%s\n' \
    "$image_version" "$git_sha" "$base_digest" "$tool_versions" >&2

  image_build_command=(docker buildx build)
  if [[ -n "${DEV_IMAGES_BUILD_FLAGS:-}" ]]; then
    # Word-splitting is intentional: callers pass a space-separated flag list.
    # shellcheck disable=SC2206
    local extra=(${DEV_IMAGES_BUILD_FLAGS})
    image_build_command+=("${extra[@]}")
  fi
  image_build_command+=(
    --build-arg "DEBIAN_IMAGE=${debian_image}"
    --build-arg "GIT_SHA=${git_sha}"
    --build-arg "IMAGE_VERSION=${image_version}"
    --build-arg "IMAGE_TITLE=dev-base"
    --build-arg "BASE_DIGEST=${base_digest}"
    --build-arg "TOOL_VERSIONS=${tool_versions}"
  )
  if [[ -z "${DEV_IMAGES_NO_TAG:-}" ]]; then
    image_build_command+=(-t "${DEV_BASE_TAG:?DEV_BASE_TAG is required}")
  fi
  image_build_command+=(-f "$dockerfile" "$build_context")
}

run_development_base_build() {
  compose_development_base_build_command
  "${image_build_command[@]}"
}

require_buildx() {
  if ! docker buildx version >/dev/null 2>&1; then
    printf 'docker buildx is required to build dev-base\n' >&2
    exit 1
  fi
}

continuous_integration_build() {
  : "${PLATFORM:?PLATFORM is required}"
  : "${IMAGE:?IMAGE is required}"
  : "${RECIPE:?RECIPE is required}"
  : "${NO_CACHE:?NO_CACHE is required}"
  : "${RUNNER_TEMP:?RUNNER_TEMP is required}"
  : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
  if [[ "$RECIPE" != base ]]; then
    printf 'unknown recipe %s\n' "$RECIPE" >&2
    exit 1
  fi
  case "$(uname -m):${PLATFORM}" in
    x86_64:linux/amd64 | aarch64:linux/arm64) ;;
    *)
      printf 'runner %s cannot build %s natively\n' "$(uname -m)" "$PLATFORM" >&2
      exit 1
      ;;
  esac
  local -a flags=(--platform "$PLATFORM" --pull --provenance=false --sbom=false)
  if [[ "$NO_CACHE" == true ]]; then
    flags+=(--no-cache)
  fi
  flags+=(--output=type=docker)
  export DEV_IMAGES_BUILD_FLAGS="${flags[*]}"
  export DEV_BASE_TAG=dev-images-ci-base:smoke
  unset DEV_IMAGES_NO_TAG
  printf 'load %s for %s\n' "$DEV_BASE_TAG" "$IMAGE" >&2
  run_development_base_build
  if ! docker image inspect "$DEV_BASE_TAG" >/dev/null 2>&1; then
    printf 'build did not load %s\n' "$DEV_BASE_TAG" >&2
    exit 1
  fi
  printf 'smoke=true\n' >>"$GITHUB_OUTPUT"
  printf 'local_tag=%s\n' "$DEV_BASE_TAG" >>"$GITHUB_OUTPUT"
}

local_build() {
  local tag=$1 platform=$2
  local -a flags=(--pull --provenance=false --sbom=false --load)
  if [[ -n "$platform" ]]; then
    flags+=(--platform "$platform")
  fi
  export DEV_IMAGES_BUILD_FLAGS="${flags[*]}"
  export DEV_BASE_TAG=$tag
  unset DEV_IMAGES_NO_TAG
  run_development_base_build
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_buildx
  if [[ -n "${PLATFORM:-}" || -n "${RECIPE:-}" ]]; then
    continuous_integration_build
    exit 0
  fi
  tag=${DEV_BASE_TAG:-dev-base:local}
  platform=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        tag=$2
        shift 2
        ;;
      --platform)
        platform=$2
        shift 2
        ;;
      *)
        printf 'usage: build_image.sh [--tag TAG] [--platform linux/amd64|linux/arm64]\n' >&2
        exit 2
        ;;
    esac
  done
  local_build "$tag" "$platform"
fi
