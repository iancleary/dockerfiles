#!/usr/bin/env bash
# Rewrite OpenShell version files to the newest allowed upstream release.
#
# Release lines (see openshell/README.md):
#   major  Node stays on the pinned major (24.x.y).
#   minor  Newest patch on the pinned major.minor. This is the default,
#          including CPython 3.13.x, Go 1.27.x, and Rust 1.99.x.
#   zero   uv and Codex track the newest stable 0.x.y. Their routine
#          releases move the minor component. Prereleases are skipped.
#
# Checksums are taken from the upstream checksum file or the GitHub asset
# digest, then checked by downloading the artifact. A mismatch or a missing
# asset fails the run. CPython and pre-commit are installed by uv, which
# verifies those downloads, so only their versions are pinned.
#
# Rust archives use the dateless static.rust-lang.org paths. The channel
# manifest still records a dist date; the images do not.
#
# GitHub Action pins stay on the same major. The cosign-release input is
# not an action pin and is left alone.
#
# --check prints the bumps that would be written and exits 1 when there
# are any. It does not modify the repository. A clean tree exits 0.
# Other failures exit 2.
#
# Requires bash, curl, jq, and GNU sha256sum. Set GITHUB_TOKEN or use
# `gh auth token` so the GitHub API rate limit is not the anonymous cap.
# OPENSHELL_BUMP_CACHE, when set, stores downloads. Cached files are
# hashed again and replaced when they do not match.
set -euo pipefail

changes=()
work=
check=false
summary_file=

die() {
  printf '%s\n' "$*" >&2
  exit 2
}

usage() {
  printf 'usage: bump-versions.sh [--check] [--summary-file PATH]\n' >&2
  exit 2
}

note() {
  changes+=("$1")
  printf '%s\n' "$1" >&2
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

line_prefix() {
  local mode=$1 version=$2 major minor
  IFS=. read -r major minor _ <<<"$version"
  case "$mode" in
    major)
      [[ -n "$major" ]] || return 1
      printf '%s\n' "$major"
      ;;
    minor)
      [[ -n "$minor" ]] || return 1
      printf '%s.%s\n' "$major" "$minor"
      ;;
    zero)
      [[ "$major" == 0 ]] || return 1
      printf '0\n'
      ;;
    *)
      return 1
      ;;
  esac
}

# stdout is the newest candidate on the current release line.
# exit 1 when none exist, exit 2 when that newest is older than current.
newest_matching() {
  local mode=$1 current=$2 cand line want best="" top
  want=$(line_prefix "$mode" "$current") || return 1
  shift 2
  for cand in "$@"; do
    is_semver "$cand" || continue
    line=$(line_prefix "$mode" "$cand") || continue
    [[ "$line" == "$want" ]] || continue
    if [[ -z "$best" ]]; then
      best=$cand
    else
      best=$(printf '%s\n%s\n' "$best" "$cand" | sort -V | tail -n 1)
    fi
  done
  [[ -n "$best" ]] || return 1
  top=$(printf '%s\n%s\n' "$current" "$best" | sort -V | tail -n 1)
  [[ "$top" == "$best" ]] || return 2
  printf '%s\n' "$best"
}

