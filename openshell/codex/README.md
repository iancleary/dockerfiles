# Codex image

Codex CLI layer on the OpenShell agent-cli image. The published name is
`ghcr.io/iancleary/openshell-codex`. A local `just openshell::codex` tags
`openshell-codex:phase1`.

The binary is `/usr/local/bin/codex`, from the official musl release. The
image has no provider credentials and does not log in. The consumer mounts
or uploads provider config when the sandbox starts.

From the repository root:

```sh
just openshell::codex
```

A language-stack base uses `BASE_IMAGE`:

```sh
docker build \
  -f openshell/codex/Dockerfile \
  --build-arg BASE_IMAGE=openshell-rust:phase1 \
  -t openshell-codex:rust \
  openshell
```

`BASE_IMAGE` can be a published digest, for example
`ghcr.io/iancleary/openshell-python@sha256:…`. Cache variables for a
language-stack base are in the [family README](../README.md).
