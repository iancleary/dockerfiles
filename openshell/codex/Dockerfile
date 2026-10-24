# Codex CLI on a shared OpenShell base. Default base is the agent-cli floor.
# The binary is the official musl release, not installers on the host.
# No provider credentials.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
ARG CODEX_VERSION=0.164.0
COPY install-codex.sh /tmp/install-codex.sh
RUN CODEX_VERSION="$CODEX_VERSION" bash /tmp/install-codex.sh && rm -f /tmp/install-codex.sh

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp

ARG IMAGE_TITLE=openshell-codex
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

ENTRYPOINT ["codex"]
CMD ["--version"]
