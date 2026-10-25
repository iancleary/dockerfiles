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
| `ghcr.io/iancleary/openshell-agent-cli` | [`agent-cli/Dockerfile`](agent-cli/Dockerfile) | `debian:bookworm-slim` from [`versions/base.env`](versions/base.env) | `fd`, `rg`, `just` from [`versions/tools.env`](versions/tools.env), user `agent` uid 1000 |
| `ghcr.io/iancleary/openshell-python` | [`python/Dockerfile`](python/Dockerfile) | agent-cli | `uv`, CPython, `pre-commit` from [`versions/python.env`](versions/python.env) |
| `ghcr.io/iancleary/openshell-rust` | [`rust/Dockerfile`](rust/Dockerfile) | agent-cli | rustc/cargo from [`versions/rust.env`](versions/rust.env), `gcc` |
| `ghcr.io/iancleary/openshell-go` | [`go/Dockerfile`](go/Dockerfile) | agent-cli | Go from [`versions/go.env`](versions/go.env) |
| `ghcr.io/iancleary/openshell-pi` | [`pi/Dockerfile`](pi/Dockerfile) | agent-cli, overridable | Pi from [`versions/pi.env`](versions/pi.env) |
| `ghcr.io/iancleary/openshell-codex` | [`codex/Dockerfile`](codex/Dockerfile) | agent-cli, overridable | Codex CLI from [`versions/codex.env`](versions/codex.env) |
| `ghcr.io/iancleary/openshell-claude` | [`claude/Dockerfile`](claude/Dockerfile) | agent-cli, overridable | Claude Code from [`versions/claude.env`](versions/claude.env) |

Harness Dockerfiles take `ARG BASE_IMAGE`. The default,
`openshell-agent-cli:phase1`, is the local tag so `just openshell::build`
works without GHCR. CI passes the published parent digest instead.
Published harness images use the agent-cli base. They replace the old local
tags `openshell-pi:phase1`, `openshell-codex:phase1`, and
`openshell-claude:phase1`.

Every tool version, checksum, and the Debian base digest lives in
[`versions/`](versions/). The weekly bump edits those files and the pinned
GitHub Actions. It leaves this README alone, so the table names the file
that holds each pin. Bookworm's `fd-find` package is 8.6.0, the binary is
`fdfind`, and it has no `--no-require-git`, so the image installs the
upstream `fd` release instead.

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
  openshell
