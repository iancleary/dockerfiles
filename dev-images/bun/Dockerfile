# syntax=docker/dockerfile:1
# dev-bun adds the Bun binary as one linked layer on dev-base.
# Node.js is not installed.

ARG DEBIAN_IMAGE
# hadolint ignore=DL3006
FROM ${DEBIAN_IMAGE} AS archive_tools
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
 && rm -rf /var/lib/apt/lists/*

FROM archive_tools AS toolchain
COPY versions/bun.env /tool/bun.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/bun.env \
      --key-prefix BUN \
      --destination-directory /out \
      --binary bun \
 && rm -rf /tool

# hadolint ignore=DL3006
FROM development-base AS dev_bun
COPY --link --from=toolchain /out/ /usr/local/bin/

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-bun
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
