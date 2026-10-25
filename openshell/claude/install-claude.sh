#!/usr/bin/env bash
# Claude Code native archive from the GitHub release.
# Checksums are the release SHASUMS256.txt lines. No install.sh and no API key.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/claude.env"
set +a

: "${CLAUDE_VERSION:?CLAUDE_VERSION is required}"
: "${CLAUDE_SHA256_AMD64:?CLAUDE_SHA256_AMD64 is required}"
: "${CLAUDE_SHA256_ARM64:?CLAUDE_SHA256_ARM64 is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    claude_arch=x64
    claude_sha=$CLAUDE_SHA256_AMD64
    ;;
  arm64)
    claude_arch=arm64
    claude_sha=$CLAUDE_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive=$tmp/claude.tgz
curl -fsSL -o "$archive" \
  "https://github.com/anthropics/claude-code/releases/download/v${CLAUDE_VERSION}/claude-linux-${claude_arch}.tar.gz"
echo "${claude_sha}  ${archive}" | sha256sum -c -
tar -xzf "$archive" -C "$tmp"
claude_bin=$(find "$tmp" -type f -name claude -print -quit)
test -n "$claude_bin"
install -m 0755 "$claude_bin" /usr/local/bin/claude
claude --version

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
