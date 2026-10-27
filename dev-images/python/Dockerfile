# syntax=docker/dockerfile:1
# dev-python adds one CPython tree on dev-base. The bytes are the
# python-build-standalone install_only_stripped archive. uv is already in
# dev-base and is not installed again.

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
COPY versions/python.env /tool/python.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
COPY scripts/install_toolchain_tree.sh /tool/install_toolchain_tree.sh
COPY scripts/install_python_toolchain.sh /tool/install_python_toolchain.sh
RUN bash /tool/install_python_toolchain.sh && rm -rf /tool

# hadolint ignore=DL3006
FROM development-base AS dev_python
COPY --link --from=toolchain /out/usr/local/ /usr/local/

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX=/tmp/python-cache

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-python
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