```

The same `--build-arg` works for the Codex and Claude Dockerfiles. Example
local tags: `openshell-codex:python`, `openshell-claude:go`. `BASE_IMAGE`
can also be a published digest, for example
`ghcr.io/iancleary/openshell-rust@sha256:…`.

CI calls the same recipes (`just openshell::agent-cli`, and so on). It sets
`OPENSHELL_BASE_IMAGE` and `OPENSHELL_BASE_DIGEST` so a child does not
rebuild its parent, and `OPENSHELL_BUILD_FLAGS` for the native-arch
digest push. The weekly bump's verify job does not set
`OPENSHELL_BASE_IMAGE`. `just openshell::all` builds the floor with
`build.sh`, then Pi, Codex, and Claude. Those recipes, and `python`,
`rust`, and `go` when run on their own, build agent-cli from this
module's justfile. `justfile()` would point at the root justfile, which
has no `agent-cli` recipe.

The build context for every OpenShell Dockerfile is the `openshell/`
directory. `versions/*.env` has to be in that context. `docker-build.sh`
reads the same files and passes `DEBIAN_IMAGE` for the agent-cli base.

## Version files

| File | Keys |
| --- | --- |
| [`versions/base.env`](versions/base.env) | `DEBIAN_IMAGE` (`debian:bookworm-slim` by digest) |
| [`versions/tools.env`](versions/tools.env) | `fd`, `rg`, `just` and both architectures' sha256 |
| [`versions/python.env`](versions/python.env) | `uv` and sha256, CPython, `pre-commit` |
| [`versions/rust.env`](versions/rust.env) | rustc/cargo/rust-std version and sha256 |
| [`versions/go.env`](versions/go.env) | Go version and sha256 |
| [`versions/pi.env`](versions/pi.env) | Pi version and sha256 |
| [`versions/codex.env`](versions/codex.env) | Codex version and sha256 |
| [`versions/claude.env`](versions/claude.env) | Claude Code version and sha256 |

Install scripts source the file copied next to them. Rust archives are the
dateless `static.rust-lang.org/dist/<component>-<version>-<triple>.tar.xz`
files. The channel manifest still has a dist date; the install ignores it.
Pi is the `pi-linux-*.tar.gz` tree from
[earendil-works/pi](https://github.com/earendil-works/pi) releases, installed
under `/usr/local/lib/pi` with `/usr/local/bin/pi` pointing at it. The image
does not install Node. CPython and `pre-commit` are installed by `uv`, which checks
those downloads, so only their versions are pinned.

Refresh the pins from upstream with:

```sh
bash openshell/scripts/bump-versions.sh --check
bash openshell/scripts/bump-versions.sh
```

`--check` prints each bump and exits 1 when a file would change. It leaves
the tree as it is. The other form rewrites `versions/` and the Action pins
under `.github/workflows/`. Either form exits 2 when an upstream asset,
checksum, or digest is missing or does not match the downloaded bytes.
`GITHUB_TOKEN` or `gh auth token` raises the GitHub API rate limit.
`OPENSHELL_BUMP_CACHE` can point at a directory for downloaded artifacts.

The release line is patch-only inside the pin that is already in the file:

| Line | Tools | What moves |
| --- | --- | --- |
| minor | `fd`, `rg`, `just`, CPython, `pre-commit`, Rust, Go, Pi, Claude Code, and any other 1.x pin | Newest `major.minor.patch` on the pinned `major.minor` |
| zero | `uv`, Codex | Newest stable `0.x.y`. Routine releases move the middle number. Prereleases are skipped |

A Rust train, a Go minor, or a Pi minor stays put until someone edits that
component in the version file. The next run then follows patches on the new
line. Action pins stay on the same major (`v7` stays `v7`) and the commit
SHA is updated with the tag comment. The `cosign-release` input is a cosign
version, separate from the Action pin, and this script leaves it alone.

## Weekly bump and the release gate

[`.github/workflows/openshell-bump.yml`](../.github/workflows/openshell-bump.yml)
runs Mondays at 16:00 UTC (09:00 America/Phoenix, which stays UTC-7).
Actions → OpenShell version bump → Run workflow starts the same jobs.
The cron is UTC and GitHub can start it late.

The bump job rewrites the pins. When files change, `just openshell::all`
builds every image on `ubuntu-24.04` and `ubuntu-24.04-arm`. That build
does not log in and does not push. When both builds pass, the workflow
commits to `main` as `github-actions[bot]`. One bump uses that bump as the
commit message (`bump claude 2.1.309 -> 2.1.310`). Several bumps use the
subject `bump openshell versions` and list the rest in the body. A failed
build commits nothing and opens or updates one issue titled
`OpenShell version bump failed`.

A token push does not start the image workflow, so the same job then
dispatches OpenShell images with `publish=release`. That dispatch releases
even when the newest calver is under three days old. `:edge` stays on the
last push that the image workflow actually ran; the bot commit does not
move it. `:latest` moves when the release finishes.

The daily image cron is 15:15 UTC (08:15 America/Phoenix). It still cannot
say "every 3 days", so it runs every day and
[`plan.sh`](scripts/plan.sh) decides. A scheduled run releases when there
is no `openshell-YYYY.MM.DD.NN` tag yet, when the newest tag is at least
30 days old (`OPENSHELL_FORCE_AGE_DAYS`), or when the tag is at least 3
days old (`OPENSHELL_MIN_AGE_DAYS`) and a release input changed since the
tag. Release inputs are files under `openshell/`, the root `justfile`, and
the two image workflows. Age is calendar days in the tag name. A manual
`release` dispatch, including the one from the bump workflow, skips both
gates. `edge` republishes `:edge` and `:sha-<7>`.

The Monday bump is scheduled after that daily plan so the two jobs do not
choose a calver at the same moment. They still share nothing but the image
workflow's own queue: the bump uses a separate concurrency group, because
the dispatch would wait forever if this workflow held the image group.

GitHub turns scheduled workflows off on a public repo after 60 days without
repository activity. A commit on the default branch is the activity that
keeps the schedule. The weekly bump supplies that commit when a pin moves.
The 30-day image rebuild creates a tag and a GitHub Release, and it does
not by itself add a commit, so do not count on it to reset the 60 days.
Debian's bookworm-slim digest moves often enough that the Monday run
usually commits. If Actions has disabled the workflow, re-enable it from
the Actions tab. The bump workflow's `contents: write` push also needs
Workflow permissions set to read and write, and a ruleset that lets
`github-actions[bot]` push to `main`.

## What a harness image contains

| Image | Binary |
| --- | --- |
| pi | `/usr/local/bin/pi` |
| codex | `/usr/local/bin/codex` |
| claude | `/usr/local/bin/claude` |

Pi, Codex, and Claude are each the upstream release binary. The images do not install Node, npm, or npx, and they do not bake an MCP server. Pi packages and extensions that need npm dependencies are not supported until Node is added back. `pi install npm:` and `pi install git:` will not work. A local TypeScript file passed with `pi -e` still loads, because those modules are built into the Pi binary. The smoke test uses that path.

## Smoke tests

`just openshell::all` builds the images and then runs these. Each one can also be run on its own. They use the local tag from the build (`openshell-pi:phase1`, and the same for Codex and Claude). CI loads each harness image, runs this same script, and only then pushes that image by digest. The push replays the build from the builder cache and refuses to continue unless the pushed config digest is the image that was smoked. A failed smoke test pushes nothing. The non-harness images have no smoke step and still push by digest from the build.

```sh
just openshell::smoke-pi
just openshell::smoke-codex
just openshell::smoke-claude
```

The Pi check mounts [`pi/smoke/extension.ts`](pi/smoke/extension.ts) into a throwaway container (`docker run --rm --network none`). That file is the only fixture. `pi/smoke` is in the build's dockerignore, and the Dockerfile does not copy it, so it is not in the published image. Pi 1.4.0 gives extensions `@earendil-works/pi-coding-agent` and `typebox` (see the upstream `docs/packages.md` shipped in that release). The fixture reads `VERSION` from `@earendil-works/pi-coding-agent` and builds a TypeBox object. Those modules are built into the Pi binary, so the fixture does not call Node, npm, or npx. A type-only import is not enough: Pi still exits 0 from `--help` when an import fails, and it omits the flag. The container runs:

```sh
pi --offline --no-extensions -e /smoke/extension.ts --help
```

`--help` exits without a model call. A loaded extension prints its flag there. The test fails unless the output contains `--openshell-smoke` and `OPENSHELL_PI_EXTENSION_OK`. No API key is passed in.

Codex and Claude have no check of that kind that stays offline and credential-free. Their smoke test is `--version`, and the output has to contain the version in `versions/codex.env` or `versions/claude.env`. The container has `--network none` for all three.

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
