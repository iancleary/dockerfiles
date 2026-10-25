#!/usr/bin/env bash
# uv, one pinned CPython, and pre-commit. No agent CLI.
# CPython is the python-build-standalone archive, not `uv python install`.
# pre-commit is installed from a hashed requirements file.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
# shellcheck disable=SC1091
. "$here/python.env"
set +a
# shellcheck disable=SC1091
. "$here/harden-runtime.sh"

: "${UV_VERSION:?UV_VERSION is required}"
: "${PYTHON_VERSION:?PYTHON_VERSION is required}"
: "${PYTHON_STANDALONE_TAG:?PYTHON_STANDALONE_TAG is required}"
: "${PRE_COMMIT_VERSION:?PRE_COMMIT_VERSION is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
apt-mark manual ca-certificates

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64)
    uv_triple=x86_64-unknown-linux-musl
    uv_sha=$UV_SHA256_AMD64
    py_triple=x86_64-unknown-linux-gnu
    py_sha=$PYTHON_SHA256_AMD64
    ;;
  arm64)
    uv_triple=aarch64-unknown-linux-musl
    uv_sha=$UV_SHA256_ARM64
    py_triple=aarch64-unknown-linux-gnu
    py_sha=$PYTHON_SHA256_ARM64
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$arch" >&2
    exit 1
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch_checked() {
  local url=$1 dest=$2 sha=$3
  curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 2 \
    --connect-timeout 20 --max-time 600 -o "$dest" "$url"
  echo "${sha}  ${dest}" | sha256sum -c -
}

fetch_checked \
  "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_triple}.tar.gz" \
  "$tmp/uv.tgz" "$uv_sha"
tar -xzf "$tmp/uv.tgz" -C "$tmp"
uv_bin=$(find "$tmp" -type f -name uv -print -quit)
uvx_bin=$(find "$tmp" -type f -name uvx -print -quit)
test -n "$uv_bin"
test -n "$uvx_bin"
install -m 0755 "$uv_bin" /usr/local/bin/uv
install -m 0755 "$uvx_bin" /usr/local/bin/uvx

# A raw plus in this filename is decoded as a space. The release asset uses %2B.
py_url="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_STANDALONE_TAG}/cpython-${PYTHON_VERSION}%2B${PYTHON_STANDALONE_TAG}-${py_triple}-install_only_stripped.tar.gz"
fetch_checked "$py_url" "$tmp/python.tgz" "$py_sha"
py_root=/usr/local/share/uv/python
rm -rf "$py_root"
mkdir -p "$py_root"
tar -xzf "$tmp/python.tgz" -C "$py_root"
test -x "$py_root/python/bin/python3"
ln -sfn "$py_root/python/bin/python3" /usr/local/bin/python3
ln -sfn python3 /usr/local/bin/python
ln -sfn python3 /usr/local/bin/python3.13

py_out=$(python3 --version)
if [[ "$py_out" != "Python ${PYTHON_VERSION}" ]]; then
  printf 'python3 --version printed [%s], want Python %s\n' "$py_out" "$PYTHON_VERSION" >&2
  exit 1
fi

tool=/usr/local/share/uv/tools/pre-commit
mkdir -p /usr/local/share/uv/tools
UV_CACHE_DIR=$tmp/cache uv venv "$tool" --python /usr/local/bin/python3
UV_CACHE_DIR=$tmp/cache uv pip install \
  --python "$tool/bin/python" \
  --require-hashes \
  --only-binary :all: \
  --no-cache \
  -r "$here/pre-commit-requirements.txt"
ln -sfn "$tool/bin/pre-commit" /usr/local/bin/pre-commit

uv_out=$(uv --version)
uv_line=${uv_out%%$'\n'*}
case "$uv_line" in
  "uv ${UV_VERSION}" | "uv ${UV_VERSION} "*) ;;
  *)
    printf 'uv --version printed [%s], want uv %s\n' "$uv_out" "$UV_VERSION" >&2
    exit 1
    ;;
esac
pc_out=$(pre-commit --version)
pc_line=${pc_out%%$'\n'*}
case "$pc_line" in
  "pre-commit ${PRE_COMMIT_VERSION}" | "pre-commit ${PRE_COMMIT_VERSION} "*) ;;
  *)
    printf 'pre-commit --version printed [%s], want pre-commit %s\n' "$pc_out" "$PRE_COMMIT_VERSION" >&2
    exit 1
    ;;
esac

install -d -m 0755 -o 1000 -g 1000 /tmp/uv-cache
install -d -m 0755 -o 1000 -g 1000 /tmp/pre-commit

apt-get purge -y curl
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
harden_runtime
