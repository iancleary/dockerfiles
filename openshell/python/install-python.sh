#!/usr/bin/env bash
# uv, one pinned CPython, and pre-commit. No agent CLI.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/versions.env"
set +a

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    triple=x86_64-unknown-linux-musl
    uv_sha=$UV_SHA256_AMD64
    ;;
  arm64)
    triple=aarch64-unknown-linux-musl
    uv_sha=$UV_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/uv.tgz" \
  "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${triple}.tar.gz"
echo "${uv_sha}  ${tmp}/uv.tgz" | sha256sum -c -
tar -xzf "$tmp/uv.tgz" -C "$tmp"
uv_bin=$(find "$tmp" -type f -name uv -print -quit)
uvx_bin=$(find "$tmp" -type f -name uvx -print -quit)
test -n "$uv_bin"
test -n "$uvx_bin"
install -m 0755 "$uv_bin" /usr/local/bin/uv
install -m 0755 "$uvx_bin" /usr/local/bin/uvx

install_dir=/usr/local/share/uv/python
tool_dir=/usr/local/share/uv/tools
mkdir -p "$install_dir" "$tool_dir" /usr/local/bin
UV_PYTHON_INSTALL_DIR=$install_dir \
  UV_PYTHON_BIN_DIR=/usr/local/bin \
  UV_CACHE_DIR=$tmp/cache \
  uv python install "$PYTHON_VERSION"
ln -sfn python3.13 /usr/local/bin/python3
ln -sfn python3.13 /usr/local/bin/python
UV_PYTHON_INSTALL_DIR=$install_dir \
  UV_TOOL_DIR=$tool_dir \
  UV_TOOL_BIN_DIR=/usr/local/bin \
  UV_CACHE_DIR=$tmp/cache \
  uv tool install "pre-commit==${PRE_COMMIT_VERSION}"

uv --version
python3 --version
pre-commit --version

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
