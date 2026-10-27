#!/usr/bin/env bash
# Build contract. Does not start Docker.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
builder=$root/dev-images/scripts/build_image.sh
dockerfile=$root/dev-images/base/Dockerfile
workflow=$root/.github/workflows/dev-images-build-single-image.yml

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

if grep -F -q 'push=true' "$builder"; then
  fail "build script pushes"
fi
if grep -F -q 'push-by-digest=true' "$builder"; then
  fail "build script pushes by digest"
fi
grep -F -q -- '--provenance=false' "$builder" || fail "provenance flag"
grep -F -q 'SOURCE_DATE_EPOCH=0' "$builder" || fail "source date epoch"
grep -F -q 'rewrite-timestamp=true' "$builder" || fail "timestamp rewrite"
grep -F -q -- '--sbom=false' "$builder" || fail "sbom flag"
if grep -F -q 'ARCHIVE_URL' "$builder"; then
  fail "build script passes archive URLs"
fi
grep -F -q 'DEBIAN_IMAGE' "$builder" || fail "debian image argument"

link_count=$(grep -c 'COPY --link --from=' "$dockerfile")
tool_count=$(grep -oE 'versions/[A-Za-z0-9._-]+\.env' "$dockerfile" | sort -u | wc -l)
if [[ "$link_count" -ne "$tool_count" ]]; then
  fail "COPY --link count $link_count does not match $tool_count tools"
fi
grep -F -q 'USER developer' "$dockerfile" || fail "runtime user"
grep -F -q 'org.opencontainers.image.source="https://github.com/iancleary/dockerfiles"' "$dockerfile" \
  || fail "source label"
if grep -E -q 'golang|nodejs|rustc|python3' "$dockerfile"; then
  fail "toolchain package in the base image"
fi

for version_file in "$root"/dev-images/versions/*.env; do
  base=$(basename "$version_file")
  case "$base" in
    debian.env | development-base-image.env) continue ;;
  esac
  name=${base%.env}
  if ! grep -R -F -q "$name.env" "$root/dev-images" --include=Dockerfile; then
    fail "dockerfile omits $name"
  fi
done
for recipe in go rust node python zig bun; do
  language_dockerfile=$root/dev-images/$recipe/Dockerfile
  [[ -f "$language_dockerfile" ]] || fail "missing $recipe dockerfile"
  grep -F -q 'FROM development-base' "$language_dockerfile" || fail "$recipe parent"
done
for recipe in go rust node zig bun; do
  grep -F -q 'COPY --link' "$root/dev-images/$recipe/Dockerfile" || fail "$recipe link"
done
grep -F -q 'uv python install' "$root/dev-images/python/Dockerfile" || fail "python uv install"
grep -F -q 'UV_PYTHON_INSTALL_DIR=/opt/python' "$root/dev-images/python/Dockerfile" || fail "python install directory"
grep -F -q 'development-base=docker-image://' "$builder" || fail "parent build context"
grep -F -q 'development-base=oci-layout://' "$builder" || fail "parent layout context"

grep -E -q '^permissions:$' "$workflow" || fail "workflow permissions"
grep -F -q 'contents: read' "$workflow" || fail "contents read"
grep -F -q 'attest-build-provenance' "$workflow" || fail "attestation"
grep -F -q 'cosign sign' "$workflow" || fail "cosign"
grep -F -q 'ubuntu-24.04-arm' "$workflow" || fail "arm64 runner"

justfile=$root/dev-images/justfile
grep -F -q 'smoke-base' "$justfile" || fail "just smoke recipe"
grep -F -q 'all: smoke-base go rust node python zig bun' "$justfile" || fail "just all recipe"
grep -F -q 'mod dev-images' "$root/justfile" || fail "root module"

pull_request_workflow=$root/.github/workflows/dev-images-verify-pull-request.yml
[[ -f "$pull_request_workflow" ]] || fail "missing pull request workflow"
grep -q '^  pull_request:' "$pull_request_workflow" || fail "pull request trigger"
grep -F -q '"dev-images/**"' "$pull_request_workflow" || fail "pull request path filter"
grep -F -q 'ubuntu-24.04-arm' "$pull_request_workflow" || fail "arm64 runner"
grep -F -q 'bash dev-images/scripts/build_image.sh' "$pull_request_workflow" || fail "pull request build"
grep -F -q 'bash dev-images/scripts/smoke_test_image.sh' "$pull_request_workflow" || fail "pull request smoke"
grep -F -q 'contents: read' "$pull_request_workflow" || fail "pull request permissions"
if grep -E -n 'packages:|id-token:|attestations:|docker/login-action|attest-build-provenance|cosign |push_image_by_digest|publish_release' "$pull_request_workflow"; then
  fail "pull request workflow publishes or signs"
fi

printf 'build image contract passed\n'
