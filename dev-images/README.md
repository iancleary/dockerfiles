# Development images

One portable development environment, published as multi-arch container
images. This phase publishes `dev-base` only. Language images, agent
command-line programs, and compose files are later phases.

The image holds tools. It does not hold secrets, credentials, or personal
configuration. Those are mounted by the consumer when a container starts.

## Published name

`ghcr.io/iancleary/dev-base` is `linux/amd64` and `linux/arm64`.

| Image | Dockerfile | Base | What it adds |
| --- | --- | --- | --- |
| `ghcr.io/iancleary/dev-base` | [`base/Dockerfile`](base/Dockerfile) | `debian:bookworm-slim` from [`versions/debian.env`](versions/debian.env) | apt packages, user `developer` uid 1000, one linked layer per pinned tool |

The Debian digest starts equal to [`openshell/versions/base.env`](../openshell/versions/base.env).
The weekly update rewrites `versions/debian.env` when the bookworm-slim
index changes. It does not rewrite the OpenShell pin.

Apt packages, installed on every release build and not version-pinned:
`ca-certificates`, `direnv`, `git`, `git-lfs`, `openssh-client`, `tmux`,
`zsh`. There is no sudo. The login shell is `/bin/zsh`. There is no shell
theme and no personal startup file.

Pinned tools, one `COPY --link` layer each, from
[`versions/`](versions/):

| Tool | Command | Version file |
| --- | --- | --- |
| jq | `jq` | `jq.env` |
| ripgrep | `rg` | `ripgrep.env` |
| fd | `fd` | `fd.env` |
| ShellCheck | `shellcheck` | `shellcheck.env` |
| just | `just` | `just.env` |
| GitHub CLI | `gh` | `gh.env` |
| uv | `uv`, `uvx` | `uv.env` |
| bat | `bat` | `bat.env` |
| eza | `eza` | `eza.env` |
| zoxide | `zoxide` | `zoxide.env` |
| fzf | `fzf` | `fzf.env` |
| delta | `delta` | `delta.env` |
| lazygit | `lazygit` | `lazygit.env` |
| gum | `gum` | `gum.env` |
| ast-grep | `ast-grep` | `ast-grep.env` |
| ahi | `ahi` | `ahi.env` |

eza and delta use the gnu archives on both architectures because the arm64
releases have no musl build. The Debian base provides glibc. ast-grep's
release zip also contains a deprecated `sg` shim that does not run; the
image installs `ast-grep` only.

Not in this image: Node, Go, Rust, CPython, Claude, Codex, Nix, Neovim,
mise, age, sops, and powerlevel10k.

## Version files

Each tool file records:

| Key | Meaning |
| --- | --- |
| `<TOOL>_VERSION` | Stable version, without a `v` prefix |
| `<TOOL>_ARCHIVE_URL_AMD64` | Recorded https URL. The build does not derive it |
| `<TOOL>_ARCHIVE_URL_ARM64` | Recorded https URL |
| `<TOOL>_SHA256_AMD64` | sha256 of the downloaded archive or raw file |
| `<TOOL>_SHA256_ARM64` | sha256 of the downloaded archive or raw file |
| `<TOOL>_CHECKSUM_SOURCE` | `upstream_shared_file:<name>`, `upstream_sidecar`, or `github_release_asset_digest` |

`debian.env` records `DEBIAN_IMAGE` and `DEBIAN_CHECKSUM_SOURCE`. A tool
with no upstream checksum file uses the GitHub asset digest. The update
script refuses the pin when a published checksum and the GitHub digest
disagree, and it checks a GitHub artifact attestation when the release
has one.

## Local build

From the repository root, with Docker Buildx already available:

```sh
just dev-images::all
```

That builds `dev-base:local` and smoke-tests it as `developer`. The smoke
test disables the network. Each pinned command must report the recorded
version. `ahi --version` must print `ahi` and the recorded version. The
account must be uid 1000, sudo must be absent, and no setuid file may remain.

`just dev-images` lists the recipes. `base` builds. `smoke-base` builds
and smoke-tests. `all` is `smoke-base`.

## Tags

| When | Git tag | Image tags |
| --- | --- | --- |
| Push to `main` that changes this family | none | `:edge` and `:sha-<7>` |
| Calver release | `dev-images-YYYY.MM.DD.NN` | `:YYYY.MM.DD.NN` and `:latest` |

`:latest` and the calver tag are applied only after the manifest succeeds.
A failed build does not move them. `:edge` is the newest push that the
publish workflow ran. The version-update commit uses `GITHUB_TOKEN`, which
does not start other workflows, so that workflow dispatches a release.

The publish workflow runs daily at 15:45 UTC (08:45 America/Phoenix). It
releases when no calver tag exists yet, when the newest tag is at least 30
days old, or when the tag is at least 3 days old and a release input has
changed. Release inputs are files under `dev-images/`, the root `justfile`,
and the workflows that build the image. `.NN` starts at `01`. Actions →
Publish dev images → Run workflow → `release` cuts one without the age
check. `edge` republishes `:edge` and `:sha-<7>`.

## Pinned version update

Monday 13:30 UTC (06:30 America/Phoenix), thirty minutes after the OpenShell
update. The policy is `latest_stable`: the newest stable release across
minor and major versions. Prereleases are skipped. A downgrade is refused.
The verify job builds and smoke-tests both architectures and does not push.
The publish job fetches `main`, rebases, and retries the push, then
dispatches a release. Toolchains are not tracked.

```sh
bash dev-images/scripts/update_pinned_versions.sh --check
bash dev-images/scripts/update_pinned_versions.sh
```

`--check` prints each update and exits 1 when a file would change. It
leaves the tree as it is.

## Supply chain

The image build reads recorded URLs and sha256 values
([`scripts/install_release_archive.sh`](scripts/install_release_archive.sh)).
The registry export rewrites layer timestamps to the Unix epoch
(`SOURCE_DATE_EPOCH=0`). A `COPY --link` layer digest then follows that
tool's bytes and fixed metadata. A local load uses the same rewrite by
loading the exported tarball. The docker exporter cannot rewrite timestamps
and unpack in one step.
[`scripts/scan_for_personal_data.sh`](scripts/scan_for_personal_data.sh)
rejects private-source markers in this tree. Workflow runs attest each
architecture image and the manifest list with
`actions/attest-build-provenance` and sign them with keyless cosign.

```sh
gh attestation verify oci://ghcr.io/iancleary/dev-base:latest \
  --repo iancleary/dockerfiles
cosign verify ghcr.io/iancleary/dev-base:latest \
  --certificate-identity-regexp 'https://github.com/iancleary/dockerfiles/.github/workflows/.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

GitHub creates the package as private the first time it is pushed. After
the first successful run on `main`, set
[dev-base](https://github.com/users/iancleary/packages/container/dev-base/settings)
to public and connect it to this repository if it is not already linked.
