#!/usr/bin/env bash
# python-build-standalone CPython, install_only_stripped. The tree stays
# together so the interpreter can find its library. uv remains the project
# installer already present in dev-base.
set -euo pipefail

here=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
source "$here/install_toolchain_tree.sh"

version_file=/tool/python.env
install_toolchain_tree "$version_file" PYTHON /out/usr/local/python tree
install_relative_symlink /out/usr/local/bin/python3 ../python/bin/python3
install_relative_symlink /out/usr/local/bin/python python3
