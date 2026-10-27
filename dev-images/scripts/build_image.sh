#!/usr/bin/env bash
# Build one development image from the recorded version files.
# Local use loads dev-base:local, or dev-<recipe>:local. Continuous
# integration loads dev-images-ci-<recipe>:smoke and does not push.
# The push script publishes that loaded image by digest after the smoke test.
# A language image uses the named build context development-base.
# A registry parent is a docker-image context. A local tag on the container
# driver is saved to an OCI layout, because that driver cannot see the engine
# image store. The docker driver can read the local tag directly.
set -euo pipefail

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -P -- "$script_directory/../.." && pwd -P)
versions_directory=$repository_root/dev-images/versions
dockerfile=$repository_root/dev-images/base/Dockerfile
build_context=$repository_root/dev-images
parent_layout_directory=

read_recorded_value() {
  local version_file=$1 key=$2 line
  line=$(grep -E "^${key}=" "$version_file" | head -n 1) || true
  if [[ -z "$line" ]]; then
    printf 'missing %s in %s\n' "$key" "$version_file" >&2
    exit 1
  fi
  printf '%s' "${line#*=}"
}

known_recipe() {
  case "$1" in
    base | go | rust | node | python | zig | bun) return 0 ;;
  esac
  return 1
}

recipe_dockerfile() {
  local recipe=$1
  if [[ "$recipe" == base ]]; then
    printf '%s\n' "$repository_root/dev-images/base/Dockerfile"
  else
    printf '%s\n' "$repository_root/dev-images/${recipe}/Dockerfile"
  fi
}

continuous_integration_local_tag() {
  printf 'dev-images-ci-%s:smoke\n' "$1"
}

resolve_parent_image() {
  local parent=${PARENT_IMAGE:-}
  if [[ -z "$parent" ]]; then
    parent=$(read_recorded_value "$versions_directory/development-base-image.env" DEV_BASE_IMAGE)
  fi
  if [[ ! "$parent" =~ ^[A-Za-z0-9][A-Za-z0-9._:@/-]+$ ]]; then
    printf 'parent image reference is not usable: %s\n' "$parent" >&2
    exit 1
  fi
  printf '%s\n' "$parent"
}

current_buildx_driver() {
  local driver
  driver=$(docker buildx inspect 2>/dev/null | awk '/^Driver:/ { print $2; exit }')
  if [[ -z "$driver" ]]; then
    printf 'docker\n'
  else
    printf '%s\n' "$driver"
  fi
}

remove_parent_layout() {
  if [[ -n "$parent_layout_directory" ]]; then
    rm -rf "$parent_layout_directory"
    parent_layout_directory=
    parent_layout_path=
  fi
}

prepare_local_parent_layout() {
  local parent=$1 archive
  remove_parent_layout
  parent_layout_directory=$(mktemp -d)
  archive=$parent_layout_directory/image.tar
  parent_layout_path=$parent_layout_directory/layout
  mkdir -p "$parent_layout_path"
  docker save "$parent" -o "$archive"
  python3 "$script_directory/prepare_parent_image_layout.py" "$archive" "$parent_layout_path"
  rm -f "$archive"
}

