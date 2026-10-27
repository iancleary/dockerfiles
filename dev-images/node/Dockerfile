# syntax=docker/dockerfile:1
# dev-node adds the Node.js LTS archive and a separate pnpm layer on dev-base.
# corepack is not installed. pnpm is the checksummed release binary.

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

FROM archive_tools AS toolchain_node
COPY versions/node.env /tool/node.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
COPY scripts/install_toolchain_tree.sh /tool/install_toolchain_tree.sh
COPY scripts/install_node_toolchain.sh /tool/install_node_toolchain.sh
RUN bash /tool/install_node_toolchain.sh && rm -rf /tool

FROM archive_tools AS toolchain_pnpm
COPY versions/pnpm.env /tool/pnpm.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/pnpm.env \
      --key-prefix PNPM \
      --destination-directory /out \
      --binary pnpm \
 && rm -rf /tool

# hadolint ignore=DL3006
FROM development-base AS dev_node
COPY --link --from=toolchain_node /out/usr/local/ /usr/local/
COPY --link --from=toolchain_pnpm /out/ /usr/local/bin/

ENV COREPACK_ENABLE_NETWORK=0

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-node
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
