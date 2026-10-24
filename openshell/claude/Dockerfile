# Claude Code on a shared OpenShell base. The binary name is `claude`.
# Default base is the agent-cli floor. No provider credentials.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
ARG CLAUDE_VERSION=2.1.309
COPY install-claude.sh /tmp/install-claude.sh
RUN CLAUDE_VERSION="$CLAUDE_VERSION" bash /tmp/install-claude.sh && rm -f /tmp/install-claude.sh

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp

ARG IMAGE_TITLE=openshell-claude
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

ENTRYPOINT ["claude"]
CMD ["--version"]
