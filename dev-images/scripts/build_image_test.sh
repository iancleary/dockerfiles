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
tool_count=$(find "$root/dev-images/versions" -name '*.env' ! -name 'debian.env' | wc -l)
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
  [[ "$base" == debian.env ]] && continue
  name=${base%.env}
  grep -F -q "$name.env" "$dockerfile" || fail "dockerfile omits $name"
done

grep -E -q '^permissions:$' "$workflow" || fail "workflow permissions"
grep -F -q 'contents: read' "$workflow" || fail "contents read"
grep -F -q 'attest-build-provenance' "$workflow" || fail "attestation"
grep -F -q 'cosign sign' "$workflow" || fail "cosign"
grep -F -q 'ubuntu-24.04-arm' "$workflow" || fail "arm64 runner"

justfile=$root/dev-images/justfile
grep -F -q 'smoke-base' "$justfile" || fail "just smoke recipe"
grep -F -q 'all: smoke-base' "$justfile" || fail "just all recipe"
grep -F -q 'mod dev-images' "$root/justfile" || fail "root module"

printf 'build image contract passed\n'
