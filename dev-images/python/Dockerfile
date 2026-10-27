# syntax=docker/dockerfile:1
# dev-python runs `uv python install` with the uv already in dev-base.
# versions/python.env supplies the exact archive and sha256. uv checks that
# sha256. The interpreter is one layer at /opt/python, owned by developer.

# hadolint ignore=DL3006
FROM development-base AS dev_python
USER root
RUN --mount=type=bind,source=.,target=/src,ro \
    PYTHON_VERSION_FILE=/src/versions/python.env \
    bash /src/scripts/install_python_with_uv.sh

ENV UV_PYTHON_INSTALL_DIR=/opt/python \
    PATH="/opt/python/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
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
