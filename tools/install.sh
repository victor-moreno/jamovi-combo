#!/usr/bin/env bash
# Assembles combo/ from the submodules, then builds and installs it into
# jamovi desktop.
#
#   bash tools/install.sh
#
# Uses whichever R `Rscript` resolves to (respecting ~/.Rprofile) -- it must
# match the R version jamovi.app itself bundles, or jmvcore segfaults on
# load. Pick the active R version with `rig default <version>` first if
# needed. See ../jamovi-jmvplus/tools/install.sh for the Docker-target
# pattern if that's wanted here too.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> assembling combo/ from submodules"
Rscript "$ROOT/tools/assemble.R"

HERE="$ROOT/combo"
MODULE="$(awk -F': *' '$1 == "Package" { print $2; exit }' "$HERE/DESCRIPTION")"
VERSION="$(awk -F': *' '$1 == "Version" { print $2; exit }' "$HERE/DESCRIPTION")"
ARTIFACT="$HERE/${MODULE}_${VERSION}.jmo"

APP=/Applications/jamovi.app
APP_R="$APP/Contents/Frameworks/R.framework/Versions/Current/Resources/bin/R"
[ -x "$APP_R" ] || { echo "error: no R inside $APP" >&2; exit 1; }

echo ">> building $MODULE $VERSION with $(Rscript -e 'cat(R.version.string)')"
cd "$HERE"

LOG="$(mktemp)"
Rscript -e 'jmvtools::install()' 2>&1 | tee "$LOG" | grep -vE '^\s*$' || true

# jmvtools::install() can report errors on stdout while exiting successfully.
# It can also claim installation succeeded after a SingletonLock failure.
[ -f "$ARTIFACT" ] || {
  echo "error: jmvtools did not produce $ARTIFACT" >&2
  rm -f "$LOG"; exit 1
}
if grep -q 'SingletonLock' "$LOG"; then
  echo
  echo "!! jamovi.app could not be driven (SingletonLock denied)."
  echo "!! The .jmo was still built. Install it by hand:"
  echo "!!   jamovi -> Modules -> Install from file -> $ARTIFACT"
  rm -f "$LOG"
  exit 0
fi
if ! grep -q 'Module installed successfully' "$LOG"; then
  echo "error: jmvtools::install() did not install the module (see above)" >&2
  rm -f "$LOG"; exit 1
fi
rm -f "$LOG"

MODDIR="$HOME/Library/Application Support/jamovi/modules/$MODULE"
if [ -d "$MODDIR" ]; then
  echo ">> installed at $MODDIR"
else
  echo "!! install reported success but $MODDIR does not exist."
  echo "!! Install $ARTIFACT by hand (Modules -> Install from file)."
  exit 1
fi

# jmc drops `addonFor` when compiling *.a.yaml into jamovi.yaml/jamovi-full.yaml
# (confirmed bug, present in this machine's jmvtools and in jamovi/jamovi:28.1's
# jamovi-compiler too) -- without it, addon analyses like jmvplus's Descriptives
# extension show up as their own duplicate, broken menu entry instead of being
# merged into the analysis they extend. Patch it back into the installed
# module and the .jmo.
python3 "$ROOT/tools/fix-addon-menu.py" "$HERE/jamovi" "$MODDIR" "$ARTIFACT" "$MODULE"
