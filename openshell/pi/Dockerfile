# Pi on a shared OpenShell base. The default base is the agent-cli floor.
# Pass BASE_IMAGE=openshell-rust:phase1 (or python, or go) to stack a toolchain,
# and tag that build yourself. Node is installed here because Pi needs it.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
ARG PI_VERSION=1.4.0
ARG NODE_VERSION=24.22.1
COPY install-pi.sh /tmp/install-pi.sh
RUN PI_VERSION="$PI_VERSION" NODE_VERSION="$NODE_VERSION" \
    bash /tmp/install-pi.sh && rm -f /tmp/install-pi.sh

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp
# OpenShell drops image ENV on sandbox exec; callers pass it again.
ENV PI_CODING_AGENT_DIR=/tmp/pi-agent

ARG IMAGE_TITLE=openshell-pi
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

ENTRYPOINT ["pi"]
CMD ["--version"]
