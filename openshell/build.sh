#!/usr/bin/env bash
# Build the shared OpenShell images in order. Does not start Docker.
# Harness images are separate. See README.md.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
script=$root/scripts/docker-build.sh

if ! command -v docker >/dev/null 2>&1; then
  printf 'docker is not on PATH. Start Docker yourself, then re-run.\n' >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  printf 'Docker is not running. Start it yourself, then re-run.\n' >&2
  exit 1
fi

bash "$script" "$root/agent-cli/Dockerfile" "$root" \
  "${OPENSHELL_AGENT_CLI_TAG:-openshell-agent-cli:phase1}" \
  FD_VERSION RG_VERSION JUST_VERSION
bash "$script" "$root/python/Dockerfile" "$root" \
  "${OPENSHELL_PYTHON_TAG:-openshell-python:phase1}" \
  UV_VERSION PYTHON_VERSION PRE_COMMIT_VERSION
bash "$script" "$root/rust/Dockerfile" "$root" \
  "${OPENSHELL_RUST_TAG:-openshell-rust:phase1}" \
  RUST_VERSION
bash "$script" "$root/go/Dockerfile" "$root" \
  "${OPENSHELL_GO_TAG:-openshell-go:phase1}" \
  GO_VERSION
