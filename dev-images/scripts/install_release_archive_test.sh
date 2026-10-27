#!/usr/bin/env bash
# Extraction and checksum checks. Does not download.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
installer=$root/dev-images/scripts/install_release_archive.sh
# shellcheck disable=SC1090,SC1091
source "$installer"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

printf 'hello\n' >"$temporary/blob"
good=$(sha256sum "$temporary/blob" | awk '{print $1}')
assert_recorded_sha256 "$temporary/blob" "$good" "fixture"
bad=$(printf 'ab%.0s' {1..32})
if (assert_recorded_sha256 "$temporary/blob" "$bad" "fixture") >/dev/null 2>&1; then
  fail "checksum mismatch was accepted"
fi
if (require_https_archive_url "http://example.invalid/tool") >/dev/null 2>&1; then
  fail "http URL was accepted"
fi
require_https_archive_url "https://github.com/example/tool/releases/download/1.0.0/tool.tar.gz"
require_checksum_source "github_release_asset_digest"
require_checksum_source "upstream_sidecar"
require_checksum_source "upstream_shared_file:sha256sum.txt"
if (require_checksum_source "mise-versions") >/dev/null 2>&1; then
  fail "unknown checksum source was accepted"
fi
if (require_safe_archive_member "../escape") >/dev/null 2>&1; then
  fail "escaping archive member was accepted"
fi

mkdir -p "$temporary/source/bin"
printf '#!/bin/sh\nprintf hello\n' >"$temporary/source/bin/demo"
chmod 0755 "$temporary/source/bin/demo"
tar -czf "$temporary/demo.tar.gz" -C "$temporary/source" bin
extract_named_binaries "$temporary/demo.tar.gz" "$temporary/out" demo
[[ -x "$temporary/out/demo" ]] || fail "extracted binary is not executable"
stamp=$(stat -c '%Y' "$temporary/out/demo")
[[ "$stamp" == 0 ]] || fail "extracted binary timestamp is not the Unix epoch"
mode=$(stat -c '%a' "$temporary/out/demo")
[[ "$mode" == 755 ]] || fail "extracted binary mode is $mode"

if (extract_named_binaries "$temporary/demo.tar.gz" "$temporary/out-missing" other) >/dev/null 2>&1; then
  fail "missing binary name was accepted"
fi

install_raw_binary "$temporary/blob" "$temporary/raw" jq
[[ -x "$temporary/raw/jq" ]] || fail "raw binary was not installed"
cmp -s "$temporary/blob" "$temporary/raw/jq" || fail "raw binary bytes changed"

if grep -R -n 'releases/download' "$installer"; then
  fail "installer derives a release URL"
fi

[[ "$(downloaded_archive_path /tmp/dl https://example.invalid/tool.tar.gz)" == /tmp/dl/archive.tar.gz ]] \
  || fail "tar.gz download name"
[[ "$(downloaded_archive_path /tmp/dl https://example.invalid/tool.tar.xz)" == /tmp/dl/archive.tar.xz ]] \
  || fail "tar.xz download name"
[[ "$(downloaded_archive_path /tmp/dl https://example.invalid/tool.zip)" == /tmp/dl/archive.zip ]] \
  || fail "zip download name"
[[ "$(downloaded_archive_path /tmp/dl https://example.invalid/jq-linux-amd64)" == /tmp/dl/archive ]] \
  || fail "raw download name"

version_directory=$root/dev-images/versions
for version_file in "$version_directory"/*.env; do
  base=$(basename "$version_file")
  [[ "$base" == debian.env ]] && continue
  version_key=$(grep -E '^[A-Z0-9_]+_VERSION=' "$version_file" | head -n 1 | cut -d= -f1)
  prefix=${version_key%_VERSION}
  for suffix in ARCHIVE_URL_AMD64 ARCHIVE_URL_ARM64; do
    value=$(read_recorded_value "$version_file" "${prefix}_${suffix}")
    require_https_archive_url "$value" || fail "${base} ${suffix}"
  done
  for suffix in SHA256_AMD64 SHA256_ARM64; do
    value=$(read_recorded_value "$version_file" "${prefix}_${suffix}")
    [[ "$value" =~ ^[a-f0-9]{64}$ ]] || fail "${base} ${suffix}"
  done
  require_checksum_source "$(read_recorded_value "$version_file" "${prefix}_CHECKSUM_SOURCE")" \
    || fail "${base} checksum source"
done

printf 'install release archive tests passed\n'
