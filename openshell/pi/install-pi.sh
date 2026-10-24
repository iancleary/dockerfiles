#!/usr/bin/env bash
# Node and Pi only. fd, rg, and just come from the base image.
# npm dist-tag 1.4.0 on 2026-10-23. Integrity:
# sha512-Z41LpZ3yYHSC/UUps6Mr39UMFPwH8elhJBG9DY1P7kuzsE5qSK/6eMj2EHzO5evJRQWLbKSqUMw+4nCNtIyiQg==
set -euo pipefail

: "${PI_VERSION:?PI_VERSION is required}"
: "${NODE_VERSION:?NODE_VERSION is required}"

# https://nodejs.org/dist/v24.22.1/SHASUMS256.txt
node_amd64_sha=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
node_arm64_sha=dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl xz-utils
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    node_arch=x64
    node_sha=$node_amd64_sha
    ;;
  arm64)
    node_arch=arm64
    node_sha=$node_arm64_sha
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive=$tmp/node.tar.xz
curl -fsSL -o "$archive" \
  "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
echo "${node_sha}  ${archive}" | sha256sum -c -
tar -xJf "$archive" -C /usr/local --strip-components=1

npm install -g "@earendil-works/pi-coding-agent@${PI_VERSION}"
npm cache clean --force
pi --version
mkdir -p /tmp/pi-agent
chown 1000:1000 /tmp/pi-agent

apt-get purge -y curl xz-utils
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
