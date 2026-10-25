#!/usr/bin/env bash
# Standalone Pi from the earendil-works/pi GitHub release.
# fd, rg, and just come from the base image.
# Tag v1.4.0 ships pi-linux-x64.tar.gz and pi-linux-arm64.tar.gz.
# Checksums are those names in that release's SHA256SUMS:
# https://github.com/earendil-works/pi/releases/download/v1.4.0/SHA256SUMS
# The Unix archive is a pi/ directory. Keep the tree: the binary reads
# sibling files (package.json, themes, native helpers) from its own directory.
# The archive is gzip. tar and gzip are already in the base image.
# curl is installed for the download and removed before the layer commits.
set -euo pipefail

: "${PI_VERSION:?PI_VERSION is required}"

pi_amd64_sha=f2e4e4329603223d03260cdb8bd5033dbdc1f73ba58ab8939db2e56546e115d2
pi_arm64_sha=fa5829c7ef83ffeaebba015715c8306220f89b2aa8a00154efbba98dd5440156

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    pi_arch=x64
    pi_sha=$pi_amd64_sha
    ;;
  arm64)
    pi_arch=arm64
    pi_sha=$pi_arm64_sha
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive=$tmp/pi.tar.gz
curl -fsSL -o "$archive" \
  "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-linux-${pi_arch}.tar.gz"
echo "${pi_sha}  ${archive}" | sha256sum -c -

mkdir -p /usr/local/lib
tar -xzf "$archive" -C /usr/local/lib
test -x /usr/local/lib/pi/pi
test -f /usr/local/lib/pi/package.json
ln -sfn /usr/local/lib/pi/pi /usr/local/bin/pi

version=$(pi --version)
if [[ "$version" != "$PI_VERSION" ]]; then
  printf 'pi --version printed %s, expected %s\n' "$version" "$PI_VERSION" >&2
  exit 1
fi

mkdir -p /tmp/pi-agent
chown 1000:1000 /tmp/pi-agent

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
