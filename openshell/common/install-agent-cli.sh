#!/usr/bin/env bash
# Install the agent-cli floor: fd, rg, just, and the uid 1000 user.
# Runs inside the image. Does not install a language toolchain or an agent.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/tools.env"
set +a
# shellcheck disable=SC1091
. "$here/harden-runtime.sh"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    triple=x86_64-unknown-linux-musl
    fd_sha=$FD_SHA256_AMD64
    rg_sha=$RG_SHA256_AMD64
    just_sha=$JUST_SHA256_AMD64
    ;;
  arm64)
    triple=aarch64-unknown-linux-musl
    fd_sha=$FD_SHA256_ARM64
    rg_sha=$RG_SHA256_ARM64
    just_sha=$JUST_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

fetch_checked() {
  local url=$1 dest=$2 sha=$3
  curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 2 \
    --connect-timeout 20 --max-time 600 -o "$dest" "$url"
  echo "${sha}  ${dest}" | sha256sum -c -
}

fetch_checked \
  "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-${triple}.tar.gz" \
  "$tmp/fd.tgz" "$fd_sha"
fetch_checked \
  "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-${triple}.tar.gz" \
  "$tmp/rg.tgz" "$rg_sha"
fetch_checked \
  "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${triple}.tar.gz" \
  "$tmp/just.tgz" "$just_sha"

tar -xzf "$tmp/fd.tgz" -C "$tmp"
tar -xzf "$tmp/rg.tgz" -C "$tmp"
tar -xzf "$tmp/just.tgz" -C "$tmp"
fd_bin=$(find "$tmp" -type f -name fd -print -quit)
rg_bin=$(find "$tmp" -type f -name rg -print -quit)
just_bin=$(find "$tmp" -type f -name just -print -quit)
test -n "$fd_bin"
test -n "$rg_bin"
test -n "$just_bin"
install -m 0755 "$fd_bin" /usr/local/bin/fd
install -m 0755 "$rg_bin" /usr/local/bin/rg
install -m 0755 "$just_bin" /usr/local/bin/just

/usr/local/bin/fd --version
/usr/local/bin/rg --version
/usr/local/bin/just --version
/usr/local/bin/fd --help | grep -q -- --no-require-git
/usr/local/bin/rg --help | grep -q -- --no-config

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
harden_runtime
