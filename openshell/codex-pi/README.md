# Codex and Pi image

Codex CLI and Pi together on the OpenShell agent-cli image, the same base
as the Codex harness. The published name is
`ghcr.io/iancleary/openshell-codex-pi`. A local `just openshell::codex-pi`
tags `openshell-codex-pi:phase1`.

`/usr/local/bin/codex` is the official musl release, installed by
[`../codex/install-codex.sh`](../codex/install-codex.sh). `/usr/local/bin/pi`
is the pinned standalone tree from earendil-works/pi, installed by
[`../pi/install-pi.sh`](../pi/install-pi.sh). This image does not carry a
second copy of either installer. The pins stay in
[`../versions/codex.env`](../versions/codex.env) and
[`../versions/pi.env`](../versions/pi.env).

`fd` and `rg` come from the agent-cli base, the same binaries the Pi image
uses. The install scripts add `curl` only for the download and then purge
it. The image does not install Node, npm, or xz.

The image has no provider credentials and does not log in. The consumer
mounts or uploads provider config when the sandbox starts.

Both binaries are on `PATH`. There is no `ENTRYPOINT`. `docker run` with
no arguments prints the Codex version.

From the repository root:

```sh
just openshell::codex-pi
```

A language-stack base uses `BASE_IMAGE`:

```sh
docker build \
  -f openshell/codex-pi/Dockerfile \
  --build-arg BASE_IMAGE=openshell-rust:phase1 \
  -t openshell-codex-pi:rust \
  openshell
```

`BASE_IMAGE` can be a published digest, for example
`ghcr.io/iancleary/openshell-python@sha256:…`. Cache variables for a
language-stack base are in the [family README](../README.md).
