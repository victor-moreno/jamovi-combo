#!/usr/bin/env bash
# Assembles combo/ from the submodules, then builds and installs it into
# jamovi desktop and/or a running jamovi Docker container.
#
#   bash tools/install.sh              both targets, whichever are available
#   bash tools/install.sh desktop
#   bash tools/install.sh docker [container]     (default container: jamovi)
#
# Uses whichever R `Rscript` resolves to (respecting ~/.Rprofile) for the
# desktop target -- it must match the R version jamovi.app itself bundles,
# or jmvcore segfaults on load. Pick the active R version with
# `rig default <version>` first if needed.
set -euo pipefail

TARGET="${1:-both}"
CONTAINER="${2:-jamovi}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$ROOT/combo"

echo ">> assembling combo/ from submodules"
Rscript "$ROOT/tools/assemble.R"

MODULE="$(awk -F': *' '$1 == "Package" { print $2; exit }' "$HERE/DESCRIPTION")"
VERSION="$(awk -F': *' '$1 == "Version" { print $2; exit }' "$HERE/DESCRIPTION")"
ARTIFACT="$HERE/${MODULE}_${VERSION}.jmo"

# ── desktop ──────────────────────────────────────────────────────────────────
install_desktop() {
  local APP APP_R LOG MODDIR
  APP=/Applications/jamovi.app
  APP_R="$APP/Contents/Frameworks/R.framework/Versions/Current/Resources/bin/R"
  [ -x "$APP_R" ] || { echo "error: no R inside $APP" >&2; return 1; }

  echo ">> desktop: building $MODULE $VERSION with $(Rscript -e 'cat(R.version.string)')"
  cd "$HERE"

  LOG="$(mktemp)"
  Rscript -e 'jmvtools::install()' 2>&1 | tee "$LOG" | grep -vE '^\s*$' || true

  # jmvtools::install() can report errors on stdout while exiting successfully.
  # It can also claim installation succeeded after a SingletonLock failure.
  [ -f "$ARTIFACT" ] || {
    echo "error: jmvtools did not produce $ARTIFACT" >&2
    rm -f "$LOG"; return 1
  }
  if grep -q 'SingletonLock' "$LOG"; then
    echo
    echo "!! jamovi.app could not be driven (SingletonLock denied)."
    echo "!! The .jmo was still built. Install it by hand:"
    echo "!!   jamovi -> Modules -> Install from file -> $ARTIFACT"
    rm -f "$LOG"
    return 0
  fi
  if ! grep -q 'Module installed successfully' "$LOG"; then
    echo "error: jmvtools::install() did not install the module (see above)" >&2
    rm -f "$LOG"; return 1
  fi
  rm -f "$LOG"

  MODDIR="$HOME/Library/Application Support/jamovi/modules/$MODULE"
  if [ -d "$MODDIR" ]; then
    echo ">> desktop: installed at $MODDIR"
  else
    echo "!! desktop: install reported success but $MODDIR does not exist."
    echo "!! Install $ARTIFACT by hand (Modules -> Install from file)."
    return 1
  fi

  # jmc drops `addonFor` when compiling *.a.yaml into jamovi.yaml/jamovi-full.yaml
  # (confirmed bug, present in this machine's jmvtools too) -- without it, addon
  # analyses like jmvplus's Descriptives extension show up as their own
  # duplicate, broken menu entry instead of being merged into the analysis
  # they extend. Patch it back into the installed module and the .jmo.
  python3 "$ROOT/tools/fix-addon-menu.py" "$HERE/jamovi" "$MODDIR" "$ARTIFACT" "$MODULE"
}

# ── docker ───────────────────────────────────────────────────────────────────
install_docker() {
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
    echo "!! docker: container '$CONTAINER' is not running — skipping"
    return 0
  fi

  if ! docker exec "$CONTAINER" sh -c 'command -v jmc >/dev/null 2>&1'; then
    echo "!! docker: jmc is not in the container." >&2
    echo "!! Install the jamovi compiler in the image before using this target." >&2
    return 1
  fi

  echo ">> docker: copying source into $CONTAINER"
  # --no-mac-metadata/--no-xattrs: AppleDouble ._ files otherwise land in the
  # container and jmc tries to compile them.
  tar --no-mac-metadata --no-xattrs -C "$HERE" -cf - DESCRIPTION NAMESPACE R jamovi \
    | docker exec -i "$CONTAINER" sh -c \
        "rm -rf /tmp/${MODULE}-src && mkdir -p /tmp/${MODULE}-src && tar -C /tmp/${MODULE}-src -xf -"

  echo ">> docker: jmc --install"
  docker exec -i "$CONTAINER" bash -s <<INCONTAINER
set -euo pipefail
source /usr/lib/jamovi/bin/env.conf 2>/dev/null || true
RHOME="\${R_HOME:-\$(R RHOME 2>/dev/null || true)}"
[ -n "\$RHOME" ] || { echo "   error: no R in the container" >&2; exit 1; }
RLIBS=/usr/lib/jamovi/modules/base/R

jmc --install /tmp/${MODULE}-src \\
    --to /usr/lib/jamovi/modules \\
    --rhome "\$RHOME" \\
    --rlibs "\$RLIBS" \\
    --patch-version --skip-deps

[ -f /usr/lib/jamovi/modules/${MODULE}/jamovi.yaml ] || {
  echo "   error: jmc did not install ${MODULE}" >&2; exit 1; }
INCONTAINER

  echo ">> docker: fixing addonFor in the container's installed module (jmc drops it there too)"
  local TMP
  TMP="$(mktemp -d)"
  local patched=0
  for f in jamovi.yaml jamovi-full.yaml; do
    if docker cp "$CONTAINER:/usr/lib/jamovi/modules/$MODULE/$f" "$TMP/$f" >/dev/null 2>&1; then
      patched=1
    fi
  done
  if [ "$patched" = 1 ]; then
    python3 "$ROOT/tools/fix-addon-menu.py" "$HERE/jamovi" "$TMP" - "$MODULE"
    for f in jamovi.yaml jamovi-full.yaml; do
      [ -f "$TMP/$f" ] && docker cp "$TMP/$f" "$CONTAINER:/usr/lib/jamovi/modules/$MODULE/$f" >/dev/null
    done
  fi
  rm -rf "$TMP"

  echo ">> docker: restarting $CONTAINER to load the module"
  docker restart "$CONTAINER" >/dev/null
  echo ">> docker: installed $MODULE; open Descriptives to verify there is only one entry"
}

case "$TARGET" in
  desktop) install_desktop ;;
  docker)  install_docker ;;
  both)    install_desktop || true; echo; install_docker || true ;;
  *)       echo "usage: install.sh [desktop|docker|both] [container]" >&2; exit 1 ;;
esac
