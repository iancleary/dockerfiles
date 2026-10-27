# syntax=docker/dockerfile:1
# dev-base: Debian, apt packages, the developer account, then one linked
# layer per pinned tool. Archive URLs and sha256 values are read from
# dev-images/versions inside each tool stage. The build does not derive them.
# Apt packages are intentionally not pinned. Language toolchains and agent
# command-line programs are not installed.

ARG DEBIAN_IMAGE
# hadolint ignore=DL3006
FROM ${DEBIAN_IMAGE} AS debian_base

FROM debian_base AS apt_packages
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      direnv \
      git \
      git-lfs \
      openssh-client \
      tmux \
      zsh \
 && rm -rf /var/lib/apt/lists/*

FROM apt_packages AS runtime_user
COPY base/harden_runtime.sh /tmp/harden_runtime.sh
RUN bash /tmp/harden_runtime.sh && rm -f /tmp/harden_runtime.sh

FROM debian_base AS archive_tools
# hadolint ignore=DL3008
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tar \
      unzip \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

FROM archive_tools AS tool_jq
COPY versions/jq.env /tool/jq.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/jq.env \
      --key-prefix JQ \
      --destination-directory /out \
      --binary jq \
 && rm -rf /tool

FROM archive_tools AS tool_ripgrep
COPY versions/ripgrep.env /tool/ripgrep.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/ripgrep.env \
      --key-prefix RIPGREP \
      --destination-directory /out \
      --binary rg \
 && rm -rf /tool

FROM archive_tools AS tool_fd
COPY versions/fd.env /tool/fd.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/fd.env \
      --key-prefix FD \
      --destination-directory /out \
      --binary fd \
 && rm -rf /tool

FROM archive_tools AS tool_shellcheck
COPY versions/shellcheck.env /tool/shellcheck.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/shellcheck.env \
      --key-prefix SHELLCHECK \
      --destination-directory /out \
      --binary shellcheck \
 && rm -rf /tool

FROM archive_tools AS tool_just
COPY versions/just.env /tool/just.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/just.env \
      --key-prefix JUST \
      --destination-directory /out \
      --binary just \
 && rm -rf /tool

FROM archive_tools AS tool_gh
COPY versions/gh.env /tool/gh.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/gh.env \
      --key-prefix GH \
      --destination-directory /out \
      --binary gh \
 && rm -rf /tool

FROM archive_tools AS tool_uv
COPY versions/uv.env /tool/uv.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/uv.env \
      --key-prefix UV \
      --destination-directory /out \
      --binary uv \
      --binary uvx \
 && rm -rf /tool

FROM archive_tools AS tool_bat
COPY versions/bat.env /tool/bat.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/bat.env \
      --key-prefix BAT \
      --destination-directory /out \
      --binary bat \
 && rm -rf /tool

FROM archive_tools AS tool_eza
COPY versions/eza.env /tool/eza.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/eza.env \
      --key-prefix EZA \
      --destination-directory /out \
      --binary eza \
 && rm -rf /tool

FROM archive_tools AS tool_zoxide
COPY versions/zoxide.env /tool/zoxide.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/zoxide.env \
      --key-prefix ZOXIDE \
      --destination-directory /out \
      --binary zoxide \
 && rm -rf /tool

FROM archive_tools AS tool_fzf
COPY versions/fzf.env /tool/fzf.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/fzf.env \
      --key-prefix FZF \
      --destination-directory /out \
      --binary fzf \
 && rm -rf /tool

FROM archive_tools AS tool_delta
COPY versions/delta.env /tool/delta.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/delta.env \
      --key-prefix DELTA \
      --destination-directory /out \
      --binary delta \
 && rm -rf /tool

FROM archive_tools AS tool_lazygit
COPY versions/lazygit.env /tool/lazygit.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/lazygit.env \
      --key-prefix LAZYGIT \
      --destination-directory /out \
      --binary lazygit \
 && rm -rf /tool

FROM archive_tools AS tool_gum
COPY versions/gum.env /tool/gum.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/gum.env \
      --key-prefix GUM \
      --destination-directory /out \
      --binary gum \
 && rm -rf /tool

FROM archive_tools AS tool_ast_grep
COPY versions/ast-grep.env /tool/ast-grep.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/ast-grep.env \
      --key-prefix AST_GREP \
      --destination-directory /out \
      --binary ast-grep \
 && rm -rf /tool

FROM archive_tools AS tool_ahi
COPY versions/ahi.env /tool/ahi.env
COPY scripts/install_release_archive.sh /tool/install_release_archive.sh
RUN bash /tool/install_release_archive.sh \
      --version-file /tool/ahi.env \
      --key-prefix AHI \
      --destination-directory /out \
      --binary ahi \
 && rm -rf /tool

FROM runtime_user AS dev_base
COPY --link --from=tool_jq /out/ /usr/local/bin/
COPY --link --from=tool_ripgrep /out/ /usr/local/bin/
COPY --link --from=tool_fd /out/ /usr/local/bin/
COPY --link --from=tool_shellcheck /out/ /usr/local/bin/
COPY --link --from=tool_just /out/ /usr/local/bin/
COPY --link --from=tool_gh /out/ /usr/local/bin/
COPY --link --from=tool_uv /out/ /usr/local/bin/
COPY --link --from=tool_bat /out/ /usr/local/bin/
COPY --link --from=tool_eza /out/ /usr/local/bin/
COPY --link --from=tool_zoxide /out/ /usr/local/bin/
COPY --link --from=tool_fzf /out/ /usr/local/bin/
COPY --link --from=tool_delta /out/ /usr/local/bin/
COPY --link --from=tool_lazygit /out/ /usr/local/bin/
COPY --link --from=tool_gum /out/ /usr/local/bin/
COPY --link --from=tool_ast_grep /out/ /usr/local/bin/
COPY --link --from=tool_ahi /out/ /usr/local/bin/

# hadolint ignore=DL3066
USER developer
WORKDIR /tmp

ARG IMAGE_TITLE=dev-base
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
      io.iancleary.dev-images.versions="${TOOL_VERSIONS}"
