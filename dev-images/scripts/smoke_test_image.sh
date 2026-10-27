#!/usr/bin/env bash
# Smoke-test one local dev-base image. Does not push.
# The container user is the image USER. Do not pass --user.
# Every pinned tool must report its recorded version with the network disabled.
set -euo pipefail

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -P -- "$script_directory/../.." && pwd -P)
openshell_smoke=$repository_root/openshell/scripts/smoke-image.sh
versions_directory=$repository_root/dev-images/versions

first_version_token() {
  local output=$1 line parsed
  while IFS= read -r line || [[ -n "$line" ]]; do
    if parsed=$(bash "$openshell_smoke" --parse-version "$line"); then
      printf '%s' "$parsed"
      return 0
    fi
  done <<<"$output"
  return 1
}

if [[ "${1:-}" == "--print-version-token" ]]; then
  [[ $# -eq 2 ]] || exit 2
  first_version_token "$2"
  exit
fi

if [[ $# -ne 1 ]]; then
  printf 'usage: smoke_test_image.sh IMAGE\n' >&2
  exit 2
fi

image=$1

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'image %s is not loaded\n' "$image" >&2
  exit 1
fi

read_recorded_value() {
  local key=$1 file=$2 line
  line=$(grep -E "^${key}=" "$file" | head -n 1) || true
  if [[ -z "$line" ]]; then
    printf 'missing %s in %s\n' "$key" "$file" >&2
    exit 1
  fi
  printf '%s' "${line#*=}"
}

run_command() {
  local entrypoint=$1
  shift
  timeout 120 docker run --rm --network none \
    --entrypoint "$entrypoint" \
    "$image" \
    "$@"
}

assert_unprivileged_developer() {
  local uid name shell_field
  uid=$(run_command id -u)
  name=$(run_command id -un)
  uid=${uid//[[:space:]]/}
  name=${name//[[:space:]]/}
  if [[ "$uid" != "1000" || "$name" != "developer" ]]; then
    printf 'dev-base ran as %s (uid %s), want 1000 and name developer\n' "$name" "$uid" >&2
    exit 1
  fi
  shell_field=$(run_command getent passwd developer)
  shell_field=${shell_field##*:}
  shell_field=${shell_field//[[:space:]]/}
  if [[ "$shell_field" != "/bin/zsh" ]]; then
    printf 'developer shell is %s, want /bin/zsh\n' "$shell_field" >&2
    exit 1
  fi
  if ! run_command sh -c 'test -w /tmp && test ! -w /usr/local/bin && ! command -v sudo >/dev/null && test -x /bin/zsh'; then
    printf 'dev-base failed the runtime permission checks\n' >&2
    exit 1
  fi
  # shellcheck disable=SC2016
  if ! run_command sh -c 'bad=$(find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o \( -type d -o -type f \) -perm -0002 ! -path /tmp ! -path "/tmp/*" -print); test -z "$bad"'; then
    printf 'dev-base has a world-writable path other than /tmp\n' >&2
    exit 1
  fi
  # shellcheck disable=SC2016
  if ! run_command sh -c 'bad=$(find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o -type f \( -perm -4000 -o -perm -2000 \) -print); test -z "$bad"'; then
    printf 'dev-base has a setuid or setgid file\n' >&2
    exit 1
  fi
}

expect_version() {
  local key=$1 file=$2 command_name=$3
  shift 3
  local output parsed want
  output=$(run_command "$command_name" "$@")
  want=$(read_recorded_value "$key" "$file")
  if ! parsed=$(first_version_token "$output"); then
    printf '%s version output has no version token: [%s]\n' "$command_name" "$output" >&2
    exit 1
  fi
  if [[ "$parsed" != "$want" ]]; then
    printf '%s version output [%s] parsed as [%s], want %s\n' "$command_name" "$output" "$parsed" "$want" >&2
    exit 1
  fi
  printf '%s %s\n' "$command_name" "$parsed"
}

expect_ahi_version() {
  local output first_line want
  output=$(run_command ahi --version)
  first_line=${output%%$'\n'*}
  first_line=${first_line%$'\r'}
  want=$(read_recorded_value AHI_VERSION "$versions_directory/ahi.env")
  if [[ "$first_line" != "ahi ${want}" ]]; then
    printf 'ahi --version printed [%s], want [ahi %s]\n' "$first_line" "$want" >&2
    exit 1
  fi
  printf '%s\n' "$first_line"
}

assert_unprivileged_developer

expect_version JQ_VERSION "$versions_directory/jq.env" jq --version
expect_version RIPGREP_VERSION "$versions_directory/ripgrep.env" rg --version
expect_version FD_VERSION "$versions_directory/fd.env" fd --version
expect_version SHELLCHECK_VERSION "$versions_directory/shellcheck.env" shellcheck --version
expect_version JUST_VERSION "$versions_directory/just.env" just --version
expect_version GH_VERSION "$versions_directory/gh.env" gh --version
expect_version UV_VERSION "$versions_directory/uv.env" uv --version
expect_version BAT_VERSION "$versions_directory/bat.env" bat --version
expect_version EZA_VERSION "$versions_directory/eza.env" eza --version
expect_version ZOXIDE_VERSION "$versions_directory/zoxide.env" zoxide --version
expect_version FZF_VERSION "$versions_directory/fzf.env" fzf --version
expect_version DELTA_VERSION "$versions_directory/delta.env" delta --version
expect_version LAZYGIT_VERSION "$versions_directory/lazygit.env" lazygit --version
expect_version GUM_VERSION "$versions_directory/gum.env" gum --version
expect_version AST_GREP_VERSION "$versions_directory/ast-grep.env" ast-grep --version
expect_ahi_version

if ! run_command sh -c 'command -v git && command -v git-lfs && command -v tmux && command -v zsh && command -v ssh && command -v direnv && command -v uvx'; then
  printf 'dev-base is missing an operating-system package or uvx\n' >&2
  exit 1
fi

printf 'smoke dev-base ok\n'
