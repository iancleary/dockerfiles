#!/usr/bin/env bash
# Install the recorded CPython with the uv already present in dev-base.
# The version file names one python-build-standalone archive and its sha256.
# This script writes that record as a uv downloads JSON and runs
# `uv python install <version>`. uv checks the sha256 before it unpacks.
# The tree is /opt/python, owned by developer.
set -euo pipefail

here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$here/install_toolchain_tree.sh"

version_file=${PYTHON_VERSION_FILE:-$here/python.env}
install_directory=/opt/python
json_path=$(mktemp)

version=$(read_recorded_value "$version_file" PYTHON_VERSION)
standalone_tag=$(read_recorded_value "$version_file" PYTHON_STANDALONE_TAG)
architecture_suffix=$(architecture_key_suffix)
archive_url=$(read_recorded_value "$version_file" "PYTHON_ARCHIVE_URL_${architecture_suffix}")
expected_sha256=$(read_recorded_value "$version_file" "PYTHON_SHA256_${architecture_suffix}")
checksum_source=$(read_recorded_value "$version_file" PYTHON_CHECKSUM_SOURCE)
require_https_archive_url "$archive_url"
require_checksum_source "$checksum_source"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'recorded Python version is not a stable release: %s\n' "$version" >&2
  exit 1
fi
if [[ ! "$standalone_tag" =~ ^[0-9]{8}$ ]]; then
  printf 'recorded Python standalone tag is not a date: %s\n' "$standalone_tag" >&2
  exit 1
fi
if [[ ! "$expected_sha256" =~ ^[a-f0-9]{64}$ ]]; then
  printf 'recorded Python sha256 is not 64 lowercase hex characters\n' >&2
  exit 1
fi

case "$architecture_suffix" in
  AMD64) architecture_family=x86_64 ;;
  ARM64) architecture_family=aarch64 ;;
  *)
    printf 'unsupported Python architecture suffix: %s\n' "$architecture_suffix" >&2
    exit 1
    ;;
esac

major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
patch=${rest#*.}

jq -n \
  --arg key "cpython-${version}-linux-${architecture_family}-gnu" \
  --arg url "$archive_url" \
  --arg sha256 "$expected_sha256" \
  --arg build "$standalone_tag" \
  --arg family "$architecture_family" \
  --argjson major "$major" \
  --argjson minor "$minor" \
  --argjson patch "$patch" \
  '{
    ($key): {
      name: "cpython",
      arch: {family: $family, variant: null},
      os: "linux",
      libc: "gnu",
      major: $major,
      minor: $minor,
      patch: $patch,
      prerelease: "",
      url: $url,
      sha256: $sha256,
      variant: null,
      build: $build
    }
  }' >"$json_path"

mkdir -p "$install_directory"
export UV_PYTHON_INSTALL_DIR=$install_directory
export UV_PYTHON_BIN_DIR=$install_directory/bin
export UV_CACHE_DIR=/tmp/uv-python-cache
uv python install \
  --no-config \
  --no-cache \
  --default \
  --python-downloads-json-url "$json_path" \
  "$version"
rm -rf "$UV_CACHE_DIR" "$json_path"

if [[ ! -x "$install_directory/bin/python3" ]]; then
  printf 'uv did not install python3\n' >&2
  exit 1
fi
if [[ ! -e "$install_directory/bin/python" ]]; then
  ln -s python3 "$install_directory/bin/python"
fi

chown -R developer:developer "$install_directory"
stamp_installed_tree "$install_directory"
