#!/usr/bin/env bash
# Official Node.js LTS archive. npm is the copy shipped in that archive.
# corepack is removed so the image does not download a package manager.
set -euo pipefail

here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$here/install_toolchain_tree.sh"

version_file=/tool/node.env
install_toolchain_tree "$version_file" NODE /out/usr/local strip
rm -rf /out/usr/local/lib/node_modules/corepack
rm -f /out/usr/local/bin/corepack
stamp_installed_tree /out/usr/local
