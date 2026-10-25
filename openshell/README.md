# OpenShell images

Shared sandbox images and the harness layers that sit on them. Nothing here
starts Docker or a gateway. Build only while the daemon is already running.

These images are generic tool layers. Skills, credentials, and a host home
directory are not in them. The runtime sandbox policy is managed outside this
repo. Provider profiles are too. The consumer mounts or uploads its own
provider config when a sandbox starts.

There is no `openshell-common` image. `agent-cli` is the shared base.

## Published names

Multi-arch `linux/amd64` and `linux/arm64`. Pull instructions and the tag
rules live in the [repository README](../README.md).

| Image | Dockerfile | Base | What it adds |
| --- | --- | --- | --- |
| `ghcr.io/iancleary/openshell-agent-cli` | [`agent-cli/Dockerfile`](agent-cli/Dockerfile) | `debian:bookworm-slim` (digest-pinned) | `fd` 10.5.0, `rg` 15.2.0, `just` 1.59.0, user `agent` uid 1000 |
| `ghcr.io/iancleary/openshell-python` | [`python/Dockerfile`](python/Dockerfile) | agent-cli | `uv` 0.13.5, CPython 3.13.17, `pre-commit` 4.7.0 |
| `ghcr.io/iancleary/openshell-rust` | [`rust/Dockerfile`](rust/Dockerfile) | agent-cli | rustc/cargo 1.99.1, `gcc` |
| `ghcr.io/iancleary/openshell-go` | [`go/Dockerfile`](go/Dockerfile) | agent-cli | Go 1.27.3 |
| `ghcr.io/iancleary/openshell-pi` | [`pi/Dockerfile`](pi/Dockerfile) | agent-cli, overridable | Pi 1.4.0 |
| `ghcr.io/iancleary/openshell-codex` | [`codex/Dockerfile`](codex/Dockerfile) | agent-cli, overridable | Codex CLI 0.164.0 |
| `ghcr.io/iancleary/openshell-claude` | [`claude/Dockerfile`](claude/Dockerfile) | agent-cli, overridable | Claude Code 2.1.309 |

Harness Dockerfiles take `ARG BASE_IMAGE`. The default,
`openshell-agent-cli:phase1`, is the local tag so `just openshell::build`
works without GHCR. CI passes the published parent digest instead.
Published harness images use the agent-cli base. They replace the old local
tags `openshell-pi:phase1`, `openshell-codex:phase1`, and
`openshell-claude:phase1`.

Pins and checksums for the shared floor and the three stacks are in
[`common/versions.env`](common/versions.env). Harness versions are `ARG`s in
each harness Dockerfile. Bookworm's `fd-find` package is not used: it is
8.6.0, the binary is `fdfind`, and it has no `--no-require-git`.

`pre-commit` is only on the Python image. It runs hooks with CPython. The
Rust and Go images stay free of that interpreter.

## Local build

From the repository root, with Docker already running:

```sh
just openshell::build
```

`just openshell` lists the recipes. `just --list` shows this module, and
`just --list --list-submodules` shows the recipes from the root. `build` is
`all`: the shared floor and the three default harness tags. Images stay on
this machine, tagged `openshell-<layer>:phase1`.

| Recipe | What it builds |
| --- | --- |
| `openshell::stacks` | agent-cli, python, rust, and go, by calling [`build.sh`](build.sh) |
| `openshell::agent-cli` | `openshell-agent-cli:phase1` |
| `openshell::python` | `openshell-python:phase1` after agent-cli |
| `openshell::rust` | `openshell-rust:phase1` after agent-cli |
| `openshell::go` | `openshell-go:phase1` after agent-cli |
| `openshell::pi` | `openshell-pi:phase1` after agent-cli |
| `openshell::codex` | `openshell-codex:phase1` after agent-cli |
| `openshell::claude` | `openshell-claude:phase1` after agent-cli |
| `openshell::pi-rust` | local-only `openshell-pi:rust` on `openshell-rust:phase1` |
| `openshell::build` | `stacks`, then pi, codex, and claude |
| `openshell::all` | same as `build` |

`bash openshell/build.sh` builds only the shared floor. `build.sh` and these
recipes build when Docker is already running. They do not start it.

`just openshell::pi-rust` is this build, and it is not published:

```sh
docker build \
  -f openshell/pi/Dockerfile \
  --build-arg BASE_IMAGE=openshell-rust:phase1 \
  -t openshell-pi:rust \
  openshell/pi
```

The same `--build-arg` works for the Codex and Claude Dockerfiles. Example
local tags: `openshell-codex:python`, `openshell-claude:go`. `BASE_IMAGE`
can also be a published digest, for example
`ghcr.io/iancleary/openshell-rust@sha256:…`.

CI calls the same recipes (`just openshell::agent-cli`, and so on). It sets
`OPENSHELL_BASE_IMAGE` and `OPENSHELL_BASE_DIGEST` so a child does not
rebuild its parent, and `OPENSHELL_BUILD_FLAGS` for the native-arch
digest push.

## What a harness image contains

| Image | Binary |
| --- | --- |
| pi | `/usr/local/bin/pi` (symlink to `/usr/local/lib/pi/pi`) |
| codex | `/usr/local/bin/codex` |
| claude | `/usr/local/bin/claude` |

OpenShell drops image `ENV` on `sandbox exec`. Pass `PI_CODING_AGENT_DIR`
again on exec. The image default is `/tmp/pi-agent`. Callers may pass a
different directory.

A language stack also needs its cache directory on exec, because a sandbox
policy often allows writes under `/tmp` only:

| Stack | Pass on exec |
| --- | --- |
| python | `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python`, `UV_TOOL_DIR=/usr/local/share/uv/tools`, `UV_CACHE_DIR=/tmp/uv-cache` |
| rust | `CARGO_HOME=/tmp/cargo` |
| go | `GOPATH=/tmp/go`, `GOCACHE=/tmp/gocache`, `GOMODCACHE=/tmp/go/pkg/mod`, `CGO_ENABLED=0` |

An existing sandbox keeps the image it was created from. After a rebuild,
delete that sandbox and create it again.
