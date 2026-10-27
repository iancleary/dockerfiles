# syntax=docker/dockerfile:1
# dev-zig adds the Zig toolchain as one linked layer on dev-base.
# The build checks the tarball sha256 and the published minisign signature.

ARG DEBIAN_IMAGE
# hadolint ignore=DL3006
FROM ${DEBIAN_IMAGE} AS archive_tools
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      minisign \
      tar \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

FROM archive_tools AS toolchain
COPY versions/zig.env /tool/zig.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
COPY scripts/install_toolchain_tree.sh /tool/install_toolchain_tree.sh
COPY scripts/install_zig_toolchain.sh /tool/install_zig_toolchain.sh
RUN bash /tool/install_zig_toolchain.sh && rm -rf /tool

# hadolint ignore=DL3006
FROM development-base AS dev_zig
COPY --link --from=toolchain /out/usr/local/ /usr/local/

ENV ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache \
    ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-zig
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
