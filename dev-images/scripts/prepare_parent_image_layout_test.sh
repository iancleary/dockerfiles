#!/usr/bin/env bash
# The parent layout converter does not need Docker.
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)
converter=$root/dev-images/scripts/prepare_parent_image_layout.py

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/classic/layer"
printf 'parent-layout\n' >"$work/classic/layer/marker"
tar -cf "$work/classic/layer.tar" -C "$work/classic/layer" marker
printf '{"architecture":"amd64","os":"linux"}\n' >"$work/classic/config.json"
python3 - "$work/classic" <<'PY'
import json, os, sys
classic = sys.argv[1]
manifest = [{
    "Config": "config.json",
    "RepoTags": ["dev-base:local"],
    "Layers": ["layer.tar"],
}]
with open(os.path.join(classic, "manifest.json"), "w", encoding="utf-8") as output:
    json.dump(manifest, output)
PY
tar -cf "$work/classic.tar" -C "$work/classic" manifest.json config.json layer.tar

python3 "$converter" "$work/classic.tar" "$work/classic-layout"
[[ -f "$work/classic-layout/oci-layout" ]] || fail "classic oci-layout"
[[ -f "$work/classic-layout/index.json" ]] || fail "classic index"
python3 - "$work/classic-layout" <<'PY'
import hashlib, json, os, sys
layout = sys.argv[1]
index = json.load(open(os.path.join(layout, "index.json"), encoding="utf-8"))
descriptor = index["manifests"][0]
digest = descriptor["digest"].removeprefix("sha256:")
blob = os.path.join(layout, "blobs", "sha256", digest)
payload = open(blob, "rb").read()
if hashlib.sha256(payload).hexdigest() != digest:
    raise SystemExit("manifest blob digest does not match index")
if len(payload) != descriptor["size"]:
    raise SystemExit("manifest blob size does not match index")
manifest = json.loads(payload)
if len(manifest["layers"]) != 1:
    raise SystemExit("classic conversion dropped the layer")
layer_digest = manifest["layers"][0]["digest"].removeprefix("sha256:")
layer_blob = os.path.join(layout, "blobs", "sha256", layer_digest)
if hashlib.sha256(open(layer_blob, "rb").read()).hexdigest() != layer_digest:
    raise SystemExit("layer blob digest does not match manifest")
PY

mkdir -p "$work/oci/blobs/sha256"
printf '{"imageLayoutVersion":"1.0.0"}' >"$work/oci/oci-layout"
printf '{"schemaVersion":2,"manifests":[]}' >"$work/oci/index.json"
tar -cf "$work/oci.tar" -C "$work/oci" oci-layout index.json
python3 "$converter" "$work/oci.tar" "$work/oci-layout"
grep -F -q 'imageLayoutVersion' "$work/oci-layout/oci-layout" || fail "existing layout"
grep -F -q 'schemaVersion' "$work/oci-layout/index.json" || fail "existing index"

printf 'parent image layout tests passed\n'
