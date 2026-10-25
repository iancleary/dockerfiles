#!/usr/bin/env bash
# Official Go toolchain tarball. No agent CLI. cgo is not set up.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/go.env"
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
    go_arch=amd64
    go_sha=$GO_SHA256_AMD64
    ;;
  arm64)
    go_arch=arm64
    go_sha=$GO_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive=$tmp/go.tgz
curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 2 \
  --connect-timeout 20 --max-time 600 -o "$archive" \
  "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz"
echo "${go_sha}  ${archive}" | sha256sum -c -
rm -rf /usr/local/go
tar -C /usr/local -xzf "$archive"
ln -sfn /usr/local/go/bin/go /usr/local/bin/go
ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt
go version

install -d -m 0755 -o 1000 -g 1000 /tmp/go
install -d -m 0755 -o 1000 -g 1000 /tmp/gocache

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
harden_runtime
