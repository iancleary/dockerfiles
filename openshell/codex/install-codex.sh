#!/usr/bin/env bash
# Official Codex musl binary from the rust-v0.164.0 GitHub release.
# No npm install and no API key.
set -euo pipefail

: "${CODEX_VERSION:?CODEX_VERSION is required}"

codex_amd64_sha=90dd0b03b28afcb7fa733a4f73b413db2916a47347efd43fb669cc1c774ee8e4
codex_arm64_sha=29a507a2a3fd8f6cd94b96b762d281d299d15d7902dee6132d314b78cf9108eb

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    triple=x86_64-unknown-linux-musl
    codex_sha=$codex_amd64_sha
    ;;
  arm64)
    triple=aarch64-unknown-linux-musl
    codex_sha=$codex_arm64_sha
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
