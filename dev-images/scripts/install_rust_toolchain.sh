#!/usr/bin/env bash
# Official rustc, cargo, rust-std, rustfmt, and clippy standalone archives.
# There is no rustup and no default host configuration. Checksums are the
# xz_hash values from the signed channel manifest.
set -euo pipefail

here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$here/install_toolchain_tree.sh"

version_file=/tool/rust.env
prefix=/out/usr/local
mkdir -p "$prefix"

install_rust_component() {
  local key_prefix=$1
  local architecture_suffix archive_url expected_sha256 checksum_source label
  local download_directory archive_path extract_root installer
  architecture_suffix=$(architecture_key_suffix)
  archive_url=$(read_recorded_value "$version_file" "${key_prefix}_ARCHIVE_URL_${architecture_suffix}")
  expected_sha256=$(read_recorded_value "$version_file" "${key_prefix}_SHA256_${architecture_suffix}")
  checksum_source=$(read_recorded_value "$version_file" RUST_CHECKSUM_SOURCE)
  require_https_archive_url "$archive_url"
  require_checksum_source "$checksum_source"
  label="${key_prefix} ${architecture_suffix}"
  download_directory=$(mktemp -d)
  archive_path=$(downloaded_archive_path "$download_directory" "$archive_url")
  download_archive "$archive_url" "$archive_path"
  assert_recorded_sha256 "$archive_path" "$expected_sha256" "$label"
  extract_root=$(mktemp -d)
  extract_toolchain_archive "$archive_path" "$extract_root"
  installer=$(find "$extract_root" -type f -name install.sh -print -quit)
  if [[ -z "$installer" ]]; then
    printf 'rust component %s has no install.sh\n' "$label" >&2
    rm -rf "$download_directory" "$extract_root"
    return 1
  fi
  sh "$installer" --prefix="$prefix" --disable-ldconfig
  rm -rf "$download_directory" "$extract_root"
}

install_rust_component RUSTC
install_rust_component RUST_STD
install_rust_component CARGO
install_rust_component RUSTFMT
install_rust_component CLIPPY
stamp_installed_tree "$prefix"
