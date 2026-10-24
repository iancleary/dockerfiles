#!/usr/bin/env bash
# Claude Code native archive from the v2.1.309 GitHub release.
# Checksums match that release's SHASUMS256.txt. No install.sh and no API key.
set -euo pipefail

: "${CLAUDE_VERSION:?CLAUDE_VERSION is required}"

claude_amd64_sha=6259b381b9501b0b2b5d3ce4c068595bf32a59f1ca131ed69a1b1ae25b891cad
claude_arm64_sha=8ecd1f2d06ccbd3f89c8886e840e42b57a19063f3de9cfe5f7d90fe875ba99ef

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    claude_arch=x64
    claude_sha=$claude_amd64_sha
    ;;
  arm64)
    claude_arch=arm64
    claude_sha=$claude_arm64_sha
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
