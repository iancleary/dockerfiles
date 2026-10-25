# Codex CLI and Pi on the shared OpenShell base. The default base is the
# agent-cli floor, the same base as the Codex harness. Codex is installed
# by codex/install-codex.sh. Pi is installed by pi/install-pi.sh. Pins stay
# in versions/. No provider credentials. The build context is the openshell
# directory.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
COPY common/harden-runtime.sh versions/codex.env codex/install-codex.sh /tmp/codex/
COPY common/harden-runtime.sh versions/pi.env pi/install-pi.sh /tmp/pi/
RUN bash /tmp/codex/install-codex.sh && rm -rf /tmp/codex \
 && bash /tmp/pi/install-pi.sh && rm -rf /tmp/pi

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp
# OpenShell drops image ENV on sandbox exec; callers pass it again.
ENV PI_CODING_AGENT_DIR=/tmp/pi-agent

ARG IMAGE_TITLE=openshell-codex-pi
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

# Both CLIs are on PATH. There is no ENTRYPOINT, so a caller can run either
# binary. The default command prints the Codex version.
CMD ["codex", "--version"]
