# Shared floor for OpenShell sandbox images.
# fd, rg, and just are installed here so agents do not download them at runtime.
# Language toolchains and agent CLIs stay in later images.
# There is no separate common image. This layer is the shared base.
# The digest is the bookworm-slim multi-arch index. Renovate keeps the tag.

FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8

COPY common/install-agent-cli.sh common/versions.env /tmp/agent-cli/
RUN bash /tmp/agent-cli/install-agent-cli.sh && rm -rf /tmp/agent-cli

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
