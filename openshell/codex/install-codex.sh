#!/usr/bin/env bash
# Official Codex musl binary from the rust-v<version> GitHub release.
# No npm install and no API key.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/codex.env"
set +a

: "${CODEX_VERSION:?CODEX_VERSION is required}"
: "${CODEX_SHA256_AMD64:?CODEX_SHA256_AMD64 is required}"
: "${CODEX_SHA256_ARM64:?CODEX_SHA256_ARM64 is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    triple=x86_64-unknown-linux-musl
    codex_sha=$CODEX_SHA256_AMD64
    ;;
  arm64)
    triple=aarch64-unknown-linux-musl
    codex_sha=$CODEX_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive=$tmp/codex.tgz
curl -fsSL -o "$archive" \
  "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${triple}.tar.gz"
echo "${codex_sha}  ${archive}" | sha256sum -c -
tar -xzf "$archive" -C "$tmp"
codex_bin=$(find "$tmp" -type f -name 'codex-*' -print -quit)
test -n "$codex_bin"
install -m 0755 "$codex_bin" /usr/local/bin/codex
codex --version

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
