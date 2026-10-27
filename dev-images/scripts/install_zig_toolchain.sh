#!/usr/bin/env bash
# Official Zig toolchain. The tarball sha256 is checked, then minisign
# checks the published signature against the recorded public key.
set -euo pipefail

here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$here/install_toolchain_tree.sh"

version_file=/tool/zig.env
install_toolchain_tree "$version_file" ZIG /out/usr/local/zig tree minisign
install_relative_symlink /out/usr/local/bin/zig ../zig/zig
