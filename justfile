# Image families. Each directory is one module.
# `just --list --list-submodules` shows every recipe.

mod openshell
mod dev-images

# List image families.
default:
    @just --list
