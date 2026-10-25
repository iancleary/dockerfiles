#!/usr/bin/env bash
# Install the just pin from openshell/versions/tools.env onto PATH.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
set -a
# shellcheck disable=SC1091
. "$root/versions/tools.env"
set +a

case "$(uname -m)" in
  x86_64 | amd64)
    triple=x86_64-unknown-linux-musl
    sha=$JUST_SHA256_AMD64
    ;;
  aarch64 | arm64)
    triple=aarch64-unknown-linux-musl
    sha=$JUST_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
archive=$tmp/just.tgz
curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 2 \
  --connect-timeout 20 --max-time 600 -o "$archive" \
  "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${triple}.tar.gz"
echo "${sha}  ${archive}" | sha256sum -c -
sudo tar -xzf "$archive" -C /usr/local/bin just
just --version
