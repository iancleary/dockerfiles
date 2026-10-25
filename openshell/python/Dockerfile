# Python stack. uv and CPython only. pre-commit is here because it runs with CPython.
# Rust and Go images do not include it.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
COPY common/harden-runtime.sh versions/python.env versions/pre-commit-requirements.txt python/install-python.sh /tmp/stack/
RUN bash /tmp/stack/install-python.sh && rm -rf /tmp/stack

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp
# OpenShell drops image ENV on sandbox exec, so pass these again on exec.
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python
ENV UV_TOOL_DIR=/usr/local/share/uv/tools
ENV UV_CACHE_DIR=/tmp/uv-cache
ENV PRE_COMMIT_HOME=/tmp/pre-commit

ARG IMAGE_TITLE=openshell-python
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
      io.iancleary.openshell.versions="${TOOL_VERSIONS}"
