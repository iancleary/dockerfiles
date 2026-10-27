#!/usr/bin/env bash
# Install one recorded toolchain archive as a directory tree.
# The version file supplies the archive URL and sha256. This script does not
# derive an asset name. Modes are preserved, other-write is removed, and
# every timestamp is the Unix epoch so a later COPY --link layer follows
# the bytes and that fixed metadata.
set -euo pipefail

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$script_directory/install_release_archive.sh"

stamp_installed_tree() {
  local tree=$1
  chmod -R a+rX,go-w "$tree"
  find "$tree" -exec touch -h -d @0 {} +
}

extract_toolchain_archive() {
  local archive_path=$1 extract_root=$2 member member_list status=0
  member_list=$(mktemp)
  list_archive_members "$archive_path" >"$member_list" || status=$?
  if [[ "$status" -ne 0 ]]; then
    rm -f "$member_list"
    return "$status"
  fi
  while IFS= read -r member || [[ -n "$member" ]]; do
    [[ -z "$member" ]] && continue
    require_safe_archive_member "$member"
  done <"$member_list"
  rm -f "$member_list"
  mkdir -p "$extract_root"
  case "$archive_path" in
    *.tar.gz | *.tgz)
      tar -xzf "$archive_path" -C "$extract_root" --no-same-owner
      ;;
    *.tar.xz | *.txz)
      tar -xJf "$archive_path" -C "$extract_root" --no-same-owner
      ;;
    *.zip)
      unzip -q "$archive_path" -d "$extract_root"
      ;;
    *)
      printf 'unsupported toolchain archive: %s\n' "$archive_path" >&2
      return 1
      ;;
  esac
}

verify_minisign_archive() {
  local archive_path=$1 version_file=$2 key_prefix=$3
  local architecture_suffix public_key signature_url signature_path
  architecture_suffix=$(architecture_key_suffix)
  public_key=$(read_recorded_value "$version_file" "${key_prefix}_MINISIGN_PUBLIC_KEY")
  signature_url=$(read_recorded_value "$version_file" "${key_prefix}_SIGNATURE_URL_${architecture_suffix}")
  require_https_archive_url "$signature_url"
  if [[ ! "$public_key" =~ ^RW[A-Za-z0-9+/]+=?=?$ ]]; then
    printf 'recorded minisign public key is not a minisign key\n' >&2
    return 1
  fi
  signature_path=${archive_path}.minisig
  download_archive "$signature_url" "$signature_path"
  minisign -V -P "$public_key" -m "$archive_path" -x "$signature_path"
}

install_toolchain_tree() {
  local version_file=$1 key_prefix=$2 destination=$3 layout=$4 signature_kind=${5:-}
  local architecture_suffix archive_url expected_sha256 checksum_source label
  local download_directory archive_path extract_root top_count top_path
  architecture_suffix=$(architecture_key_suffix)
  archive_url=$(read_recorded_value "$version_file" "${key_prefix}_ARCHIVE_URL_${architecture_suffix}")
  expected_sha256=$(read_recorded_value "$version_file" "${key_prefix}_SHA256_${architecture_suffix}")
  checksum_source=$(read_recorded_value "$version_file" "${key_prefix}_CHECKSUM_SOURCE")
  require_https_archive_url "$archive_url"
  require_checksum_source "$checksum_source"
  label="${key_prefix} ${architecture_suffix}"
  download_directory=$(mktemp -d)
  archive_path=$(downloaded_archive_path "$download_directory" "$archive_url")
  download_archive "$archive_url" "$archive_path"
  assert_recorded_sha256 "$archive_path" "$expected_sha256" "$label"
  if [[ "$signature_kind" == minisign ]]; then
    verify_minisign_archive "$archive_path" "$version_file" "$key_prefix"
  elif [[ -n "$signature_kind" ]]; then
    printf 'unknown signature kind %s\n' "$signature_kind" >&2
    rm -rf "$download_directory"
    return 1
  fi
  extract_root=$(mktemp -d)
  extract_toolchain_archive "$archive_path" "$extract_root"
  top_count=$(find "$extract_root" -mindepth 1 -maxdepth 1 | wc -l)
  if [[ "$top_count" -ne 1 ]]; then
    printf 'toolchain archive %s has %s top-level entries\n' "$label" "$top_count" >&2
    rm -rf "$download_directory" "$extract_root"
    return 1
  fi
  top_path=$(find "$extract_root" -mindepth 1 -maxdepth 1)
  if [[ ! -d "$top_path" ]]; then
    printf 'toolchain archive %s top-level entry is not a directory\n' "$label" >&2
    rm -rf "$download_directory" "$extract_root"
    return 1
  fi
  mkdir -p "$(dirname "$destination")"
  rm -rf "$destination"
  case "$layout" in
    tree)
      mv "$top_path" "$destination"
      ;;
    strip)
      mkdir -p "$destination"
      find "$top_path" -mindepth 1 -maxdepth 1 -exec mv -t "$destination" {} +
      ;;
    *)
      printf 'unknown toolchain layout %s\n' "$layout" >&2
      rm -rf "$download_directory" "$extract_root"
      return 1
      ;;
  esac
  stamp_installed_tree "$destination"
  rm -rf "$download_directory" "$extract_root"
}

install_relative_symlink() {
  local link_path=$1 link_target=$2 link_directory
  link_directory=$(dirname "$link_path")
  mkdir -p "$link_directory"
  ln -s "$link_target" "$link_path"
  touch -h -d @0 "$link_path"
  touch -d @0 "$link_directory"
  chmod 0755 "$link_directory"
}
