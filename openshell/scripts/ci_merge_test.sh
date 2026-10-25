#!/usr/bin/env bash
# Tag selection for the manifest list, and digest artifact names.
# Does not call docker. GitHub ${{ }} expressions below are literal text.
# shellcheck disable=SC2016,SC1003
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
merge=$root/openshell/scripts/ci-merge.sh
image=ghcr.io/iancleary/openshell-pi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
amd=$(printf 'a%.0s' $(seq 1 64))
arm=$(printf 'b%.0s' $(seq 1 64))
: >"$tmp/$amd"
: >"$tmp/$arm"

out=$(
  OPENSHELL_MERGE_PRINT=1 \
    IMAGE="$image" PUBLISH=edge SHORT_SHA=0123456 DIGEST_DIR="$tmp" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:edge
-t
${image}:sha-0123456
${image}@sha256:${amd}
${image}@sha256:${arm}
primary=${image}:edge
EOF
)
if [[ "$out" != "$expected" ]]; then
  printf 'edge manifest tags mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$out") || true
  exit 1
fi

out=$(
  OPENSHELL_MERGE_PRINT=1 \
    IMAGE="$image" PUBLISH=release IMAGE_VERSION=2026.10.24.01 SHORT_SHA=0123456 DIGEST_DIR="$tmp" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:sha-0123456
${image}@sha256:${amd}
${image}@sha256:${arm}
primary=${image}:sha-0123456
EOF
)
if [[ "$out" != "$expected" ]]; then
  printf 'release manifest tags mismatch\n'
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$out") || true
  exit 1
fi

if OPENSHELL_MERGE_PRINT=1 \
  IMAGE="$image" PUBLISH=release IMAGE_VERSION=edge DIGEST_DIR="$tmp" \
  bash "$merge" >/dev/null 2>&1; then
  printf 'calver check did not fail\n'
  exit 1
fi

printf 'manifest tag tests passed\n'

four=$tmp/four
mkdir "$four"
for hex in a b c d; do
  name=$(printf '%s' "$hex"; printf '0%.0s' $(seq 1 63))
  : >"$four/$name"
done
if OPENSHELL_MERGE_PRINT=1 \
  IMAGE="$image" PUBLISH=edge SHORT_SHA=0123456 DIGEST_DIR="$four" \
  bash "$merge" >"$tmp/four-out" 2>"$tmp/four-err"; then
  printf 'four arch digests did not fail\n'
  exit 1
fi
if ! grep -F -q 'expected 2 arch digests, found 4' "$tmp/four-err"; then
  printf 'four arch digests missing the count error\n'
  cat "$tmp/four-err" >&2
  exit 1
fi

# Minimatch-style match for the digest artifact names this repo uses.
# `*` does not cross `/`. Anything else is literal. One `{a,b}` group.
glob_match() {
  local name=$1 pat=$2 regex='^' i c
  local -i n=${#pat}
  for ((i = 0; i < n; i++)); do
    c=${pat:i:1}
    case "$c" in
      '*') regex+='[^/]*' ;;
      '?' | '[' | ']' | '(' | ')')
        printf 'unsupported glob metacharacter in %s\n' "$pat" >&2
        exit 1
        ;;
      '.' | '^' | '$' | '+' | '{' | '}' | '|' | '\\') regex+="\\$c" ;;
      *) regex+="$c" ;;
    esac
  done
  regex+='$'
  [[ "$name" =~ $regex ]]
}

