#!/usr/bin/env bash
# Last step of the dev-base operating-system layer. The caller is root.
# The runtime user is developer, uid 1000. There is no sudo and no setuid.
# The checks match openshell/common/harden-runtime.sh. The account name and
# login shell are the development image's own: developer, /bin/zsh.
set -euo pipefail

harden_runtime() {
  if command -v sudo >/dev/null 2>&1; then
    printf 'sudo must not be installed\n' >&2
    exit 1
  fi
  if [[ -f /etc/sudoers ]] && grep -q '[^[:space:]#]' /etc/sudoers; then
    printf 'sudoers must not grant access\n' >&2
    exit 1
  fi
  if [[ -d /etc/sudoers.d ]] && find /etc/sudoers.d -type f -print -quit | grep -q .; then
    printf 'sudoers.d must be empty\n' >&2
    exit 1
  fi
  if [[ -f /etc/shadow ]]; then
    local root_hash
    root_hash=$(awk -F: '$1=="root" { print $2; exit }' /etc/shadow)
    case "$root_hash" in
      '!'* | '*'*) ;;
      '') ;;
      *)
        printf 'root password is set\n' >&2
        exit 1
        ;;
    esac
  fi

  if ! getent group developer >/dev/null; then
    groupadd --gid 1000 developer
  fi
  if ! id -u developer >/dev/null 2>&1; then
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/zsh developer
  fi
  local developer_uid developer_gid developer_home
  developer_uid=$(id -u developer)
  developer_gid=$(id -g developer)
  if [[ "$developer_uid" != 1000 || "$developer_gid" != 1000 ]]; then
    printf 'developer must be uid 1000 and gid 1000\n' >&2
    exit 1
  fi
  developer_home=$(getent passwd developer | cut -d: -f6)
  if [[ -z "$developer_home" || "$developer_home" == / ]]; then
    printf 'developer home directory is missing\n' >&2
    exit 1
  fi
  chown "${developer_uid}:${developer_gid}" "$developer_home"
  chmod 0750 "$developer_home"

  # Installed tools stay root-owned. The runtime user cannot replace them.
  if [[ -d /usr/local ]]; then
    chown -R root:root /usr/local
    chmod -R go-w /usr/local
  fi

  # Drop setuid and setgid. These images do not need them.
  find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o \
    -type f \( -perm -4000 -o -perm -2000 \) -exec chmod a-s {} +

  # /tmp is the only world-writable path. Other sticky temp dirs are closed.
  if [[ -d /var/tmp ]]; then
    chown root:root /var/tmp
    chmod 0755 /var/tmp
  fi
  find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o \
    \( -type d -o -type f \) -perm -0002 ! -path /tmp ! -path '/tmp/*' \
    -exec chmod o-w {} +
  install -d -m 1777 -o root -g root /tmp

  local world_writable setuid_files temporary_mode
  world_writable=$(
    find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o \
      \( -type d -o -type f \) -perm -0002 ! -path /tmp ! -path '/tmp/*' -print
  )
  if [[ -n "$world_writable" ]]; then
    printf 'world-writable paths other than /tmp:\n%s\n' "$world_writable" >&2
    exit 1
  fi
  setuid_files=$(
    find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o \
      -type f \( -perm -4000 -o -perm -2000 \) -print
  )
  if [[ -n "$setuid_files" ]]; then
    printf 'setuid or setgid files remain:\n%s\n' "$setuid_files" >&2
    exit 1
  fi
  temporary_mode=$(stat -c '%a' /tmp)
  if [[ "$temporary_mode" != 1777 ]]; then
    printf '/tmp mode is %s, want 1777\n' "$temporary_mode" >&2
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  harden_runtime
fi
