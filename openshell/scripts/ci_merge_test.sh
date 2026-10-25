#!/usr/bin/env bash
# Tag selection for the manifest list, and digest artifact names.
# Does not call docker. Download patterns are matched the way
# actions/download-artifact does: GitHub expressions first, then
# minimatch with brace expansion left on.
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
    IMAGE="$image" PUBLISH=release IMAGE_VERSION=2026.10.24.01 DIGEST_DIR="$tmp" \
    bash "$merge"
)
expected=$(
  cat <<EOF
-t
${image}:2026.10.24.01
-t
${image}:latest
${image}@sha256:${amd}
${image}@sha256:${arm}
primary=${image}:2026.10.24.01
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

expand_braces() {
  local pat=$1 pre rest body post alt
  local -a alts
  if [[ "$pat" != *'{'* ]]; then
    printf '%s\n' "$pat"
    return
  fi
  pre=${pat%%'{'*}
  rest=${pat#*'{'}
  body=${rest%%'}'*}
  post=${rest#*'}'}
  if [[ "$body" == "$rest" ]]; then
    printf 'unclosed brace in %s\n' "$pat" >&2
    exit 1
  fi
  if [[ "$pre$body" == *'{'* || "$post" == *'{'* ]]; then
    printf 'only one brace group is supported in %s\n' "$pat" >&2
    exit 1
  fi
  local IFS=,
  read -ra alts <<< "$body"
  for alt in "${alts[@]}"; do
    if [[ -z "$alt" || "$alt" == *' '* ]]; then
      printf 'empty brace alternative in %s\n' "$pat" >&2
      exit 1
    fi
    printf '%s\n' "${pre}${alt}${post}"
  done
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
mapfile -t brace_fixture < <(expand_braces 'digests-codex-{amd64,arm64}')
if [[ ${#brace_fixture[@]} -ne 2 \
  || "${brace_fixture[0]}" != digests-codex-amd64 \
  || "${brace_fixture[1]}" != digests-codex-arm64 ]]; then
  printf 'brace fixture did not expand to the two arch names\n' >&2
  exit 1
fi

build_wf=$root/.github/workflows/openshell-build-image.yml
images_wf=$root/.github/workflows/openshell-images.yml
mapfile -t upload_lines < <(grep -E '^[[:space:]]+name:[[:space:]]+"?digests-' "$build_wf")
mapfile -t pattern_lines < <(grep -E '^[[:space:]]+pattern:[[:space:]]+' "$build_wf")
if [[ ${#upload_lines[@]} -ne 1 || ${#pattern_lines[@]} -ne 1 ]]; then
  printf 'expected one digest upload name and one download pattern\n' >&2
  exit 1
fi
upload_tmpl=$(yaml_scalar "${upload_lines[0]}")
pattern_tmpl=$(yaml_scalar "${pattern_lines[0]}")

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

all_names=()
declare -A own_names=()
for recipe in "${recipes[@]}"; do
  own_names["$recipe"]=""
  for suffix in "${suffixes[@]}"; do
    name=$(render_template "$upload_tmpl" "$recipe" "$suffix")
    all_names+=("$name")
    own_names["$recipe"]+="${name}"$'\n'
  done
done

for recipe in "${recipes[@]}"; do
  rendered=$(render_template "$pattern_tmpl" "$recipe" "")
  mapfile -t pats < <(expand_braces "$rendered")
  matches=()
  for name in "${all_names[@]}"; do
    for pat in "${pats[@]}"; do
      if glob_match "$name" "$pat"; then
        matches+=("$name")
        break
      fi
    done
  done
  expected=$(printf '%s' "${own_names[$recipe]}" | sed '/^$/d' | sort)
  got=$(printf '%s\n' "${matches[@]}" | sed '/^$/d' | sort)
  if [[ "$expected" != "$got" ]]; then
    printf 'digest pattern for %s does not match only its own artifacts\n' "$recipe" >&2
    printf 'pattern: %s\n' "$rendered" >&2
    printf 'got:\n%s\nwant:\n%s\n' "$got" "$expected" >&2
    for other in "${recipes[@]}"; do
      if [[ "$other" == "$recipe"-* ]]; then
        printf '%s is a hyphen-prefix of %s\n' "$recipe" "$other" >&2
      fi
    done
    exit 1
  fi
done

printf 'digest artifact tests passed\n'