render_template() {
  local tmpl=$1 recipe=$2 suffix=$3 out
  out=${tmpl//'${{ inputs.recipe }}'/$recipe}
  out=${out//'${{ matrix.suffix }}'/$suffix}
  if [[ "$out" == *'${{'* ]]; then
    printf 'unsubstituted expression in %s\n' "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

yaml_scalar() {
  local line=$1 value
  value=${line#*:}
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  if [[ "$value" == \"*\" ]]; then
    value=${value:1:${#value}-2}
  elif [[ "$value" == \'*\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s\n' "$value"
}

if ! glob_match 'digests-codex-pi-amd64' "$(render_template 'digests-${{ inputs.recipe }}-*' codex '')"; then
  printf 'star fixture did not match digests-codex-pi-amd64\n' >&2
  exit 1
fi
if glob_match 'digests-codex-pi-amd64' 'digests-codex-amd64'; then
  printf 'exact digest name matched a different recipe\n' >&2
  exit 1
fi

# A star after the recipe matches another recipe when the names share a
# hyphen. codex is a prefix of codex-pi, so digests-codex-* is not safe.
scheme_overlaps() {
  local tmpl=$1 recipe suffix name star
  local -a names=()
  local -A own=()
  for recipe in "${recipes[@]}"; do
    own["$recipe"]=""
    for suffix in "${suffixes[@]}"; do
      name=$(render_template "$tmpl" "$recipe" "$suffix")
      names+=("$name")
      own["$recipe"]+="${name}"$'\n'
    done
  done
  for recipe in "${recipes[@]}"; do
    star=${tmpl/'${{ matrix.suffix }}'/*}
    star=$(render_template "$star" "$recipe" "")
    local -a matches=()
    for name in "${names[@]}"; do
      if glob_match "$name" "$star"; then
        matches+=("$name")
      fi
    done
    local expected got
    expected=$(printf '%s' "${own[$recipe]}" | sed '/^$/d' | sort)
    got=$(printf '%s\n' "${matches[@]}" | sed '/^$/d' | sort)
    if [[ "$expected" != "$got" ]]; then
      printf 'artifact scheme overlaps for %s under %s\n' "$recipe" "$star" >&2
      printf 'got:\n%s\nwant:\n%s\n' "$got" "$expected" >&2
      return 0
    fi
  done
  return 1
}

build_wf=$root/.github/workflows/openshell-build-image.yml
images_wf=$root/.github/workflows/openshell-images.yml
if grep -n -E '^[[:space:]]+pattern:' "$build_wf"; then
  printf 'digest download must use an exact artifact name, not a pattern\n' >&2
  exit 1
fi

mapfile -t suffixes < <(grep -E '^[[:space:]]+suffix:[[:space:]]+' "$build_wf" | while IFS= read -r line; do yaml_scalar "$line"; done)
suffix_set=" ${suffixes[*]} "
if [[ "$suffix_set" != *" amd64 "* || "$suffix_set" != *" arm64 "* ]]; then
  printf 'matrix is missing amd64 or arm64 (%s)\n' "${suffixes[*]}" >&2
  exit 1
fi

mapfile -t recipes < <(grep -E '^[[:space:]]+recipe:[[:space:]]+[A-Za-z0-9-]+[[:space:]]*$' "$images_wf" | while IFS= read -r line; do yaml_scalar "$line"; done | sort -u)
expected_recipes=(agent-cli claude codex codex-pi go pi python rust)
if [[ "${recipes[*]}" != "${expected_recipes[*]}" ]]; then
  printf 'image recipes changed: %s\n' "${recipes[*]}" >&2
  exit 1
fi

if ! scheme_overlaps 'digests-${{ inputs.recipe }}-${{ matrix.suffix }}' 2>/dev/null; then
  printf 'hyphen suffix scheme did not overlap for a prefix recipe\n' >&2
  exit 1
fi

mapfile -t digest_names < <(
  grep -E '^[[:space:]]+name:[[:space:]]+' "$build_wf" |
    while IFS= read -r line; do yaml_scalar "$line"; done |
    grep -F '${{ inputs.recipe }}' |
    grep -E 'matrix\.suffix|_amd64|_arm64|-amd64|-arm64'
)
upload_tmpl=
downloads=()
for item in "${digest_names[@]}"; do
  if [[ "$item" == *'${{ matrix.suffix }}'* ]]; then
    if [[ -n "$upload_tmpl" ]]; then
      printf 'more than one digest upload name\n' >&2
      exit 1
    fi
    upload_tmpl=$item
  else
    downloads+=("$item")
  fi
done
if [[ -z "$upload_tmpl" || ${#downloads[@]} -ne 2 ]]; then
  printf 'expected one upload template and two exact arch downloads\n' >&2
  printf '%s\n' "${digest_names[@]}" >&2
  exit 1
fi
if scheme_overlaps "$upload_tmpl"; then
  printf 'digest artifact names still overlap\n' >&2
  exit 1
fi
for suffix in "${suffixes[@]}"; do
  want=$(render_template "$upload_tmpl" 'PLACE' "$suffix")
  want=${want/PLACE/'${{ inputs.recipe }}'}
  found=false
  for item in "${downloads[@]}"; do
    if [[ "$item" == "$want" ]]; then
      found=true
    fi
  done
  if [[ "$found" != true ]]; then
    printf 'download name for %s is not the upload name\n' "$suffix" >&2
    printf 'want %s\n' "$want" >&2
    exit 1
  fi
done

# ci-build.sh accepts the same recipes the workflow publishes.
mapfile -t build_recipes < <(
  grep -E '^[[:space:]]+agent-cli \|' "$root/openshell/scripts/ci-build.sh" |
    sed -E 's/^[[:space:]]+//; s/\)[[:space:]]*;;[[:space:]]*$//; s/[[:space:]]*\|[[:space:]]*/\n/g' |
    sort
)
if [[ "${build_recipes[*]}" != "${recipes[*]}" ]]; then
  printf 'ci-build.sh recipes (%s) differ from the image workflow (%s)\n' \
    "${build_recipes[*]}" "${recipes[*]}" >&2
  exit 1
fi

if grep -n ':latest' "$merge" | grep -v -E '^[0-9]+:[[:space:]]*#'; then
  printf 'per-image merge must not publish :latest\n' >&2
  exit 1
fi
if ! grep -F -q "needs.plan.outputs.publish == 'release'" "$images_wf"; then
  printf 'release job is not limited to publish=release\n' >&2
  exit 1
fi
for recipe in "${recipes[@]}"; do
  if ! grep -F -q "needs.${recipe}.result == 'success'" "$images_wf"; then
    printf 'release job does not require %s to succeed\n' "$recipe" >&2
    exit 1
  fi
done
callers=$(grep -l 'create-release.sh' "$root"/.github/workflows/*.yml)
if [[ "$callers" != "$images_wf" ]]; then
  printf 'create-release.sh is not only called by the image workflow\n' >&2
  printf '%s\n' "$callers" >&2
  exit 1
fi

release=$root/openshell/scripts/create-release.sh
release_ids=(agent-cli python rust go pi codex codex-pi claude)
for id in "${release_ids[@]}"; do
  if ! grep -F -q "  ${id}" "$release"; then
    printf 'create-release.sh is missing %s\n' "$id" >&2
    exit 1
  fi
  var=DIGEST_${id//-/_}
  if ! grep -F -q "${var}: \${{ needs.${id}.outputs.digest }}" "$images_wf"; then
    printf 'release job does not pass %s\n' "$var" >&2
    exit 1
  fi
done

sha=0123456789abcdef0123456789abcdef01234567
export GIT_TAG=openshell-2026.10.24.01
export IMAGE_VERSION=2026.10.24.01
export GITHUB_SHA=$sha
export OPENSHELL_RELEASE_PRINT=1
i=0
for id in "${release_ids[@]}"; do
  i=$((i + 1))
  var=DIGEST_${id//-/_}
  printf -v "$var" 'sha256:%s%s' "$i" "$(printf 'a%.0s' $(seq 1 63))"
  export "${var?}"
done
out=$(bash "$release")
for id in "${release_ids[@]}"; do
  ref="ghcr.io/iancleary/openshell-${id}"
  var=DIGEST_${id//-/_}
  if ! grep -F -q -- "-t" <<<"$out" \
    || ! grep -F -q "${ref}:${IMAGE_VERSION}" <<<"$out" \
    || ! grep -F -q "${ref}:latest" <<<"$out" \
    || ! grep -F -q "${ref}@${!var}" <<<"$out"; then
    printf 'release tags missing for %s\n%s\n' "$id" "$out" >&2
    exit 1
  fi
done
if ! grep -F -q 'git_tag=openshell-2026.10.24.01' <<<"$out"; then
  printf 'release print did not name the git tag\n%s\n' "$out" >&2
  exit 1
fi
unset DIGEST_codex
if out=$(bash "$release" 2>"$tmp/missing-digest"); then
  printf 'missing codex digest still tagged images\n%s\n' "$out" >&2
  exit 1
fi
if [[ -n "$out" ]]; then
  printf 'missing digest printed tags before refusing\n%s\n' "$out" >&2
  exit 1
fi
if ! grep -F -q 'refusing to tag any image; missing digest for codex' "$tmp/missing-digest"; then
  printf 'missing digest did not name codex\n' >&2
  cat "$tmp/missing-digest" >&2
  exit 1
fi
unset OPENSHELL_RELEASE_PRINT

printf 'digest artifact tests passed\n'
