#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="${1:?usage: apply-termux-patches.sh TERMUX_PACKAGES_DIR}"

git -C "$repo" rev-parse --is-inside-work-tree >/dev/null

shopt -s nullglob
patches=("$SCRIPT_DIR"/patches/termux/*.patch)

((${#patches[@]})) || {
    echo "ERROR: no Fermux Termux patches found" >&2
    exit 1
}

for patch in "${patches[@]}"; do
    echo "Fermux patch: $(basename "$patch")"
    sha256sum "$patch"

    if git -C "$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "  already applied"
    elif git -C "$repo" apply --check "$patch"; then
        git -C "$repo" apply "$patch"
        echo "  applied"
    else
        echo "ERROR: patch does not apply cleanly: $patch" >&2
        exit 1
    fi
done
