#!/usr/bin/env bash
# Official rustc, cargo, and rust-std. No rustup installer and no agent CLI.
# The tarballs are the dateless dist files. channel-rust-<version>.toml
# still records a dist date; the install does not use it.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/rust.env"
set +a

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gcc libc6-dev xz-utils
apt-mark manual ca-certificates gcc libc6-dev

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    triple=x86_64-unknown-linux-gnu
    rustc_sha=$RUSTC_SHA256_AMD64
    cargo_sha=$CARGO_SHA256_AMD64
    std_sha=$RUST_STD_SHA256_AMD64
    ;;
  arm64)
    triple=aarch64-unknown-linux-gnu
    rustc_sha=$RUSTC_SHA256_ARM64
    cargo_sha=$CARGO_SHA256_ARM64
    std_sha=$RUST_STD_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

install_component() {
  local name=$1 sha=$2
  local archive="$tmp/${name}.tar.xz"
  local dest="$tmp/${name}"
  curl -fsSL -o "$archive" \
    "https://static.rust-lang.org/dist/${name}-${RUST_VERSION}-${triple}.tar.xz"
  echo "${sha}  ${archive}" | sha256sum -c -
  mkdir -p "$dest"
  tar -xJf "$archive" -C "$dest"
  local installer
  installer=$(find "$dest" -type f -name install.sh -print -quit)
  test -n "$installer"
  sh "$installer" --prefix=/usr/local --disable-ldconfig
  rm -rf "$dest" "$archive"
}

install_component rustc "$rustc_sha"
install_component rust-std "$std_sha"
install_component cargo "$cargo_sha"

rustc --version
cargo --version

apt-get purge -y curl xz-utils
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