parent_build_context() {
  local parent=$1 driver
  if [[ "$parent" == */* ]]; then
    parent_context_value="development-base=docker-image://${parent}"
    return
  fi
  driver=$(current_buildx_driver)
  if [[ "$driver" == "docker-container" ]]; then
    prepare_local_parent_layout "$parent"
    parent_context_value="development-base=oci-layout://${parent_layout_path}"
    return
  fi
  parent_context_value="development-base=docker-image://${parent}"
}

compose_image_build_command() {
  local recipe=${RECIPE:-base}
  local debian_image git_sha image_version base_digest tool_versions file key value parent image_tag
  local -a tool_parts=() version_files=()
  image_build_command=()
  if ! known_recipe "$recipe"; then
    printf 'unknown recipe %s\n' "$recipe" >&2
    exit 1
  fi
  dockerfile=$(recipe_dockerfile "$recipe")
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
  if [[ "$recipe" == base ]]; then
    base_digest=${debian_image##*@}
  else
    parent=$(resolve_parent_image)
    if [[ "$parent" =~ @(sha256:[a-f0-9]{64})$ ]]; then
      base_digest=${BASH_REMATCH[1]}
    else
      base_digest=local
    fi
  fi
  if [[ "$recipe" == base && ! "$base_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    printf 'base digest is not sha256: %s\n' "$base_digest" >&2
    exit 1
  fi
  mapfile -t version_files < <(grep -oE 'versions/[A-Za-z0-9._-]+\.env' "$dockerfile" | LC_ALL=C sort -u)
  for file in "${version_files[@]}"; do
    file=$repository_root/dev-images/$file
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^([A-Z0-9_]+_VERSION)=(.*)$ ]] || continue
      key=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      tool_parts+=("${key}=${value}")
    done <"$file"
  done
  tool_versions=$(IFS=,; printf '%s' "${tool_parts[*]}")
  printf 'building dev-%s version=%s revision=%s base=%s tools=%s\n' \
    "$recipe" "$image_version" "$git_sha" "$base_digest" "$tool_versions" >&2

  image_build_command=(docker buildx build)
  if [[ -n "${DEV_IMAGES_BUILD_FLAGS:-}" ]]; then
    # Word-splitting is intentional: callers pass a space-separated flag list.
    # shellcheck disable=SC2206
    local extra=(${DEV_IMAGES_BUILD_FLAGS})
    image_build_command+=("${extra[@]}")
  fi
  if [[ "$recipe" != base ]]; then
    parent_build_context "$parent"
    image_build_command+=(--build-context "$parent_context_value")
  fi
  image_build_command+=(
    --build-arg "DEBIAN_IMAGE=${debian_image}"
    --build-arg "GIT_SHA=${git_sha}"
    --build-arg "IMAGE_VERSION=${image_version}"
    --build-arg "IMAGE_TITLE=dev-${recipe}"
    --build-arg "BASE_DIGEST=${base_digest}"
    --build-arg "TOOL_VERSIONS=${tool_versions}"
    --build-arg SOURCE_DATE_EPOCH=0
  )
  if [[ -z "${DEV_IMAGES_NO_TAG:-}" ]]; then
    image_tag=${IMAGE_TAG:-${DEV_BASE_TAG:-}}
    if [[ -z "$image_tag" ]]; then
      printf 'IMAGE_TAG is required\n' >&2
      exit 1
    fi
    image_build_command+=(-t "$image_tag")
  fi
  image_build_command+=(-f "$dockerfile" "$build_context")
}

run_image_build() {
  compose_image_build_command
  "${image_build_command[@]}"
}

run_development_base_build() {
  run_image_build
}

# The docker exporter's unpack option conflicts with rewrite-timestamp, so a
# loaded image is produced by exporting a tarball and loading that tarball.
# Directory entries created by COPY --link otherwise take the build clock as
# their timestamp, and every tool layer digest changes on the next build.
record_smoked_config_digest() {
  local tar_path=$1 config_name config_digest
  if [[ -z "${RUNNER_TEMP:-}" ]]; then
    return 0
  fi
  config_name=$(python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["Config"])' < <(tar -xOf "$tar_path" manifest.json))
  config_digest=$(tar -xOf "$tar_path" "$config_name" | sha256sum | awk '{print $1}')
  if [[ ! "$config_digest" =~ ^[a-f0-9]{64}$ ]]; then
    printf 'smoked image config digest was not sha256\n' >&2
    return 1
  fi
  printf 'sha256:%s\n' "$config_digest" >"${RUNNER_TEMP}/dev-images-smoked-config"
}

load_rewritten_image() {
  local tar_path status=0
  tar_path=$(mktemp --suffix=-dev-image.tar)
  DEV_IMAGES_BUILD_FLAGS="${DEV_IMAGES_BUILD_FLAGS:-} --output type=docker,dest=${tar_path},rewrite-timestamp=true"
  export DEV_IMAGES_BUILD_FLAGS
  run_development_base_build || status=$?
  if [[ "$status" -eq 0 ]]; then
    record_smoked_config_digest "$tar_path" || status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    docker load --input "$tar_path" >&2 || status=$?
  fi
  rm -f "$tar_path"
  remove_parent_layout
  return "$status"
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
  if ! known_recipe "$RECIPE"; then
    printf 'unknown recipe %s\n' "$RECIPE" >&2
    exit 1
  fi
  if [[ "$RECIPE" != base && -z "${PARENT_IMAGE:-}" ]]; then
    printf 'PARENT_IMAGE is required for recipe %s\n' "$RECIPE" >&2
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
  local local_tag
  if [[ "$NO_CACHE" == true ]]; then
    flags+=(--no-cache)
  fi
  local_tag=$(continuous_integration_local_tag "$RECIPE")
  export DEV_IMAGES_BUILD_FLAGS="${flags[*]}"
  export IMAGE_TAG=$local_tag
  unset DEV_IMAGES_NO_TAG
  printf 'load %s for %s\n' "$IMAGE_TAG" "$IMAGE" >&2
  load_rewritten_image
  if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    printf 'build did not load %s\n' "$IMAGE_TAG" >&2
    exit 1
  fi
  printf 'smoke=true\n' >>"$GITHUB_OUTPUT"
  printf 'local_tag=%s\n' "$IMAGE_TAG" >>"$GITHUB_OUTPUT"
}

local_build() {
  local tag=$1 platform=$2 recipe=$3
  local -a flags=(--pull --provenance=false --sbom=false)
  if [[ -n "$platform" ]]; then
    flags+=(--platform "$platform")
  fi
  export RECIPE=$recipe
  export DEV_IMAGES_BUILD_FLAGS="${flags[*]}"
  export IMAGE_TAG=$tag
  unset DEV_IMAGES_NO_TAG
  load_rewritten_image
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_buildx
  if [[ -n "${PLATFORM:-}" || -n "${RECIPE:-}" ]]; then
    continuous_integration_build
    exit 0
  fi
  tag=${DEV_BASE_TAG:-}
  platform=
  recipe=base
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
      --recipe)
        recipe=$2
        shift 2
        ;;
      *)
        printf 'usage: build_image.sh [--recipe RECIPE] [--tag TAG] [--platform linux/amd64|linux/arm64]\n' >&2
        exit 2
        ;;
    esac
  done
  if ! known_recipe "$recipe"; then
    printf 'unknown recipe %s\n' "$recipe" >&2
    exit 2
  fi
  if [[ -z "$tag" ]]; then
    tag=dev-${recipe}:local
  fi
  local_build "$tag" "$platform" "$recipe"
fi
