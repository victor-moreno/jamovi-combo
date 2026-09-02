#!/usr/bin/env bash
# Pull each bundled module's submodule up to its remote's default branch, and
# report which ones moved. Doesn't build anything -- run tools/install.sh
# after to rebuild combo/ against the updated code, and commit the new
# submodule pointers once satisfied.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git submodule update --remote --merge
git status --short -- $(git config -f .gitmodules --get-regexp path | awk '{print $2}')
