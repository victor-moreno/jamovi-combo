#!/usr/bin/env python3
"""
Works around a bug in jamovi-compiler (jmc): when it writes an analysis's
`addonFor` field from <name>.a.yaml into the compiled jamovi.yaml /
jamovi-full.yaml, it silently drops it (confirmed in both the local jmvtools
node_modules copy and the jamovi/jamovi:28.1 Docker image's /usr/local/lib/
jamovi-compiler/index.js -- neither copies `addonFor` into the analysis
object it writes out). Without it, jamovi's server never marks the analysis
as an addon (see server's modules.py: `if 'addonFor' in analysis_defn:
analysis.in_menu = False`), so it shows up as its own menu entry instead of
being merged into the analysis it extends -- and since these addon backends
assume `self$parent` is set (only true when attached as an addon), running
that stray entry errors out.

This patches `addonFor` back into the already-compiled jamovi.yaml /
jamovi-full.yaml, both in the installed module directory and inside the
built .jmo, using the addonFor values declared in the source *.a.yaml files.
Text-based patch (not a full YAML re-serialize) so untouched entries are
byte-for-byte unchanged.
"""
import re
import sys
import zipfile
from pathlib import Path

import yaml


def addon_map(jamovi_src_dir):
    """name -> addonFor, read from the module's own *.a.yaml sources."""
    out = {}
    for f in Path(jamovi_src_dir).glob("*.a.yaml"):
        data = yaml.safe_load(f.read_text())
        if data and "addonFor" in data:
            out[data["name"]] = data["addonFor"]
    return out


def patch_yaml_text(text, addons):
    """Insert `    addonFor: '<value>'` into each analysis entry that needs
    one and doesn't already have it, right before the entry ends."""
    lines = text.splitlines(keepends=True)
    entry_start_re = re.compile(r"^  - ")
    entry_end_re = re.compile(r"^\S")  # next top-level key: analyses: list is over
    name_re = re.compile(r"^    name:\s*(\S+)\s*$")

    out = []
    i = 0
    patched = 0
    while i < len(lines):
        line = lines[i]
        if not entry_start_re.match(line):
            out.append(line)
            i += 1
            continue

        entry = [line]
        i += 1
        while i < len(lines) and not entry_start_re.match(lines[i]) and not entry_end_re.match(lines[i]):
            entry.append(lines[i])
            i += 1

        name = None
        has_addon = False
        for l in entry:
            m = name_re.match(l)
            if m:
                name = m.group(1)
            if l.startswith("    addonFor:"):
                has_addon = True

        if name in addons and not has_addon:
            entry.append("    addonFor: '%s'\n" % addons[name])
            patched += 1

        out.extend(entry)

    return "".join(out), patched


def patch_file(path, addons):
    path = Path(path)
    if not path.exists():
        return 0
    text = path.read_text(encoding="utf-8")
    patched_text, count = patch_yaml_text(text, addons)
    if count:
        path.write_text(patched_text, encoding="utf-8")
    return count


def patch_jmo(jmo_path, module_name, addons):
    jmo_path = Path(jmo_path)
    targets = {f"{module_name}/jamovi.yaml", f"{module_name}/jamovi-full.yaml"}
    total = 0

    with zipfile.ZipFile(jmo_path) as zin:
        infos = zin.infolist()
        contents = {info.filename: zin.read(info.filename) for info in infos}

    changed = False
    for name in list(contents):
        if name in targets:
            text = contents[name].decode("utf-8")
            patched_text, count = patch_yaml_text(text, addons)
            if count:
                contents[name] = patched_text.encode("utf-8")
                total += count
                changed = True

    if not changed:
        return 0

    tmp_path = jmo_path.with_suffix(jmo_path.suffix + ".tmp")
    with zipfile.ZipFile(jmo_path) as zin, zipfile.ZipFile(
        tmp_path, "w", zipfile.ZIP_DEFLATED
    ) as zout:
        for info in zin.infolist():
            zout.writestr(info, contents[info.filename])
    tmp_path.replace(jmo_path)
    return total


def main():
    if len(sys.argv) != 5:
        print(
            "usage: fix-addon-menu.py <jamovi-src-dir> <module-dir> <jmo-path> <module-name>",
            file=sys.stderr,
        )
        return 1

    jamovi_src_dir, module_dir, jmo_path, module_name = sys.argv[1:5]
    addons = addon_map(jamovi_src_dir)
    if not addons:
        return 0

    total = 0
    total += patch_file(Path(module_dir) / "jamovi.yaml", addons)
    total += patch_file(Path(module_dir) / "jamovi-full.yaml", addons)
    if jmo_path not in ("", "-") and Path(jmo_path).exists():
        total += patch_jmo(jmo_path, module_name, addons)

    if total:
        print(f">> fix-addon-menu: restored addonFor on {total} entr{'y' if total == 1 else 'ies'} "
              f"(jmc drops it when compiling -- see script header)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
