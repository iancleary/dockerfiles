#!/usr/bin/env bash
# Pi release binary. fd, rg, and just come from the base image.
# Pi is the linux archive from earendil-works/pi.
# The tree is installed together so `pi --version` can see package.json.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/pi.env"
set +a

: "${PI_VERSION:?PI_VERSION is required}"
: "${PI_SHA256_AMD64:?PI_SHA256_AMD64 is required}"
: "${PI_SHA256_ARM64:?PI_SHA256_ARM64 is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    pi_asset=pi-linux-x64.tar.gz
    pi_sha=$PI_SHA256_AMD64
    ;;
  arm64)
    pi_asset=pi-linux-arm64.tar.gz
    pi_sha=$PI_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pi_archive=$tmp/pi.tgz
curl -fsSL -o "$pi_archive" \
  "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/${pi_asset}"
echo "${pi_sha}  ${pi_archive}" | sha256sum -c -
tar -xzf "$pi_archive" -C "$tmp"
test -x "$tmp/pi/pi"
test -f "$tmp/pi/package.json"
rm -rf /usr/local/lib/pi
mkdir -p /usr/local/lib
mv "$tmp/pi" /usr/local/lib/pi
ln -sfn /usr/local/lib/pi/pi /usr/local/bin/pi
pi_got=$(/usr/local/bin/pi --version)
pi_got=${pi_got%%$'\n'*}
pi_got=${pi_got//[[:space:]]/}
if [[ "$pi_got" != "$PI_VERSION" ]]; then
  printf 'pi --version printed %s, expected %s\n' "$pi_got" "$PI_VERSION" >&2
  exit 1
fi

mkdir -p /tmp/pi-agent
chown 1000:1000 /tmp/pi-agent

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
