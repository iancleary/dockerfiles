#!/usr/bin/env bash
# Rewrite dev-images version files to the newest stable upstream release.
#
# Policy is latest_stable: the newest stable release across minor and major
# versions. Prerelease tags are skipped. A downgrade is refused.
# Toolchains are not tracked. Node, Go, Rust, and Python stay out of this
# image until a later phase.
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
