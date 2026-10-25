# Shared floor for OpenShell sandbox images.
# fd, rg, and just are installed here so agents do not download them at runtime.
# Language toolchains and agent CLIs stay in later images.
# There is no separate common image. This layer is the shared base.
# The base pin is versions/base.env. docker-build.sh passes DEBIAN_IMAGE.

ARG DEBIAN_IMAGE
# hadolint ignore=DL3006
FROM ${DEBIAN_IMAGE}

COPY common/harden-runtime.sh common/install-agent-cli.sh versions/tools.env /tmp/agent-cli/
RUN bash /tmp/agent-cli/install-agent-cli.sh && rm -rf /tmp/agent-cli

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp

ARG IMAGE_TITLE=openshell-agent-cli
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