# stdout is the highest vMAJOR.MINOR.PATCH tag. Arguments are tag names
# or refs/tags/... values.
pick_action_tag() {
  local major=$1 tag ver best=""
  shift
  for tag in "$@"; do
    tag=${tag#refs/tags/}
    [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || continue
    [[ "${BASH_REMATCH[1]}" == "$major" ]] || continue
    ver=$tag
    if [[ -z "$best" ]]; then
      best=$ver
    else
      best=$(printf '%s\n%s\n' "$best" "$ver" | sort -V | tail -n 1)
    fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

checksum_for_name() {
  local file=$1 name=$2 hash fname single="" count=0
  while read -r hash fname || [[ -n "${hash:-}" ]]; do
    hash=${hash%$'\r'}
    fname=${fname%$'\r'}
    fname=${fname#\*}
    fname=${fname#./}
    [[ "$hash" =~ ^[a-f0-9]{64}$ ]] || continue
    count=$((count + 1))
    single=$hash
    if [[ -n "$name" && "$fname" == "$name" ]]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done <"$file"
  if [[ -z "$name" && "$count" -eq 1 ]]; then
    printf '%s\n' "$single"
    return 0
  fi
  return 1
}

kv() {
  local file=$1 key=$2 line
  line=$(grep -E "^${key}=" "$file" | head -n 1) || true
  [[ -n "$line" ]] || die "missing ${key} in ${file}"
  printf '%s' "${line#*=}"
}

set_kv() {
  local file=$1 key=$2 value=$3 current tmp
  current=$(kv "$file" "$key")
  [[ "$current" == "$value" ]] && return 0
  tmp=$(mktemp)
  awk -v key="$key" -v value="$value" '
    $0 ~ "^" key "=" { print key "=" value; next }
    { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

github_curl() {
  local url=$1 attempt=1 body
  local -a args=(
    --http1.1
    -fsSL
    --retry 3
    --retry-all-errors
    --retry-delay 2
    --connect-timeout 20
    --max-time 120
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: openshell-bump"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  while ((attempt <= 4)); do
    if body=$(curl "${args[@]}" "$url") && jq -e . >/dev/null <<<"$body"; then
      printf '%s\n' "$body"
      return 0
    fi
    printf 'GitHub request failed (attempt %s)\n' "$attempt" >&2
    attempt=$((attempt + 1))
    sleep $((attempt * 2))
  done
  return 1
}

curl_public() {
  curl --http1.1 -fsSL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 --max-time 600 "$@"
}

# Run a command in this shell and read its stdout into the named array.
# Process substitution would hide a failing list command.
capture_lines() {
  local -n _lines=$1
  shift
  local out status=0
  out=$(mktemp "$work/lines.XXXXXX")
  "$@" >"$out" || status=$?
  if [[ "$status" -ne 0 ]]; then
    rm -f "$out"
    exit "$status"
  fi
  mapfile -t _lines <"$out"
  rm -f "$out"
}

download_to_cache() {
  local url=$1 label=$2 dest
  if [[ -n "${OPENSHELL_BUMP_CACHE:-}" ]]; then
    mkdir -p "$OPENSHELL_BUMP_CACHE"
    dest="${OPENSHELL_BUMP_CACHE}/$(printf '%s' "$url" | sha256sum | awk '{print $1}')"
  else
    dest=$(mktemp "$work/dl.XXXXXX")
  fi
  if [[ -s "$dest" ]]; then
    printf 'cache hit %s\n' "$label" >&2
    printf '%s\n' "$dest"
    return 0
  fi
  printf 'download %s\n' "$label" >&2
  curl_public -o "${dest}.partial" "$url" || die "download failed for ${label}"
  mv "${dest}.partial" "$dest"
  printf '%s\n' "$dest"
}

download_verify() {
  local url=$1 expected=$2 label=$3 dest got
  [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || die "bad sha256 for ${label}"
  dest=$(download_to_cache "$url" "$label")
  if echo "${expected}  ${dest}" | sha256sum -c --status; then
    return 0
  fi
  if [[ -n "${OPENSHELL_BUMP_CACHE:-}" ]]; then
    rm -f "$dest"
    dest=$(download_to_cache "$url" "$label")
    if echo "${expected}  ${dest}" | sha256sum -c --status; then
      return 0
    fi
  fi
  got=$(sha256sum "$dest" | awk '{print $1}')
  die "checksum mismatch for ${label}: expected ${expected} got ${got}"
}

require_array() {
  local json=$1 what=$2
  if ! jq -e 'type == "array"' <<<"$json" >/dev/null; then
    die "unexpected response for ${what}"
  fi
}

# Tags, not the releases API. A releases page embeds every asset, and those
# bodies are large enough to arrive truncated. Prerelease suffixes fail the
# caller's semver regex. The chosen tag is fetched on its own afterwards.
list_release_versions() {
  local repo=$1 tag_re=$2 page=1 json count tag
  while ((page <= 10)); do
    json=$(github_curl "https://api.github.com/repos/${repo}/tags?per_page=100&page=${page}") \
      || die "tag list failed for ${repo}"
    require_array "$json" "${repo} tags"
    while IFS= read -r tag; do
      [[ -z "$tag" ]] && continue
      if [[ "$tag" =~ $tag_re ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      fi
    done < <(jq -r '.[].name' <<<"$json")
    count=$(jq 'length' <<<"$json")
    if ((count < 100)); then
      break
    fi
    page=$((page + 1))
  done
}

list_tag_versions() {
  local repo=$1 prefix=$2 page=1 json count ref
  while ((page <= 5)); do
    json=$(github_curl "https://api.github.com/repos/${repo}/git/matching-refs/${prefix}?per_page=100&page=${page}") \
      || die "tag list failed for ${repo} ${prefix}"
    require_array "$json" "${repo} tags"
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      if [[ "$ref" =~ ^refs/tags/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      fi
    done < <(jq -r '.[].ref' <<<"$json")
    count=$(jq 'length' <<<"$json")
    if ((count < 100)); then
      break
    fi
    page=$((page + 1))
  done
}

choose_version() {
  local name=$1 mode=$2 current=$3
  shift 3
  local chosen status=0
  if [[ $# -eq 0 ]]; then
    die "no upstream versions for ${name}"
  fi
  chosen=$(newest_matching "$mode" "$current" "$@") || status=$?
  if [[ "$status" -eq 2 ]]; then
    die "refusing to downgrade ${name} from ${current}"
  fi
  if [[ "$status" -ne 0 ]]; then
    die "no ${name} release on the release line of ${current}"
  fi
  printf '%s\n' "$chosen"
}

release_json() {
  local repo=$1 tag=$2 safe cache
  safe=${repo//\//_}
  cache="$work/release-${safe}-${tag}.json"
  if [[ ! -s "$cache" ]]; then
    github_curl "https://api.github.com/repos/${repo}/releases/tags/${tag}" >"${cache}.partial" \
      || die "release lookup failed for ${repo} ${tag}"
    mv "${cache}.partial" "$cache"
  fi
  printf '%s\n' "$cache"
}

resolve_archive_sha() {
  local repo=$1 tag=$2 asset=$3 sums_kind=$4 sums_name=$5 label=$6
  local jsonfile digest url published="" sums_asset sums_url sums_file count
  jsonfile=$(release_json "$repo" "$tag")
  count=$(jq --arg name "$asset" '[.assets[] | select(.name == $name)] | length' "$jsonfile")
  [[ "$count" -eq 1 ]] || die "expected one ${asset} on ${repo} ${tag}, found ${count}"
  IFS=$'\t' read -r digest url < <(
    jq -r --arg name "$asset" '
      .assets[] | select(.name == $name) | [(.digest // ""), .browser_download_url] | @tsv
    ' "$jsonfile"
  )
  [[ -n "$url" ]] || die "missing download url for ${asset}"
  digest=${digest#sha256:}
  if [[ -n "$digest" && ! "$digest" =~ ^[a-f0-9]{64}$ ]]; then
    die "bad asset digest for ${asset}"
  fi
  case "$sums_kind" in
    none) sums_asset= ;;
    sidecar) sums_asset="${asset}.sha256" ;;
    shared) sums_asset=$sums_name ;;
    *) die "bad checksum kind ${sums_kind}" ;;
  esac
  if [[ -n "$sums_asset" ]]; then
    count=$(jq --arg name "$sums_asset" '[.assets[] | select(.name == $name)] | length' "$jsonfile")
    [[ "$count" -eq 1 ]] || die "expected one ${sums_asset} on ${repo} ${tag}, found ${count}"
    sums_url=$(jq -r --arg name "$sums_asset" '.assets[] | select(.name == $name) | .browser_download_url' "$jsonfile")
    sums_file=$(download_to_cache "$sums_url" "${label} checksum")
    if [[ "$sums_kind" == sidecar ]]; then
      published=$(checksum_for_name "$sums_file" "$asset" || checksum_for_name "$sums_file" "") \
        || die "could not parse checksum for ${asset}"
    else
      published=$(checksum_for_name "$sums_file" "$asset") \
        || die "checksum file ${sums_asset} has no line for ${asset}"
    fi
    if [[ -n "$digest" && "$digest" != "$published" ]]; then
      die "asset digest and checksum file disagree for ${asset}"
    fi
  elif [[ -n "$digest" ]]; then
    published=$digest
  fi
  if [[ -n "$published" ]]; then
    download_verify "$url" "$published" "$label"
    printf '%s\n' "$published"
    return 0
  fi
  printf 'no published checksum for %s; hashing the download\n' "$label" >&2
  local dest got
  dest=$(download_to_cache "$url" "$label")
  got=$(sha256sum "$dest" | awk '{print $1}')
  [[ "$got" =~ ^[a-f0-9]{64}$ ]] || die "could not hash ${label}"
  printf '%s\n' "$got"
}

record_version() {
  local name=$1 file=$2 ver_key=$3 old_ver=$4 new_ver=$5
  shift 5
  local key old new checksums=false
  set_kv "$file" "$ver_key" "$new_ver"
  while [[ $# -ge 2 ]]; do
    key=$1
    new=$2
    shift 2
    old=$(kv "$file" "$key")
    if [[ "$old" != "$new" ]]; then
      checksums=true
    fi
    set_kv "$file" "$key" "$new"
  done
  if [[ "$old_ver" != "$new_ver" ]]; then
    note "bump ${name} ${old_ver} -> ${new_ver}"
  elif [[ "$checksums" == true ]]; then
    note "bump ${name} ${old_ver} checksums"
  else
    printf '%s %s unchanged\n' "$name" "$old_ver" >&2
  fi
}

bump_github_archives() {
  local name=$1 mode=$2 file=$3 ver_key=$4 repo=$5 tag_prefix=$6 tag_re=$7
  local sums_kind=$8 sums_name=$9
  shift 9
  local current chosen tag asset amd_sha arm_sha
  local -a versions=()
  current=$(kv "$file" "$ver_key")
  capture_lines versions list_release_versions "$repo" "$tag_re"
  chosen=$(choose_version "$name" "$mode" "$current" "${versions[@]}")
  printf 'resolve %s %s\n' "$name" "$chosen" >&2
  tag="${tag_prefix}${chosen}"
  asset=${1//VERSIONTOKEN/$chosen}
  amd_sha=$(resolve_archive_sha "$repo" "$tag" "$asset" "$sums_kind" "$sums_name" "${name} amd64")
  asset=${2//VERSIONTOKEN/$chosen}
  arm_sha=$(resolve_archive_sha "$repo" "$tag" "$asset" "$sums_kind" "$sums_name" "${name} arm64")
  record_version "$name" "$file" "$ver_key" "$current" "$chosen" "$3" "$amd_sha" "$4" "$arm_sha"
}

bump_node() {
  local file=$work/versions/node.env current chosen json sums node_lines
  local -a versions=()
  current=$(kv "$file" NODE_VERSION)
  json=$(curl_public "https://nodejs.org/dist/index.json") || die "node index failed"
  node_lines=$(jq -r '.[].version' <<<"$json" | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p') \
    || die "node index parse failed"
  [[ -n "$node_lines" ]] || die "node index parse failed"
  mapfile -t versions <<<"$node_lines"
  chosen=$(choose_version node major "$current" "${versions[@]}")
  printf 'resolve node %s\n' "$chosen" >&2
  sums=$(download_to_cache "https://nodejs.org/dist/v${chosen}/SHASUMS256.txt" "node ${chosen} SHASUMS256.txt")
  local amd_name="node-v${chosen}-linux-x64.tar.xz"
  local arm_name="node-v${chosen}-linux-arm64.tar.xz"
  local amd_sha arm_sha
  amd_sha=$(checksum_for_name "$sums" "$amd_name") || die "node SHASUMS256.txt has no ${amd_name}"
  arm_sha=$(checksum_for_name "$sums" "$arm_name") || die "node SHASUMS256.txt has no ${arm_name}"
  download_verify "https://nodejs.org/dist/v${chosen}/${amd_name}" "$amd_sha" "node amd64"
  download_verify "https://nodejs.org/dist/v${chosen}/${arm_name}" "$arm_sha" "node arm64"
  record_version node "$file" NODE_VERSION "$current" "$chosen" \
    NODE_SHA256_AMD64 "$amd_sha" NODE_SHA256_ARM64 "$arm_sha"
}

bump_go() {
  local file=$work/versions/go.env current chosen json go_lines
  local -a versions=()
  current=$(kv "$file" GO_VERSION)
  json=$(curl_public "https://go.dev/dl/?mode=json&include=all") || die "go.dev index failed"
  require_array "$json" "go.dev"
  go_lines=$(jq -r '.[].version' <<<"$json" | sed -n 's/^go\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p') \
    || die "go.dev parse failed"
  [[ -n "$go_lines" ]] || die "go.dev parse failed"
  mapfile -t versions <<<"$go_lines"
  chosen=$(choose_version go minor "$current" "${versions[@]}")
  printf 'resolve go %s\n' "$chosen" >&2
  local arch sha filename url
  local amd_sha="" arm_sha=""
  for arch in amd64 arm64; do
    filename="go${chosen}.linux-${arch}.tar.gz"
    sha=$(jq -r --arg ver "go${chosen}" --arg file "$filename" '
      .[] | select(.version == $ver) | .files[] | select(.filename == $file) | .sha256
    ' <<<"$json")
    [[ "$sha" =~ ^[a-f0-9]{64}$ ]] || die "go.dev has no sha256 for ${filename}"
    url="https://go.dev/dl/${filename}"
    download_verify "$url" "$sha" "go ${arch}"
    if [[ "$arch" == amd64 ]]; then
      amd_sha=$sha
    else
      arm_sha=$sha
    fi
  done
  record_version go "$file" GO_VERSION "$current" "$chosen" \
    GO_SHA256_AMD64 "$amd_sha" GO_SHA256_ARM64 "$arm_sha"
}

# kind is semver or sha256. The rustc version line also contains a short
# commit and a date, so a generic token match is wrong there.
toml_value() {
  local file=$1 section=$2 key=$3 kind=$4
  awk -v section="$section" -v key="$key" -v kind="$kind" '
    $0 == "[" section "]" { grab = 1; next }
    grab && /^\[/ { exit }
    grab && $1 == key {
      if (kind == "semver" && match($0, /[0-9]+\.[0-9]+\.[0-9]+/)) {
        print substr($0, RSTART, RLENGTH)
      } else if (kind == "sha256" && match($0, /[0-9a-f]{64}/)) {
        print substr($0, RSTART, RLENGTH)
      }
      exit
    }
  ' "$file"
}

rust_component_sha() {
  local component=$1 triple=$2 label=$3 toml=$4 version=$5
  local section hash url
  section="pkg.${component}.target.${triple}"
  hash=$(toml_value "$toml" "$section" xz_hash sha256)
  [[ "$hash" =~ ^[a-f0-9]{64}$ ]] || die "missing xz_hash for ${section}"
  url="https://static.rust-lang.org/dist/${component}-${version}-${triple}.tar.xz"
  download_verify "$url" "$hash" "$label"
  printf '%s\n' "$hash"
}

bump_rust() {
  local file=$work/versions/rust.env current chosen toml rust_ver
  local rustc_amd rustc_arm cargo_amd cargo_arm std_amd std_arm
  local -a versions=()
  current=$(kv "$file" RUST_VERSION)
  capture_lines versions list_release_versions rust-lang/rust '^([0-9]+\.[0-9]+\.[0-9]+)$'
  chosen=$(choose_version rust minor "$current" "${versions[@]}")
  printf 'resolve rust %s\n' "$chosen" >&2
  toml=$(download_to_cache "https://static.rust-lang.org/dist/channel-rust-${chosen}.toml" "channel-rust-${chosen}.toml")
  rust_ver=$(toml_value "$toml" "pkg.rustc" version semver)
  [[ "$rust_ver" == "$chosen" ]] || die "channel-rust-${chosen}.toml is rustc ${rust_ver:-missing}"
  rustc_amd=$(rust_component_sha rustc x86_64-unknown-linux-gnu "rustc amd64" "$toml" "$chosen")
  rustc_arm=$(rust_component_sha rustc aarch64-unknown-linux-gnu "rustc arm64" "$toml" "$chosen")
  cargo_amd=$(rust_component_sha cargo x86_64-unknown-linux-gnu "cargo amd64" "$toml" "$chosen")
  cargo_arm=$(rust_component_sha cargo aarch64-unknown-linux-gnu "cargo arm64" "$toml" "$chosen")
  std_amd=$(rust_component_sha rust-std x86_64-unknown-linux-gnu "rust-std amd64" "$toml" "$chosen")
  std_arm=$(rust_component_sha rust-std aarch64-unknown-linux-gnu "rust-std arm64" "$toml" "$chosen")
  record_version rust "$file" RUST_VERSION "$current" "$chosen" \
    RUSTC_SHA256_AMD64 "$rustc_amd" RUSTC_SHA256_ARM64 "$rustc_arm" \
    CARGO_SHA256_AMD64 "$cargo_amd" CARGO_SHA256_ARM64 "$cargo_arm" \
    RUST_STD_SHA256_AMD64 "$std_amd" RUST_STD_SHA256_ARM64 "$std_arm"
}

bump_python_versions() {
  local file=$work/versions/python.env current chosen prefix
  local -a versions=()
  current=$(kv "$file" PYTHON_VERSION)
  prefix=$(line_prefix minor "$current") || die "bad python version ${current}"
  capture_lines versions list_tag_versions python/cpython "tags/v${prefix}."
  chosen=$(choose_version python minor "$current" "${versions[@]}")
  printf 'resolve python %s\n' "$chosen" >&2
  record_version python "$file" PYTHON_VERSION "$current" "$chosen"
}

bump_pre_commit() {
  local file=$work/versions/python.env current chosen json pre_lines
  local -a versions=()
  current=$(kv "$file" PRE_COMMIT_VERSION)
  json=$(curl_public "https://pypi.org/pypi/pre-commit/json") || die "pre-commit index failed"
  pre_lines=$(
    jq -r '
      .releases
      | to_entries[]
      | select(any(.value[]; (.yanked // false) | not))
      | .key
    ' <<<"$json"
  ) || die "pre-commit index parse failed"
  [[ -n "$pre_lines" ]] || die "pre-commit index parse failed"
  mapfile -t versions <<<"$pre_lines"
  chosen=$(choose_version pre-commit minor "$current" "${versions[@]}")
  printf 'resolve pre-commit %s\n' "$chosen" >&2
  record_version pre-commit "$file" PRE_COMMIT_VERSION "$current" "$chosen"
}

bump_debian() {
  local file=$work/versions/base.env token headers digest manifest old new arch
  token=$(curl_public "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull" | jq -r '.token // empty') \
    || die "debian registry token failed"
  [[ -n "$token" ]] || die "debian registry token was empty"
  headers=$(curl_public -I \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://registry-1.docker.io/v2/library/debian/manifests/bookworm-slim") \
    || die "debian manifest headers failed"
  digest=$(printf '%s\n' "$headers" | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2; exit }')
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || die "debian bookworm-slim digest missing"
  manifest=$(curl_public \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://registry-1.docker.io/v2/library/debian/manifests/bookworm-slim") \
    || die "debian manifest failed"
  for arch in amd64 arm64; do
    jq -e --arg arch "$arch" '
      [.manifests[]? | select(.platform.os == "linux" and .platform.architecture == $arch)] | length > 0
    ' <<<"$manifest" >/dev/null || die "debian bookworm-slim index has no linux/${arch}"
  done
  new="debian:bookworm-slim@${digest}"
  old=$(kv "$file" DEBIAN_IMAGE)
  set_kv "$file" DEBIAN_IMAGE "$new"
  if [[ "$old" != "$new" ]]; then
    note "bump debian:bookworm-slim digest"
  else
    printf 'debian bookworm-slim unchanged\n' >&2
  fi
}

list_action_tags() {
  local repo=$1 major=$2 page=1 json count
  while ((page <= 5)); do
    json=$(github_curl "https://api.github.com/repos/${repo}/git/matching-refs/tags/v${major}.?per_page=100&page=${page}") \
      || die "action tag list failed for ${repo}"
    require_array "$json" "${repo} tags"
    jq -r '.[].ref' <<<"$json"
    count=$(jq 'length' <<<"$json")
    if ((count < 100)); then
      break
    fi
    page=$((page + 1))
  done
}

replace_pin() {
  local file=$1 repo=$2 oldsha=$3 newsha=$4 oldver=$5 newver=$6
  local tmp line
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"uses: ${repo}@${oldsha}"* && "$line" == *"# ${oldver}"* ]]; then
      line=${line//${oldsha}/${newsha}}
      line=${line//"# ${oldver}"/"# ${newver}"}
    fi
    printf '%s\n' "$line"
  done <"$file" >"$tmp"
  mv "$tmp" "$file"
}

bump_actions() {
  local file line trimmed repo sha major ver best newsha before after changed_file sorted
  local -a repos=() tags=()
  declare -A pin_sha=() pin_ver=() pin_major=()
  for file in "$work/workflows/"*.yml; do
    [[ -f "$file" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      trimmed=${line#"${line%%[![:space:]]*}"}
      [[ "$trimmed" == \#* ]] && continue
      if [[ "$line" =~ uses:[[:space:]]*([^[:space:]@]+)@([0-9a-f]{40})[[:space:]]+#[[:space:]]*v([0-9]+)\.([0-9]+)\.([0-9]+)[[:space:]]*$ ]]; then
        repo=${BASH_REMATCH[1]}
        sha=${BASH_REMATCH[2]}
        major=${BASH_REMATCH[3]}
        ver="v${BASH_REMATCH[3]}.${BASH_REMATCH[4]}.${BASH_REMATCH[5]}"
        if [[ -n "${pin_sha[$repo]:-}" && "${pin_sha[$repo]}" != "$sha" ]]; then
          die "conflicting pins for ${repo}"
        fi
        if [[ -n "${pin_major[$repo]:-}" && "${pin_major[$repo]}" != "$major" ]]; then
          die "conflicting majors for ${repo}"
        fi
        pin_sha[$repo]=$sha
        pin_ver[$repo]=$ver
        pin_major[$repo]=$major
      elif [[ "$line" =~ uses:[[:space:]]*\./ ]]; then
        :
      elif [[ "$line" =~ uses: ]]; then
        die "action pin must be a 40-character SHA and a vX.Y.Z comment: ${line}"
      fi
    done <"$file"
  done
  if [[ ${#pin_sha[@]} -eq 0 ]]; then
    die "no pinned actions found"
  fi
  sorted=$(printf '%s\n' "${!pin_sha[@]}" | sort) || die "could not list pinned actions"
  mapfile -t repos <<<"$sorted"
  for repo in "${repos[@]}"; do
    capture_lines tags list_action_tags "$repo" "${pin_major[$repo]}"
    best=$(pick_action_tag "${pin_major[$repo]}" "${tags[@]}") || die "no v${pin_major[$repo]} tag for ${repo}"
    if [[ "$(printf '%s\n%s\n' "${pin_ver[$repo]}" "$best" | sort -V | tail -n 1)" != "$best" ]]; then
      die "refusing to downgrade ${repo} from ${pin_ver[$repo]} to ${best}"
    fi
    if [[ "$best" == "${pin_ver[$repo]}" ]]; then
      printf '%s %s unchanged\n' "$repo" "$best" >&2
      continue
    fi
    newsha=$(github_curl "https://api.github.com/repos/${repo}/commits/${best}" | jq -r '.sha // empty') \
      || die "could not resolve ${repo} ${best}"
    [[ "$newsha" =~ ^[0-9a-f]{40}$ ]] || die "bad commit for ${repo} ${best}"
    if [[ "$newsha" == "${pin_sha[$repo]}" ]]; then
      printf '%s %s already at %s\n' "$repo" "$best" "$newsha" >&2
      continue
    fi
    changed_file=false
    for file in "$work/workflows/"*.yml; do
      before=$(sha256sum "$file")
      replace_pin "$file" "$repo" "${pin_sha[$repo]}" "$newsha" "${pin_ver[$repo]}" "$best"
      after=$(sha256sum "$file")
      [[ "$before" == "$after" ]] || changed_file=true
    done
    [[ "$changed_file" == true ]] || die "could not rewrite ${repo}"
    note "bump ${repo} ${pin_ver[$repo]} -> ${best}"
  done
}

files_differ() {
  ! diff -rq "$1" "$2" >/dev/null
}

main() {
  local root
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        check=true
        shift
        ;;
      --summary-file)
        [[ $# -ge 2 ]] || usage
        summary_file=$2
        shift 2
        ;;
      -h | --help)
        usage
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        usage
        ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
  if [[ -z "${GITHUB_TOKEN:-}" && -n "${GH_TOKEN:-}" ]]; then
    GITHUB_TOKEN=$GH_TOKEN
  fi
  if [[ -z "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
    GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
  fi
  export GITHUB_TOKEN
  root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/versions" "$work/workflows"
  cp -a "$root/openshell/versions/." "$work/versions/"
  cp -a "$root/.github/workflows/." "$work/workflows/"

  bump_github_archives fd minor "$work/versions/tools.env" FD_VERSION \
    sharkdp/fd v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "fd-vVERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "fd-vVERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz" \
    FD_SHA256_AMD64 FD_SHA256_ARM64
  bump_github_archives rg minor "$work/versions/tools.env" RG_VERSION \
    BurntSushi/ripgrep "" '^([0-9]+\.[0-9]+\.[0-9]+)$' sidecar "" \
    "ripgrep-VERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "ripgrep-VERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz" \
    RG_SHA256_AMD64 RG_SHA256_ARM64
  bump_github_archives just minor "$work/versions/tools.env" JUST_VERSION \
    casey/just "" '^([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "just-VERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "just-VERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz" \
    JUST_SHA256_AMD64 JUST_SHA256_ARM64
  bump_github_archives uv zero "$work/versions/python.env" UV_VERSION \
    astral-sh/uv "" '^([0-9]+\.[0-9]+\.[0-9]+)$' sidecar "" \
    "uv-x86_64-unknown-linux-musl.tar.gz" \
    "uv-aarch64-unknown-linux-musl.tar.gz" \
    UV_SHA256_AMD64 UV_SHA256_ARM64
  bump_python_versions
  bump_pre_commit
  bump_rust
  bump_go
  bump_node
  bump_github_archives pi minor "$work/versions/pi.env" PI_VERSION \
    earendil-works/pi v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared SHA256SUMS \
    "pi-linux-x64.tar.gz" \
    "pi-linux-arm64.tar.gz" \
    PI_SHA256_AMD64 PI_SHA256_ARM64
  bump_github_archives codex zero "$work/versions/codex.env" CODEX_VERSION \
    openai/codex rust-v '^rust-v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "codex-x86_64-unknown-linux-musl.tar.gz" \
    "codex-aarch64-unknown-linux-musl.tar.gz" \
    CODEX_SHA256_AMD64 CODEX_SHA256_ARM64
  bump_github_archives claude minor "$work/versions/claude.env" CLAUDE_VERSION \
    anthropics/claude-code v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared SHASUMS256.txt \
    "claude-linux-x64.tar.gz" \
    "claude-linux-arm64.tar.gz" \
    CLAUDE_SHA256_AMD64 CLAUDE_SHA256_ARM64
  bump_debian
  bump_actions

  local differ=false
  if files_differ "$root/openshell/versions" "$work/versions" \
    || files_differ "$root/.github/workflows" "$work/workflows"; then
    differ=true
  fi
  if [[ "$differ" == true && ${#changes[@]} -eq 0 ]]; then
    die "files would change but the summary is empty"
  fi
  if [[ "$differ" == false && ${#changes[@]} -gt 0 ]]; then
    die "summary lists bumps but the files match"
  fi
  if [[ -n "$summary_file" ]]; then
    mkdir -p "$(dirname "$summary_file")"
    if [[ ${#changes[@]} -gt 0 ]]; then
      printf '%s\n' "${changes[@]}" >"$summary_file"
    else
      : >"$summary_file"
    fi
  fi
  if [[ "$check" == false && "$differ" == true ]]; then
    cp -a "$work/versions/." "$root/openshell/versions/"
    cp -a "$work/workflows/." "$root/.github/workflows/"
  fi
  if [[ ${#changes[@]} -gt 0 ]]; then
    printf '%s\n' "${changes[@]}"
  fi
  if [[ "$check" == true && "$differ" == true ]]; then
    exit 1
  fi
  if [[ "$differ" == false ]]; then
    printf 'versions are current\n' >&2
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
