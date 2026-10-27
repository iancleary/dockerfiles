# syntax=docker/dockerfile:1
# dev-go adds the Go toolchain as one linked layer on dev-base.
# The parent is the named build context development-base.

ARG DEBIAN_IMAGE
# hadolint ignore=DL3006
FROM ${DEBIAN_IMAGE} AS archive_tools
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tar \
 && rm -rf /var/lib/apt/lists/*

FROM archive_tools AS toolchain
COPY versions/go.env /tool/go.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
COPY scripts/install_toolchain_tree.sh /tool/install_toolchain_tree.sh
COPY scripts/install_go_toolchain.sh /tool/install_go_toolchain.sh
RUN bash /tool/install_go_toolchain.sh && rm -rf /tool

# hadolint ignore=DL3006
FROM development-base AS dev_go
COPY --link --from=toolchain /out/usr/local/ /usr/local/

ENV GOTOOLCHAIN=local \
    CGO_ENABLED=0 \
    GOCACHE=/tmp/go-build-cache \
    GOPATH=/tmp/go \
    GOMODCACHE=/tmp/go/pkg/mod

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-go
ARG GIT_SHA=unknown
ARG IMAGE_VERSION=local
ARG BASE_DIGEST=unknown
ARG TOOL_VERSIONS=unknown
LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
      org.opencontainers.image.source="https://github.com/iancleary/dockerfiles" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}" \
      io.iancleary.dev-images.versions="${TOOL_VERSIONS}"
