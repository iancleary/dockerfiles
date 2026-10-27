#!/usr/bin/env bash
# Official Go toolchain. The whole GOROOT is installed. cgo is left off by
# the image because this image does not include a C compiler.
set -euo pipefail

here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$here/install_toolchain_tree.sh"

version_file=/tool/go.env
install_toolchain_tree "$version_file" GO /out/usr/local/go tree
install_relative_symlink /out/usr/local/bin/go ../go/bin/go
install_relative_symlink /out/usr/local/bin/gofmt ../go/bin/gofmt
