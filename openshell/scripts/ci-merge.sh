#!/usr/bin/env bash
# Join per-arch digests into one manifest list and print its digest.
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
: "${PUBLISH:?PUBLISH is required}"
: "${DIGEST_DIR:?DIGEST_DIR is required}"

if [[ "$PUBLISH" == release ]]; then
  : "${IMAGE_VERSION:?IMAGE_VERSION is required}"
  : "${SHORT_SHA:?SHORT_SHA is required}"
  if [[ ! "$IMAGE_VERSION" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    printf 'bad calver %s\n' "$IMAGE_VERSION" >&2
    exit 1
  fi
  if [[ ! "$SHORT_SHA" =~ ^[0-9a-f]{7}$ ]]; then
    printf 'bad short sha %s\n' "$SHORT_SHA" >&2
    exit 1
  fi
  # The list needs a registry reference. Calver and :latest are applied by
  # the release job, and only after every image manifest has succeeded.
  primary=${IMAGE}:sha-${SHORT_SHA}
  tag_args=(-t "$primary")
elif [[ "$PUBLISH" == edge ]]; then
  : "${SHORT_SHA:?SHORT_SHA is required}"
  if [[ ! "$SHORT_SHA" =~ ^[0-9a-f]{7}$ ]]; then
    printf 'bad short sha %s\n' "$SHORT_SHA" >&2
    exit 1
  fi
  primary=${IMAGE}:edge
  tag_args=(-t "$primary" -t "${IMAGE}:sha-${SHORT_SHA}")
else
  printf 'refusing publish mode %s\n' "$PUBLISH" >&2
  exit 1
fi

mapfile -t files < <(find "$DIGEST_DIR" -type f -printf '%f\n' | sort)
if [[ ${#files[@]} -ne 2 ]]; then
  printf 'expected 2 arch digests, found %s\n' "${#files[@]}" >&2
  printf '%s\n' "${files[@]}" >&2
  exit 1
fi

refs=()
for file in "${files[@]}"; do
  if [[ ! "$file" =~ ^[a-f0-9]{64}$ ]]; then
    printf 'unexpected digest file %s\n' "$file" >&2
    exit 1
  fi
  refs+=("${IMAGE}@sha256:${file}")
done

if [[ -n "${OPENSHELL_MERGE_PRINT:-}" ]]; then
  printf '%s\n' "${tag_args[@]}" "${refs[@]}"
  printf 'primary=%s\n' "$primary"
  exit 0
fi

docker buildx imagetools create "${tag_args[@]}" "${refs[@]}"
digest=$(docker buildx imagetools inspect "$primary" --format '{{.Manifest.Digest}}')
if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  printf 'manifest digest not found (%s)\n' "$digest" >&2
  exit 1
fi
printf '%s\n' "$digest"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'digest=%s\n' "$digest" >>"$GITHUB_OUTPUT"
fi
