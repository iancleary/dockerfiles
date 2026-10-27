#!/usr/bin/env python3
"""Write an OCI image layout from a docker save archive.

The container Buildx driver cannot read an image tag from the engine store.
A language image build saves the loaded dev-base image and passes this layout
as the development-base context. A save that is already an OCI layout is
extracted. A classic docker save is converted.
"""

import hashlib
import json
import os
import sys
import tarfile
import tempfile


def extract_archive(archive_path, destination):
    with tarfile.open(archive_path) as archive:
        names = archive.getnames()
        if hasattr(tarfile, "data_filter"):
            archive.extractall(destination, filter="data")
        else:
            archive.extractall(destination)
    return names


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_bytes(directory, payload):
    digest = hashlib.sha256(payload).hexdigest()
    destination = os.path.join(directory, digest)
    with open(destination, "wb") as output:
        output.write(payload)
    return digest, len(payload)


def copy_blob(source_path, blob_directory):
    temporary = os.path.join(blob_directory, "partial")
    digest = hashlib.sha256()
    with open(source_path, "rb") as source, open(temporary, "wb") as output:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
            output.write(chunk)
    hex_digest = digest.hexdigest()
    size = os.path.getsize(temporary)
    os.replace(temporary, os.path.join(blob_directory, hex_digest))
    return hex_digest, size


def layer_media_type(path):
    with open(path, "rb") as source:
        magic = source.read(2)
    if magic == b"\x1f\x8b":
        return "application/vnd.oci.image.layer.v1.tar+gzip"
    return "application/vnd.oci.image.layer.v1.tar"


def convert_classic_save(extracted, layout):
    manifest_path = os.path.join(extracted, "manifest.json")
    with open(manifest_path, encoding="utf-8") as source:
        manifests = json.load(source)
    if not isinstance(manifests, list) or len(manifests) != 1:
        raise SystemExit("docker save archive must contain one image")
    item = manifests[0]
    blob_directory = os.path.join(layout, "blobs", "sha256")
    os.makedirs(blob_directory, exist_ok=True)

    config_path = os.path.join(extracted, item["Config"])
    config_digest, config_size = copy_blob(config_path, blob_directory)
    layers = []
    for layer_name in item["Layers"]:
        layer_path = os.path.join(extracted, layer_name)
        layer_digest, layer_size = copy_blob(layer_path, blob_directory)
        layers.append(
            {
                "mediaType": layer_media_type(layer_path),
                "digest": "sha256:" + layer_digest,
                "size": layer_size,
            }
        )

    image_manifest = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": "sha256:" + config_digest,
            "size": config_size,
        },
        "layers": layers,
    }
    manifest_payload = json.dumps(image_manifest, separators=(",", ":")).encode("utf-8")
    manifest_digest, manifest_size = write_bytes(blob_directory, manifest_payload)
    index = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.index.v1+json",
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": "sha256:" + manifest_digest,
                "size": manifest_size,
                "annotations": {"org.opencontainers.image.ref.name": "latest"},
            }
        ],
    }
    with open(os.path.join(layout, "index.json"), "w", encoding="utf-8") as output:
        json.dump(index, output, separators=(",", ":"))
    with open(os.path.join(layout, "oci-layout"), "w", encoding="utf-8") as output:
        json.dump({"imageLayoutVersion": "1.0.0"}, output, separators=(",", ":"))


def prepare_layout(archive_path, layout):
    os.makedirs(layout, exist_ok=True)
    with tempfile.TemporaryDirectory() as extracted:
        names = extract_archive(archive_path, extracted)
        if "oci-layout" in names and "index.json" in names:
            extract_archive(archive_path, layout)
            return
        if "manifest.json" not in names:
            raise SystemExit("docker save archive has no image manifest")
        convert_classic_save(extracted, layout)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare_parent_image_layout.py ARCHIVE LAYOUT")
    prepare_layout(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
