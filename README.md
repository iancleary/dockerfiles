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

`:latest` is the release consumers should run. `:edge` is the newest push
that the image workflow ran. A scheduled rebuild does not move it, and
neither does the version-bump commit: that push uses `GITHUB_TOKEN`, which
does not start other workflows. A push outside `openshell/` does not rebuild
this family. Inside the family, only the changed layer and its dependents
rebuild. A change to `agent-cli`, `common/`, or
`openshell/versions/base.env` / `tools.env` rebuilds every layer, in order,
and each child receives the parent manifest-list digest as `BASE_IMAGE`.

The first push to `main` publishes `:edge` and `:sha-<7>` only. It does not
create a calver git tag.

## Rebuild every 3 days

GitHub's cron cannot express "every 3 days". The OpenShell workflow runs
daily at 15:15 UTC and compares the calendar date in the newest
`openshell-YYYY.MM.DD.NN` tag with today. It releases when no calver tag
exists yet, when that tag is at least 30 days old, or when the tag is at
least 3 days old and a release input has changed since the tag. Release
inputs are files under `openshell/`, the root `justfile`, and the workflows
that build the images. The first scheduled run on a repo with no calver tag
publishes one. After that, a release dated the 24th can go out on the 27th
when something under `openshell/` changed, and an unchanged tree waits.
A month boundary does not skip or bunch days. The 30-day run is the
security rebuild for a tree that stayed still.

That rebuild uses `docker build --pull --no-cache`, pushes a new calver and
`:latest`, and creates the git tag `openshell-YYYY.MM.DD.NN` only after
every image manifest succeeds. `.NN` starts at `01` and increments when more
than one release happens on the same UTC day. Actions → OpenShell images →
Run workflow → `release` cuts one without waiting for the age or the change
check. The weekly version bump dispatches that same input after it commits.
`edge` republishes `:edge` and `:sha-<7>` for the current `main` commit.

## Supply chain

Versions and checksums live in [`openshell/versions/`](openshell/versions/).
`openshell-agent-cli` pins `debian:bookworm-slim` by digest in
`base.env`. Each image records the git SHA, image version, parent digest,
and those pins as OCI labels, including `org.opencontainers.image.source`,
which links the GHCR package to this repo.

[`openshell/scripts/bump-versions.sh`](openshell/scripts/bump-versions.sh)
asks upstream for the newest release on the current line, rewrites the
version and both architectures' checksums, and checks the download. The
Monday workflow runs that script, builds every image without pushing, and
commits to `main` only when the builds pass. Details, the release lines,
and the 60-day schedule caveat are in the
[OpenShell README](openshell/README.md). Node stays on 24. CPython stays
on 3.13. Rust, Go, and Pi stay on the pinned minor until that number is
edited by hand.

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

Confirm Actions can grant the permissions the workflows request
(Settings → Actions → General → Workflow permissions → Read and write).
The image workflow asks for `contents: write` on the release job,
`packages: write`, `id-token: write`, and `attestations: write`. The
version-bump workflow asks for `contents: write` and `actions: write` on
the publish job, and `issues: write` when a run fails. A repository
maximum of read-only blocks those grants.

The bump commits straight to `main`. A ruleset that requires a pull request,
or that blocks `github-actions[bot]`, stops that push. Allow that actor to
push to `main`.

Uninstall the Renovate GitHub App from this repo. Version and digest bumps
are the workflow above, and `renovate.json` is gone.
