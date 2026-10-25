# Claude Code on a shared OpenShell base. The binary name is `claude`.
# Default base is the agent-cli floor. No provider credentials.
# The build context is the openshell directory.
# The pin lives in versions/claude.env.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
COPY versions/claude.env claude/install-claude.sh /tmp/claude/
RUN bash /tmp/claude/install-claude.sh && rm -rf /tmp/claude

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
