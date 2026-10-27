# syntax=docker/dockerfile:1
# dev-rust adds rustc, cargo, rustfmt, and clippy as one linked layer on
# dev-base. gcc and libc6-dev are the C linker cargo uses. There is no rustup.

ARG DEBIAN_IMAGE
# hadolint ignore=DL3006
FROM ${DEBIAN_IMAGE} AS archive_tools
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tar \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

FROM archive_tools AS toolchain
COPY versions/rust.env /tool/rust.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
COPY scripts/install_toolchain_tree.sh /tool/install_toolchain_tree.sh
COPY scripts/install_rust_toolchain.sh /tool/install_rust_toolchain.sh
RUN bash /tool/install_rust_toolchain.sh && rm -rf /tool

# hadolint ignore=DL3006
FROM development-base AS system_packages
# The parent image ends as the developer user. Package installation is root.
USER root
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc \
      libc6-dev \
 && rm -rf /var/lib/apt/lists/*

FROM system_packages AS dev_rust
COPY --link --from=toolchain /out/usr/local/ /usr/local/

ENV CARGO_HOME=/tmp/cargo

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-rust
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
