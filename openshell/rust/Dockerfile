# Rust stack. rustc and cargo are on PATH. A C linker is included so cargo can link.
# Cargo's cache is under /tmp because the sandbox can write only there.
# OpenShell drops image ENV on sandbox exec, so pass CARGO_HOME again on exec.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

# hadolint ignore=DL3066
USER root
COPY common/harden-runtime.sh versions/rust.env rust/install-rust.sh /tmp/stack/
RUN bash /tmp/stack/install-rust.sh && rm -rf /tmp/stack

# hadolint ignore=DL3066
USER agent
WORKDIR /tmp
# OpenShell drops image ENV on sandbox exec, so pass CARGO_HOME again on exec.
ENV CARGO_HOME=/tmp/cargo

ARG IMAGE_TITLE=openshell-rust
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
