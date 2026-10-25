# dockerfiles

Public container images for Ian Cleary, built here and published to GHCR.
One directory per image family. OpenShell is the first. A later family
(for example `devcontainers/`) is another directory plus a `mod` line in
the root [`justfile`](justfile).

| Family | Module | Images |
| --- | --- | --- |
| [openshell/](openshell/README.md) | `just openshell::…` | `ghcr.io/iancleary/openshell-<layer>` |

Local builds and CI call the same recipes. From the repository root, with
Docker already running:

```sh
just openshell::build
```

`just --list` shows families. `just --list --list-submodules` shows recipes.

## Pulling images

Images are multi-arch (`linux/amd64` and `linux/arm64`). There is no
`openshell-common` image. `openshell-agent-cli` is the shared base. The
harness images `openshell-pi`, `openshell-codex`, and `openshell-claude`
are published on that base. They replace the old local tags
`openshell-pi:phase1`, `openshell-codex:phase1`, and `openshell-claude:phase1`.

```sh
docker pull ghcr.io/iancleary/openshell-agent-cli:latest
docker pull ghcr.io/iancleary/openshell-python:latest
docker pull ghcr.io/iancleary/openshell-rust:latest
docker pull ghcr.io/iancleary/openshell-go:latest
docker pull ghcr.io/iancleary/openshell-pi:latest
docker pull ghcr.io/iancleary/openshell-codex:latest
docker pull ghcr.io/iancleary/openshell-claude:latest
```

These images are generic tool layers. Sandbox policy and provider
configuration are not in this repo. The consumer mounts or uploads its own
provider config when a sandbox starts.

| When | Git tag | Image tags |
| --- | --- | --- |
| Push to `main` that changes a family | none | `:edge` and `:sha-<7>` |
| Calver release | `openshell-YYYY.MM.DD.NN` | `:YYYY.MM.DD.NN` and `:latest` |

`:latest` is the release consumers should run. `:edge` is only the newest
push to `main`, so it does not move on the scheduled rebuild. A push outside
`openshell/` does not rebuild this family. Inside the family, only the
changed layer and its dependents rebuild. A change to `agent-cli` or
`common/` rebuilds every layer, in order, and each child receives the
parent manifest-list digest as `BASE_IMAGE`.

The first push to `main` publishes `:edge` and `:sha-<7>` only. It does not
create a calver git tag.

## Rebuild every 3 days

GitHub's cron cannot express "every 3 days". The OpenShell workflow runs
daily at 15:15 UTC and compares the calendar date in the newest
`openshell-YYYY.MM.DD.NN` tag with today. It rebuilds only when that date
is at least 3 days ago, or when no calver tag exists yet. The first
scheduled run after merge therefore publishes the first calver, because
there is no previous tag. The next one waits until that tag's date is 3
days old (a release dated the 24th rebuilds on the 27th). A month boundary
does not skip or bunch days.

That rebuild uses `docker build --pull --no-cache`, pushes a new calver and
`:latest`, and creates the git tag `openshell-YYYY.MM.DD.NN` only after
every image manifest succeeds. `.NN` starts at `01` and increments when more
than one release happens on the same UTC day. Actions → OpenShell images →
Run workflow → `release` cuts one without waiting. `edge` republishes
`:edge` and `:sha-<7>` for the current `main` commit.

## Supply chain

`openshell-agent-cli` pins `debian:bookworm-slim` by tag and digest.
Harness CLI versions are `ARG`s (`PI_VERSION`, `CODEX_VERSION`,
`CLAUDE_VERSION`). Shared toolchain versions live in
[`openshell/common/versions.env`](openshell/common/versions.env). Each image
records the git SHA, image version, parent digest, and those pins as OCI
labels, including `org.opencontainers.image.source`, which links the GHCR
package to this repo.

[Renovate](renovate.json) updates the Debian digest, the pinned versions,
and GitHub Action digests. Several pins are checked against a sha256 in
`versions.env` or the harness `install-*.sh`. A version bump without the
matching checksum fails the image build. Update both in the Renovate PR.
CPython stays on 3.13, because the Python install script is written for
that line. Pi's checksums are the linux archive lines from the
`earendil-works/pi` release `SHA256SUMS`.

Workflow runs attest the arch images and the manifest list with
`actions/attest-build-provenance` and sign them with keyless cosign
(GitHub OIDC). Verify with:

```sh
gh attestation verify oci://ghcr.io/iancleary/openshell-agent-cli:latest \
  --repo iancleary/dockerfiles
cosign verify ghcr.io/iancleary/openshell-agent-cli:latest \
  --certificate-identity-regexp 'https://github.com/iancleary/dockerfiles/.github/workflows/.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

Workflows authenticate to GHCR with the built-in `GITHUB_TOKEN` and
`packages: write`. No extra registry secret is required.

## One-time package setup

GitHub creates each package as private the first time it is pushed. After
the first successful run on `main`, set each package to public. That is
once per package, under package settings:

- [openshell-agent-cli](https://github.com/users/iancleary/packages/container/openshell-agent-cli/settings)
- [openshell-python](https://github.com/users/iancleary/packages/container/openshell-python/settings)
- [openshell-rust](https://github.com/users/iancleary/packages/container/openshell-rust/settings)
- [openshell-go](https://github.com/users/iancleary/packages/container/openshell-go/settings)
- [openshell-pi](https://github.com/users/iancleary/packages/container/openshell-pi/settings)
- [openshell-codex](https://github.com/users/iancleary/packages/container/openshell-codex/settings)
- [openshell-claude](https://github.com/users/iancleary/packages/container/openshell-claude/settings)

The source label should already connect the package to
`iancleary/dockerfiles`. If a package is unlinked, use Package settings →
Connect repository.

Also confirm Actions can grant the permissions the workflow requests
(Settings → Actions → General → Workflow permissions → Read and write).
The workflow file asks for `contents: write` on the release job,
`packages: write`, `id-token: write`, and `attestations: write`. A
repository maximum of read-only blocks those grants, and the publish fails.
Install the Renovate GitHub App on this repo so digest and version PRs open.
