#!/usr/bin/env bash
# Digest push contract. Does not start Docker.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
push=$root/dev-images/scripts/push_image_by_digest.sh

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

grep -F -q 'push-by-digest=true' "$push" || fail "digest push flag"
grep -F -q 'rewrite-timestamp=true' "$push" || fail "timestamp rewrite"
grep -F -q 'push=true' "$push" || fail "push flag"
grep -F -q 'dev-images-ci-base:smoke' "$push" || fail "smoked tag"
grep -F -q 'remote_config' "$push" || fail "config digest comparison"
grep -F -q 'local_id' "$push" || fail "smoked image id"
grep -F -q 'build_image.sh' "$push" || fail "shared build command"
if grep -F -q ':latest' "$push"; then
  fail "digest push applies a release tag"
fi

workflow=$root/.github/workflows/dev-images-build-single-image.yml
if ! grep -n 'push_image_by_digest.sh' "$workflow" | grep -q "steps.build.outputs.smoke == 'true'"; then
  # The condition is on the step above the run line. Check the preceding step.
  if ! awk '
    /name: Push smoked image by digest/ { found=1 }
    found && /if: steps.build.outputs.smoke/ { ok=1 }
    found && /push_image_by_digest.sh/ { exit }
    END { exit ok ? 0 : 1 }
  ' "$workflow"; then
    fail "push is not gated on the smoke output"
  fi
fi

printf 'digest push contract passed\n'
