#!/usr/bin/env bash
# Install one pinned release into a destination directory.
# The version file supplies the archive URL and sha256. This script does not
# derive an asset name. A raw file is installed under the requested binary
# name. An archive is extracted, and each requested binary name must occur
# once. Installed files are mode 0755 and timestamped at the Unix epoch so a
# later COPY --link layer depends only on the bytes and that fixed metadata.
set -euo pipefail

usage() {
  printf 'usage: install_release_archive.sh --version-file PATH --key-prefix PREFIX --destination-directory PATH --binary NAME [--binary NAME]\n' >&2
  exit 2
}

read_recorded_value() {
  local version_file=$1 key=$2 line
  if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    printf 'invalid version key: %s\n' "$key" >&2
    return 1
  fi
  line=$(grep -E "^${key}=" "$version_file" | head -n 1) || true
  if [[ -z "$line" ]]; then
    printf 'missing %s in %s\n' "$key" "$version_file" >&2
    return 1
  fi
  printf '%s' "${line#*=}"
}

require_https_archive_url() {
  local archive_url=$1
  if [[ ! "$archive_url" =~ ^https://[^[:space:]]+$ ]]; then
    printf 'archive URL must be https with no spaces: %s\n' "$archive_url" >&2
    return 1
  fi
}

assert_recorded_sha256() {
  local file_path=$1 expected_sha256=$2 label=$3
  if [[ ! "$expected_sha256" =~ ^[a-f0-9]{64}$ ]]; then
    printf 'recorded sha256 for %s is not 64 lowercase hex characters\n' "$label" >&2
    return 1
  fi
  echo "${expected_sha256}  ${file_path}" | sha256sum -c -
}

require_safe_archive_member() {
  local member=$1
  case "$member" in
    /* | ../* | */../* | */.. | ..)
      printf 'archive member escapes the extract directory: %s\n' "$member" >&2
      return 1
      ;;
  esac
}

list_archive_members() {
  local archive_path=$1
  case "$archive_path" in
    *.tar.gz | *.tgz)
      tar -tzf "$archive_path"
      ;;
    *.tar.xz | *.txz)
      tar -tJf "$archive_path"
      ;;
    *.zip)
      unzip -Z -1 "$archive_path"
      ;;
    *)
      printf 'unsupported archive type: %s\n' "$archive_path" >&2
      return 1
      ;;
  esac
}

extract_archive() {
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
  case "$archive_path" in
    *.tar.gz | *.tgz)
      tar -xzf "$archive_path" -C "$extract_root" --no-same-owner --no-same-permissions
      ;;
    *.tar.xz | *.txz)
      tar -xJf "$archive_path" -C "$extract_root" --no-same-owner --no-same-permissions
      ;;
    *.zip)
      unzip -q "$archive_path" -d "$extract_root"
      ;;
  esac
}

install_normalized_file() {
  local source_path=$1 destination_path=$2
  install -m 0755 "$source_path" "$destination_path"
  touch -d @0 "$destination_path"
}

extract_named_binaries() {
  local archive_path=$1 destination_directory=$2
  shift 2
  local extract_root binary_name member_path
  local -a matches=()
  if [[ $# -eq 0 ]]; then
    printf 'at least one binary name is required\n' >&2
    return 1
  fi
  extract_root=$(mktemp -d)
  extract_archive "$archive_path" "$extract_root"
  mkdir -p "$destination_directory"
  chmod 0755 "$destination_directory"
  touch -d @0 "$destination_directory"
  for binary_name in "$@"; do
    mapfile -t matches < <(find "$extract_root" \( -type f -o -type l \) -name "$binary_name" | LC_ALL=C sort)
    if [[ ${#matches[@]} -ne 1 ]]; then
      printf 'expected one %s in the archive, found %s\n' "$binary_name" "${#matches[@]}" >&2
      rm -rf "$extract_root"
      return 1
    fi
    member_path=$(readlink -f "${matches[0]}")
    if [[ ! -f "$member_path" ]]; then
      printf 'archive member %s is not a regular file\n' "$binary_name" >&2
      rm -rf "$extract_root"
      return 1
    fi
    install_normalized_file "$member_path" "$destination_directory/$binary_name"
  done
  rm -rf "$extract_root"
}

install_raw_binary() {
  local archive_path=$1 destination_directory=$2 binary_name=$3
  mkdir -p "$destination_directory"
  chmod 0755 "$destination_directory"
  touch -d @0 "$destination_directory"
  install_normalized_file "$archive_path" "$destination_directory/$binary_name"
}

architecture_key_suffix() {
  local machine
  machine=$(dpkg --print-architecture 2>/dev/null || uname -m)
  case "$machine" in
    amd64 | x86_64)
      printf 'AMD64\n'
      ;;
    arm64 | aarch64)
      printf 'ARM64\n'
      ;;
    *)
      printf 'unsupported architecture: %s\n' "$machine" >&2
      return 1
      ;;
  esac
}

require_checksum_source() {
  local checksum_source=$1
  case "$checksum_source" in
    github_release_asset_digest | upstream_sidecar | upstream_shared_file:*)
      ;;
    *)
      printf 'recorded checksum source is not recognized: %s\n' "$checksum_source" >&2
      return 1
      ;;
  esac
}

download_archive() {
  local archive_url=$1 destination_path=$2
  curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 2 \
    --connect-timeout 20 --max-time 600 -o "$destination_path" "$archive_url"
}

# The download name keeps the archive suffix. Extraction classifies the file
# by that suffix, and a raw release file has none.
downloaded_archive_path() {
  local download_directory=$1 archive_url=$2
  case "$archive_url" in
    *.tar.gz)
      printf '%s/archive.tar.gz\n' "$download_directory"
      ;;
    *.tgz)
      printf '%s/archive.tgz\n' "$download_directory"
      ;;
    *.tar.xz)
      printf '%s/archive.tar.xz\n' "$download_directory"
      ;;
    *.txz)
      printf '%s/archive.txz\n' "$download_directory"
      ;;
    *.zip)
      printf '%s/archive.zip\n' "$download_directory"
      ;;
    *)
      printf '%s/archive\n' "$download_directory"
      ;;
  esac
}

install_release_archive() {
  local version_file=$1 key_prefix=$2 destination_directory=$3
  shift 3
  local architecture_suffix archive_url expected_sha256 checksum_source label download_directory archive_path
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
  case "$archive_url" in
    *.tar.gz | *.tgz | *.tar.xz | *.txz | *.zip)
      extract_named_binaries "$archive_path" "$destination_directory" "$@"
      ;;
    *)
      if [[ $# -ne 1 ]]; then
        printf 'a raw release file installs exactly one binary\n' >&2
        rm -rf "$download_directory"
        return 1
      fi
      install_raw_binary "$archive_path" "$destination_directory" "$1"
      ;;
  esac
  rm -rf "$download_directory"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  version_file=
  key_prefix=
  destination_directory=
  binary_names=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-file)
        version_file=$2
        shift 2
        ;;
      --key-prefix)
        key_prefix=$2
        shift 2
        ;;
      --destination-directory)
        destination_directory=$2
        shift 2
        ;;
      --binary)
        binary_names+=("$2")
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
  if [[ -z "$version_file" || -z "$key_prefix" || -z "$destination_directory" || ${#binary_names[@]} -eq 0 ]]; then
    usage
  fi
  if [[ ! "$key_prefix" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    printf 'key prefix must be uppercase: %s\n' "$key_prefix" >&2
    exit 2
  fi
  install_release_archive "$version_file" "$key_prefix" "$destination_directory" "${binary_names[@]}"
fi
