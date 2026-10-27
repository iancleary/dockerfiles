#!/usr/bin/env bash
# Rewrite dev-images version files to the newest stable upstream release.
#
# Policy is latest_stable: the newest stable release across minor and major
# versions. Prerelease tags are skipped. A downgrade is refused.
# Go, Rust, Python, Zig, Bun, and pnpm use latest_stable. Node uses the newest
# LTS line from the Node.js index. That line is also a stable release.
#
# Archive URLs and sha256 values are recorded from the release. Two published
# checksums that disagree fail the run. GitHub artifact attestations are
# verified when the release has one. A failed attestation refuses the pin.
#
# --check prints the updates that would be written and exits 1 when there
# are any. It does not modify the repository. A clean tree exits 0.
# Other failures exit 2.
#
# The bookworm-slim digest is written to dev-images/versions/debian.env and
# openshell/versions/base.env in the same run. The OpenShell Monday update
# does not write that digest.
#
# Checksum download and attestation helpers come from
# openshell/scripts/bump-versions.sh.
set -euo pipefail

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -P -- "$script_directory/../.." && pwd -P)
# shellcheck disable=SC1091
source "$repository_root/openshell/scripts/bump-versions.sh"

check=false
changes=()
summary_file=

update_usage() {
  printf 'usage: update_pinned_versions.sh [--check] [--summary-file PATH]\n' >&2
  exit 2
}

