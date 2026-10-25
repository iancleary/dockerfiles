#!/usr/bin/env bash
# Build one OpenShell image. Local builds load it into the Docker engine.
# CI sets OPENSHELL_BUILDX, OPENSHELL_NO_TAG, and OPENSHELL_BUILD_FLAGS.
set -euo pipefail

if [[ $# -lt 4 ]]; then
  printf 'usage: docker-build.sh DOCKERFILE CONTEXT TAG VERSION_KEY...\n' >&2
  exit 2
fi

dockerfile=$1
context=$2
tag=$3
shift 3

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
versions_dir=$root/versions

lookup_version() {
  local key=$1 file val hits=()
  if [[ ! "$key" =~ ^[A-Z0-9_]+$ ]]; then
    printf 'invalid version key: %s\n' "$key" >&2
    exit 1
  fi
  for file in "$versions_dir"/*.env; do
    [[ -f "$file" ]] || continue
    if grep -q -E "^${key}=" "$file"; then
      hits+=("$file")
    fi
  done
  if [[ ${#hits[@]} -ne 1 ]]; then
    printf 'version pin %s must appear in exactly one file under versions/\n' "$key" >&2
    exit 1
  fi
  val=$(grep -E "^${key}=" "${hits[0]}" | head -1 | cut -d= -f2-)
  if [[ -z "$val" ]]; then
    printf 'missing version pin %s\n' "$key" >&2
    exit 1
  fi
  printf '%s' "$val"
}

if [[ ! -f "$dockerfile" || ! -d "$context" ]]; then
  printf 'missing Dockerfile or context\n' >&2
  exit 1
fi

if [[ -n "${OPENSHELL_GIT_SHA:-}" ]]; then
  git_sha=$OPENSHELL_GIT_SHA
elif git_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null); then
  :
else
  git_sha=unknown
fi
image_version=${OPENSHELL_IMAGE_VERSION:-local}

layer=$(basename "$(dirname "$dockerfile")")
image_title=openshell-${layer}

base_image=
base_args=()
if grep -q '^ARG BASE_IMAGE=' "$dockerfile"; then
  if [[ -n "${OPENSHELL_BUILDX:-}" && -z "${OPENSHELL_BASE_IMAGE:-}" ]]; then
    printf 'CI build of %s requires OPENSHELL_BASE_IMAGE\n' "$image_title" >&2
    exit 1
  fi
  base_image=${OPENSHELL_BASE_IMAGE:-openshell-agent-cli:phase1}
  base_args+=(--build-arg "BASE_IMAGE=${base_image}")
fi

debian_image=
if grep -q '^ARG DEBIAN_IMAGE$' "$dockerfile"; then
  debian_image=$(lookup_version DEBIAN_IMAGE)
  if [[ ! "$debian_image" =~ ^debian:bookworm-slim@sha256:[a-f0-9]{64}$ ]]; then
    printf 'DEBIAN_IMAGE must be debian:bookworm-slim pinned by digest\n' >&2
    exit 1
  fi
fi

if [[ -n "${OPENSHELL_BASE_DIGEST:-}" ]]; then
  base_digest=$OPENSHELL_BASE_DIGEST
elif [[ -n "$debian_image" ]]; then
  base_digest=${debian_image##*@}
elif [[ -n "$base_image" ]] && docker image inspect "$base_image" >/dev/null 2>&1; then
  repo_digest=$(docker image inspect "$base_image" --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}')
  if [[ "$repo_digest" == *@sha256:* ]]; then
    base_digest=${repo_digest##*@}
  else
    base_digest=$(docker image inspect "$base_image" --format '{{.Id}}')
  fi
else
  base_digest=unknown
fi

if [[ "$base_digest" != unknown && ! "$base_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'base digest is not sha256: %s\n' "$base_digest" >&2
  exit 1
fi
if [[ -n "${OPENSHELL_BUILDX:-}" && "$base_digest" == unknown ]]; then
  printf 'CI build of %s requires OPENSHELL_BASE_DIGEST\n' "$image_title" >&2
  exit 1
fi

tool_parts=()
for key in "$@"; do
  val=$(lookup_version "$key")
  tool_parts+=("${key}=${val}")
done
tool_versions=$(IFS=,; printf '%s' "${tool_parts[*]}")

printf 'building %s version=%s revision=%s base=%s tools=%s\n' \
  "$image_title" "$image_version" "$git_sha" "$base_digest" "$tool_versions"

if [[ -n "${OPENSHELL_BUILDX:-}" ]]; then
  cmd=(docker buildx build)
else
  cmd=(docker build)
fi

if [[ -n "${OPENSHELL_BUILD_FLAGS:-}" ]]; then
  # Word-splitting is intentional: CI passes a space-separated flag list.
  # shellcheck disable=SC2206
  extra=(${OPENSHELL_BUILD_FLAGS})
  cmd+=("${extra[@]}")
fi

cmd+=(
  --build-arg "GIT_SHA=${git_sha}"
  --build-arg "IMAGE_VERSION=${image_version}"
  --build-arg "IMAGE_TITLE=${image_title}"
  --build-arg "BASE_DIGEST=${base_digest}"
  --build-arg "TOOL_VERSIONS=${tool_versions}"
)
if ((${#base_args[@]})); then
  cmd+=("${base_args[@]}")
fi
if [[ -n "$debian_image" ]]; then
  cmd+=(--build-arg "DEBIAN_IMAGE=${debian_image}")
fi
if [[ -z "${OPENSHELL_NO_TAG:-}" ]]; then
  cmd+=(-t "$tag")
fi
cmd+=(-f "$dockerfile" "$context")

"${cmd[@]}"
