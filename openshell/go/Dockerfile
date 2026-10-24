# Go stack. The toolchain lives in /usr/local/go. No C compiler, so cgo is off.
# Module and build caches belong under /tmp. Pass these ENV values again on
# sandbox exec; OpenShell does not keep image ENV.

ARG BASE_IMAGE=openshell-agent-cli:phase1
FROM ${BASE_IMAGE}

COPY common/versions.env go/install-go.sh /tmp/stack/
RUN bash /tmp/stack/install-go.sh && rm -rf /tmp/stack

ENV GOPATH=/tmp/go
ENV GOCACHE=/tmp/gocache
ENV GOMODCACHE=/tmp/go/pkg/mod
ENV CGO_ENABLED=0

ARG IMAGE_TITLE=openshell-go
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