choose_latest_stable_version() {
  local tool_name=$1 current_version=$2
  shift 2
  local candidate best="" highest
  is_semver "$current_version" || die "recorded version is not a stable release: ${tool_name} ${current_version}"
  if [[ $# -eq 0 ]]; then
    die "no upstream versions for ${tool_name}"
  fi
  for candidate in "$@"; do
    is_semver "$candidate" || continue
    if [[ -z "$best" ]]; then
      best=$candidate
    else
      best=$(printf '%s\n%s\n' "$best" "$candidate" | sort -V | tail -n 1)
    fi
  done
  [[ -n "$best" ]] || die "no stable version for ${tool_name}"
  highest=$(printf '%s\n%s\n' "$current_version" "$best" | sort -V | tail -n 1)
  if [[ "$highest" != "$best" ]]; then
    die "refusing to downgrade ${tool_name} from ${current_version}"
  fi
  printf '%s\n' "$best"
}

release_asset_url() {
  local repository=$1 tag=$2 asset_name=$3 jsonfile archive_url
  jsonfile=$(release_json "$repository" "$tag")
  archive_url=$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' "$jsonfile")
  [[ "$archive_url" == https://* ]] || die "missing download url for ${asset_name}"
  printf '%s\n' "$archive_url"
}

record_tool() {
  local tool_name=$1 version_file=$2 key_prefix=$3 old_version=$4 new_version=$5
  local archive_url_amd64=$6 archive_url_arm64=$7 sha256_amd64=$8 sha256_arm64=$9 checksum_source=${10}
  local archive_changed=false field_key field_value
  set_kv "$version_file" "${key_prefix}_VERSION" "$new_version"
  local -a pairs=(
    "${key_prefix}_ARCHIVE_URL_AMD64|${archive_url_amd64}"
    "${key_prefix}_ARCHIVE_URL_ARM64|${archive_url_arm64}"
    "${key_prefix}_SHA256_AMD64|${sha256_amd64}"
    "${key_prefix}_SHA256_ARM64|${sha256_arm64}"
    "${key_prefix}_CHECKSUM_SOURCE|${checksum_source}"
  )
  for pair in "${pairs[@]}"; do
    field_key=${pair%%|*}
    field_value=${pair#*|}
    if [[ "$(kv "$version_file" "$field_key")" != "$field_value" ]]; then
      archive_changed=true
    fi
    set_kv "$version_file" "$field_key" "$field_value"
  done
  if [[ "$old_version" != "$new_version" ]]; then
    note "update ${tool_name} ${old_version} -> ${new_version}"
  elif [[ "$archive_changed" == true ]]; then
    note "update ${tool_name} ${old_version} recorded archive"
  else
    printf '%s %s unchanged\n' "$tool_name" "$old_version" >&2
  fi
}

update_github_release_tool() {
  local tool_name=$1 version_file=$2 key_prefix=$3 repository=$4 tag_prefix=$5 tag_expression=$6
  local checksum_kind=$7 checksum_name_template=$8 amd64_asset_template=$9 arm64_asset_template=${10}
  local current_version chosen_version release_tag checksum_name checksum_source
  local amd64_asset arm64_asset amd64_url arm64_url amd64_sha arm64_sha
  local -a versions=()
  current_version=$(kv "$version_file" "${key_prefix}_VERSION")
  capture_lines versions list_release_versions "$repository" "$tag_expression"
  chosen_version=$(choose_latest_stable_version "$tool_name" "$current_version" "${versions[@]}")
  printf 'resolve %s %s\n' "$tool_name" "$chosen_version" >&2
  release_tag="${tag_prefix}${chosen_version}"
  amd64_asset=${amd64_asset_template//VERSIONTOKEN/$chosen_version}
  arm64_asset=${arm64_asset_template//VERSIONTOKEN/$chosen_version}
  checksum_name=${checksum_name_template//VERSIONTOKEN/$chosen_version}
  case "$checksum_kind" in
    none)
      checksum_source=github_release_asset_digest
      ;;
    sidecar)
      checksum_source=upstream_sidecar
      ;;
    shared)
      checksum_source="upstream_shared_file:${checksum_name}"
      ;;
    *)
      die "bad checksum kind ${checksum_kind}"
      ;;
  esac
  amd64_sha=$(resolve_archive_sha "$repository" "$release_tag" "$amd64_asset" "$checksum_kind" "$checksum_name" "${tool_name} amd64")
  arm64_sha=$(resolve_archive_sha "$repository" "$release_tag" "$arm64_asset" "$checksum_kind" "$checksum_name" "${tool_name} arm64")
  amd64_url=$(release_asset_url "$repository" "$release_tag" "$amd64_asset")
  arm64_url=$(release_asset_url "$repository" "$release_tag" "$arm64_asset")
  record_tool "$tool_name" "$version_file" "$key_prefix" "$current_version" "$chosen_version" \
    "$amd64_url" "$arm64_url" "$amd64_sha" "$arm64_sha" "$checksum_source"
}

assign_recorded_value() {
  local version_file=$1 key=$2 value=$3
  if [[ "$(kv "$version_file" "$key")" != "$value" ]]; then
    recorded_value_changed=true
  fi
  set_kv "$version_file" "$key" "$value"
}

channel_manifest_field() {
  local file=$1 section=$2 key=$3
  awk -v section="$section" -v key="$key" '
    $0 == "[" section "]" { grab = 1; next }
    grab && /^\[/ { exit }
    grab && $1 == key {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
      } else if (match($0, /[0-9a-f]{64}/)) {
        print substr($0, RSTART, RLENGTH)
      }
      exit
    }
  ' "$file"
}

update_go_toolchain() {
  local version_file=$work/versions/go.env current_version chosen_version json
  local amd64_sha arm64_sha amd64_url arm64_url filename
  local -a versions=()
  current_version=$(kv "$version_file" GO_VERSION)
  json=$(curl_public "https://go.dev/dl/?mode=json&include=all") || die "go.dev index failed"
  require_array "$json" "go.dev"
  mapfile -t versions < <(jq -r '.[] | select(.stable == true) | .version' <<<"$json" | sed -n 's/^go\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p')
  chosen_version=$(choose_latest_stable_version go "$current_version" "${versions[@]}")
  printf 'resolve go %s\n' "$chosen_version" >&2
  filename="go${chosen_version}.linux-amd64.tar.gz"
  amd64_sha=$(jq -r --arg version "go${chosen_version}" --arg filename "$filename" '
    .[] | select(.version == $version) | .files[] | select(.filename == $filename) | .sha256
  ' <<<"$json")
  filename="go${chosen_version}.linux-arm64.tar.gz"
  arm64_sha=$(jq -r --arg version "go${chosen_version}" --arg filename "$filename" '
    .[] | select(.version == $version) | .files[] | select(.filename == $filename) | .sha256
  ' <<<"$json")
  [[ "$amd64_sha" =~ ^[a-f0-9]{64}$ && "$arm64_sha" =~ ^[a-f0-9]{64}$ ]] || die "go.dev sha256 missing"
  amd64_url="https://go.dev/dl/go${chosen_version}.linux-amd64.tar.gz"
  arm64_url="https://go.dev/dl/go${chosen_version}.linux-arm64.tar.gz"
  download_verify "$amd64_url" "$amd64_sha" "go amd64"
  download_verify "$arm64_url" "$arm64_sha" "go arm64"
  record_tool go "$version_file" GO "$current_version" "$chosen_version" \
    "$amd64_url" "$arm64_url" "$amd64_sha" "$arm64_sha" go_dev_download_index
}

update_node_toolchain() {
  local version_file=$work/versions/node.env current_version chosen_version json sums_path
  local amd64_sha arm64_sha amd64_name arm64_name amd64_url arm64_url
  local -a versions=()
  current_version=$(kv "$version_file" NODE_VERSION)
  json=$(curl_public "https://nodejs.org/dist/index.json") || die "nodejs index failed"
  require_array "$json" "nodejs"
  mapfile -t versions < <(jq -r '.[] | select(.lts != false) | .version' <<<"$json" | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p')
  chosen_version=$(choose_latest_stable_version node "$current_version" "${versions[@]}")
  printf 'resolve node %s\n' "$chosen_version" >&2
  sums_path=$(download_to_cache "https://nodejs.org/dist/v${chosen_version}/SHASUMS256.txt" "node ${chosen_version} SHASUMS256.txt")
  amd64_name="node-v${chosen_version}-linux-x64.tar.xz"
  arm64_name="node-v${chosen_version}-linux-arm64.tar.xz"
  amd64_sha=$(awk -v name="$amd64_name" '$2 == name { print $1; exit }' "$sums_path")
  arm64_sha=$(awk -v name="$arm64_name" '$2 == name { print $1; exit }' "$sums_path")
  [[ "$amd64_sha" =~ ^[a-f0-9]{64}$ && "$arm64_sha" =~ ^[a-f0-9]{64}$ ]] || die "node SHASUMS256 missing"
  amd64_url="https://nodejs.org/dist/v${chosen_version}/${amd64_name}"
  arm64_url="https://nodejs.org/dist/v${chosen_version}/${arm64_name}"
  download_verify "$amd64_url" "$amd64_sha" "node amd64"
  download_verify "$arm64_url" "$arm64_sha" "node arm64"
  record_tool node "$version_file" NODE "$current_version" "$chosen_version" \
    "$amd64_url" "$arm64_url" "$amd64_sha" "$arm64_sha" "upstream_shared_file:SHASUMS256.txt"
}

update_python_toolchain() {
  local version_file=$work/versions/python.env current_version chosen_version standalone_tag
  local amd64_asset arm64_asset amd64_sha arm64_sha amd64_url arm64_url
  local -a versions=()
  current_version=$(kv "$version_file" PYTHON_VERSION)
  capture_lines versions list_release_versions python/cpython '^v([0-9]+\.[0-9]+\.[0-9]+)$'
  chosen_version=$(choose_latest_stable_version python "$current_version" "${versions[@]}")
  printf 'resolve python %s\n' "$chosen_version" >&2
  standalone_tag=$(python_standalone_tag "$chosen_version")
  [[ "$standalone_tag" =~ ^[0-9]{8}$ ]] || die "bad python-build-standalone tag ${standalone_tag}"
  amd64_asset="cpython-${chosen_version}+${standalone_tag}-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
  arm64_asset="cpython-${chosen_version}+${standalone_tag}-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz"
  amd64_sha=$(resolve_archive_sha astral-sh/python-build-standalone "$standalone_tag" "$amd64_asset" shared SHA256SUMS "python amd64")
  arm64_sha=$(resolve_archive_sha astral-sh/python-build-standalone "$standalone_tag" "$arm64_asset" shared SHA256SUMS "python arm64")
  amd64_url=$(release_asset_url astral-sh/python-build-standalone "$standalone_tag" "$amd64_asset")
  arm64_url=$(release_asset_url astral-sh/python-build-standalone "$standalone_tag" "$arm64_asset")
  recorded_value_changed=false
  assign_recorded_value "$version_file" PYTHON_STANDALONE_TAG "$standalone_tag"
  record_tool python "$version_file" PYTHON "$current_version" "$chosen_version" \
    "$amd64_url" "$arm64_url" "$amd64_sha" "$arm64_sha" "upstream_shared_file:SHA256SUMS"
  if [[ "$recorded_value_changed" == true && "$current_version" == "$chosen_version" ]]; then
    note "update python ${chosen_version} standalone tag"
  fi
}

update_rust_toolchain() {
  local version_file=$work/versions/rust.env current_version chosen_version toml_path checksum_source
  local -a versions=()
  current_version=$(kv "$version_file" RUST_VERSION)
  capture_lines versions list_release_versions rust-lang/rust '^([0-9]+\.[0-9]+\.[0-9]+)$'
  chosen_version=$(choose_latest_stable_version rust "$current_version" "${versions[@]}")
  printf 'resolve rust %s\n' "$chosen_version" >&2
  toml_path=$(download_to_cache "https://static.rust-lang.org/dist/channel-rust-${chosen_version}.toml" "channel-rust-${chosen_version}.toml")
  verify_rust_channel "$chosen_version" "$toml_path"
  checksum_source="upstream_shared_file:channel-rust-${chosen_version}.toml"
  recorded_value_changed=false
  assign_recorded_value "$version_file" RUST_VERSION "$chosen_version"
  assign_recorded_value "$version_file" RUST_CHECKSUM_SOURCE "$checksum_source"
  record_rust_component "$version_file" "$toml_path" RUSTC rustc
  record_rust_component "$version_file" "$toml_path" CARGO cargo
  record_rust_component "$version_file" "$toml_path" RUST_STD rust-std
  record_rust_component "$version_file" "$toml_path" RUSTFMT rustfmt-preview
  record_rust_component "$version_file" "$toml_path" CLIPPY clippy-preview
  if [[ "$current_version" != "$chosen_version" ]]; then
    note "update rust ${current_version} -> ${chosen_version}"
  elif [[ "$recorded_value_changed" == true ]]; then
    note "update rust ${chosen_version} recorded archive"
  else
    printf 'rust %s unchanged\n' "$chosen_version" >&2
  fi
}

record_rust_component() {
  local version_file=$1 toml_path=$2 key_prefix=$3 component=$4
  local triple field amd64_url arm64_url amd64_sha arm64_sha
  triple=x86_64-unknown-linux-gnu
  field="pkg.${component}.target.${triple}"
  amd64_url=$(channel_manifest_field "$toml_path" "$field" xz_url)
  amd64_sha=$(channel_manifest_field "$toml_path" "$field" xz_hash)
  triple=aarch64-unknown-linux-gnu
  field="pkg.${component}.target.${triple}"
  arm64_url=$(channel_manifest_field "$toml_path" "$field" xz_url)
  arm64_sha=$(channel_manifest_field "$toml_path" "$field" xz_hash)
  [[ "$amd64_url" == https://* && "$arm64_url" == https://* ]] || die "rust ${component} url missing"
  [[ "$amd64_sha" =~ ^[a-f0-9]{64}$ && "$arm64_sha" =~ ^[a-f0-9]{64}$ ]] || die "rust ${component} sha256 missing"
  download_verify "$amd64_url" "$amd64_sha" "rust ${component} amd64"
  download_verify "$arm64_url" "$arm64_sha" "rust ${component} arm64"
  assign_recorded_value "$version_file" "${key_prefix}_ARCHIVE_URL_AMD64" "$amd64_url"
  assign_recorded_value "$version_file" "${key_prefix}_ARCHIVE_URL_ARM64" "$arm64_url"
  assign_recorded_value "$version_file" "${key_prefix}_SHA256_AMD64" "$amd64_sha"
  assign_recorded_value "$version_file" "${key_prefix}_SHA256_ARM64" "$arm64_sha"
}

update_zig_toolchain() {
  local version_file=$work/versions/zig.env current_version chosen_version json public_key
  local amd64_url arm64_url amd64_sha arm64_sha amd64_signature arm64_signature
  local amd64_path arm64_path amd64_signature_path arm64_signature_path
  local -a versions=()
  current_version=$(kv "$version_file" ZIG_VERSION)
  public_key=$(kv "$version_file" ZIG_MINISIGN_PUBLIC_KEY)
  command -v minisign >/dev/null 2>&1 || die "minisign is required to verify Zig"
  json=$(curl_public "https://ziglang.org/download/index.json") || die "zig index failed"
  mapfile -t versions < <(jq -r 'keys[]' <<<"$json" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)
  chosen_version=$(choose_latest_stable_version zig "$current_version" "${versions[@]}")
  printf 'resolve zig %s\n' "$chosen_version" >&2
  amd64_url=$(jq -r --arg version "$chosen_version" '.[$version]["x86_64-linux"].tarball' <<<"$json")
  arm64_url=$(jq -r --arg version "$chosen_version" '.[$version]["aarch64-linux"].tarball' <<<"$json")
  amd64_sha=$(jq -r --arg version "$chosen_version" '.[$version]["x86_64-linux"].shasum' <<<"$json")
  arm64_sha=$(jq -r --arg version "$chosen_version" '.[$version]["aarch64-linux"].shasum' <<<"$json")
  [[ "$amd64_url" == https://* && "$arm64_url" == https://* ]] || die "zig tarball url missing"
  [[ "$amd64_sha" =~ ^[a-f0-9]{64}$ && "$arm64_sha" =~ ^[a-f0-9]{64}$ ]] || die "zig shasum missing"
  amd64_signature="${amd64_url}.minisig"
  arm64_signature="${arm64_url}.minisig"
  amd64_path=$(download_to_cache "$amd64_url" "zig amd64")
  arm64_path=$(download_to_cache "$arm64_url" "zig arm64")
  verify_sha256_file "$amd64_path" "$amd64_sha" "zig amd64"
  verify_sha256_file "$arm64_path" "$arm64_sha" "zig arm64"
  amd64_signature_path=$(download_to_cache "$amd64_signature" "zig amd64 signature")
  arm64_signature_path=$(download_to_cache "$arm64_signature" "zig arm64 signature")
  minisign -V -P "$public_key" -m "$amd64_path" -x "$amd64_signature_path" >/dev/null \
    || die "zig amd64 minisign verification failed"
  minisign -V -P "$public_key" -m "$arm64_path" -x "$arm64_signature_path" >/dev/null \
    || die "zig arm64 minisign verification failed"
  recorded_value_changed=false
  assign_recorded_value "$version_file" ZIG_SIGNATURE_URL_AMD64 "$amd64_signature"
  assign_recorded_value "$version_file" ZIG_SIGNATURE_URL_ARM64 "$arm64_signature"
  record_tool zig "$version_file" ZIG "$current_version" "$chosen_version" \
    "$amd64_url" "$arm64_url" "$amd64_sha" "$arm64_sha" ziglang_download_index
  if [[ "$recorded_value_changed" == true && "$current_version" == "$chosen_version" ]]; then
    note "update zig ${chosen_version} signature"
  fi
}

update_debian_image_digest() {
  local development_version_file=$work/versions/debian.env
  local openshell_version_file=$work/openshell-base.env
  local token headers digest manifest new_image development_old openshell_old architecture
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
  for architecture in amd64 arm64; do
    jq -e --arg architecture "$architecture" '
      [.manifests[]? | select(.platform.os == "linux" and .platform.architecture == $architecture)] | length > 0
    ' <<<"$manifest" >/dev/null || die "debian bookworm-slim index has no linux/${architecture}"
  done
  new_image="debian:bookworm-slim@${digest}"
  development_old=$(kv "$development_version_file" DEBIAN_IMAGE)
  openshell_old=$(kv "$openshell_version_file" DEBIAN_IMAGE)
  set_kv "$development_version_file" DEBIAN_IMAGE "$new_image"
  set_kv "$development_version_file" DEBIAN_CHECKSUM_SOURCE docker_hub_manifest_list_digest
  set_kv "$openshell_version_file" DEBIAN_IMAGE "$new_image"
  if [[ "$development_old" != "$new_image" || "$openshell_old" != "$new_image" ]]; then
    note "update debian:bookworm-slim digest"
  else
    printf 'debian bookworm-slim unchanged\n' >&2
  fi
}

update_pinned_versions() {
  local version_directory=$work/versions
  update_github_release_tool jq "$version_directory/jq.env" JQ \
    jqlang/jq jq- '^jq-([0-9]+\.[0-9]+\.[0-9]+)$' shared sha256sum.txt \
    jq-linux-amd64 jq-linux-arm64
  update_github_release_tool ripgrep "$version_directory/ripgrep.env" RIPGREP \
    BurntSushi/ripgrep "" '^([0-9]+\.[0-9]+\.[0-9]+)$' sidecar "" \
    "ripgrep-VERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "ripgrep-VERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz"
  update_github_release_tool fd "$version_directory/fd.env" FD \
    sharkdp/fd v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "fd-vVERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "fd-vVERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz"
  update_github_release_tool shellcheck "$version_directory/shellcheck.env" SHELLCHECK \
    koalaman/shellcheck v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "shellcheck-vVERSIONTOKEN.linux.x86_64.tar.xz" \
    "shellcheck-vVERSIONTOKEN.linux.aarch64.tar.xz"
  update_github_release_tool just "$version_directory/just.env" JUST \
    casey/just "" '^([0-9]+\.[0-9]+\.[0-9]+)$' shared SHA256SUMS \
    "just-VERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "just-VERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz"
  update_github_release_tool gh "$version_directory/gh.env" GH \
    cli/cli v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared "gh_VERSIONTOKEN_checksums.txt" \
    "gh_VERSIONTOKEN_linux_amd64.tar.gz" \
    "gh_VERSIONTOKEN_linux_arm64.tar.gz"
  update_github_release_tool uv "$version_directory/uv.env" UV \
    astral-sh/uv "" '^([0-9]+\.[0-9]+\.[0-9]+)$' shared sha256.sum \
    uv-x86_64-unknown-linux-musl.tar.gz \
    uv-aarch64-unknown-linux-musl.tar.gz
  update_github_release_tool bat "$version_directory/bat.env" BAT \
    sharkdp/bat v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "bat-vVERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "bat-vVERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz"
  update_github_release_tool eza "$version_directory/eza.env" EZA \
    eza-community/eza v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    eza_x86_64-unknown-linux-gnu.tar.gz \
    eza_aarch64-unknown-linux-gnu.tar.gz
  update_github_release_tool zoxide "$version_directory/zoxide.env" ZOXIDE \
    ajeetdsouza/zoxide v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "zoxide-VERSIONTOKEN-x86_64-unknown-linux-musl.tar.gz" \
    "zoxide-VERSIONTOKEN-aarch64-unknown-linux-musl.tar.gz"
  update_github_release_tool fzf "$version_directory/fzf.env" FZF \
    junegunn/fzf v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared "fzf_VERSIONTOKEN_checksums.txt" \
    "fzf-VERSIONTOKEN-linux_amd64.tar.gz" \
    "fzf-VERSIONTOKEN-linux_arm64.tar.gz"
  update_github_release_tool delta "$version_directory/delta.env" DELTA \
    dandavison/delta "" '^([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    "delta-VERSIONTOKEN-x86_64-unknown-linux-gnu.tar.gz" \
    "delta-VERSIONTOKEN-aarch64-unknown-linux-gnu.tar.gz"
  update_github_release_tool lazygit "$version_directory/lazygit.env" LAZYGIT \
    jesseduffield/lazygit v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared checksums.txt \
    "lazygit_VERSIONTOKEN_linux_x86_64.tar.gz" \
    "lazygit_VERSIONTOKEN_linux_arm64.tar.gz"
  update_github_release_tool gum "$version_directory/gum.env" GUM \
    charmbracelet/gum v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared checksums.txt \
    "gum_VERSIONTOKEN_Linux_x86_64.tar.gz" \
    "gum_VERSIONTOKEN_Linux_arm64.tar.gz"
  update_github_release_tool ast-grep "$version_directory/ast-grep.env" AST_GREP \
    ast-grep/ast-grep "" '^([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    app-x86_64-unknown-linux-gnu.zip \
    app-aarch64-unknown-linux-gnu.zip
  update_github_release_tool ahi "$version_directory/ahi.env" AHI \
    iancleary/ahi v '^v([0-9]+\.[0-9]+\.[0-9]+)$' shared "ahi-VERSIONTOKEN-sha256sums.txt" \
    "ahi-VERSIONTOKEN-linux-x86_64.tar.gz" \
    "ahi-VERSIONTOKEN-linux-aarch64.tar.gz"
  update_github_release_tool pnpm "$version_directory/pnpm.env" PNPM \
    pnpm/pnpm v '^v([0-9]+\.[0-9]+\.[0-9]+)$' none "" \
    pnpm-linux-x64.tar.gz \
    pnpm-linux-arm64.tar.gz
  update_github_release_tool bun "$version_directory/bun.env" BUN \
    oven-sh/bun bun-v '^bun-v([0-9]+\.[0-9]+\.[0-9]+)$' shared SHASUMS256.txt \
    bun-linux-x64.zip \
    bun-linux-aarch64.zip
  update_go_toolchain
  update_node_toolchain
  update_python_toolchain
  update_rust_toolchain
  update_zig_toolchain
  update_debian_image_digest
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        check=true
        shift
        ;;
      --summary-file)
        [[ $# -ge 2 ]] || update_usage
        summary_file=$2
        shift 2
        ;;
      -h | --help)
        update_usage
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        update_usage
        ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
  command -v gh >/dev/null 2>&1 || die "gh is required"
  if [[ -z "${GITHUB_TOKEN:-}" && -n "${GH_TOKEN:-}" ]]; then
    GITHUB_TOKEN=$GH_TOKEN
  fi
  if [[ -z "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
    GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
  fi
  export GITHUB_TOKEN
  if [[ -n "${DEV_IMAGES_UPDATE_CACHE:-}" ]]; then
    export OPENSHELL_BUMP_CACHE=$DEV_IMAGES_UPDATE_CACHE
  fi
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/versions"
  cp -a "$repository_root/dev-images/versions/." "$work/versions/"
  cp -a "$repository_root/openshell/versions/base.env" "$work/openshell-base.env"
  update_pinned_versions

  local differ=false
  if files_differ "$repository_root/dev-images/versions" "$work/versions" \
    || files_differ "$repository_root/openshell/versions/base.env" "$work/openshell-base.env"; then
    differ=true
  fi
  if [[ "$differ" == true && ${#changes[@]} -eq 0 ]]; then
    die "files would change but the summary is empty"
  fi
  if [[ "$differ" == false && ${#changes[@]} -gt 0 ]]; then
    die "summary lists updates but the files match"
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
    cp -a "$work/versions/." "$repository_root/dev-images/versions/"
    cp -a "$work/openshell-base.env" "$repository_root/openshell/versions/base.env"
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
