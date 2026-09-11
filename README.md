# jamovi-combo

Bundles several independently-developed [jamovi](https://www.jamovi.org) modules
into **one** sideloadable `.jmo`, to install them as a single "Sideload".

Bundled modules (see `modules.yaml`):

- [conttables2xK](https://github.com/victor-moreno/jamovi-conttables-2xK)
- [conttablespaired2xK](https://github.com/victor-moreno/jamovi-conttablespaired-2xK)
- [corrInspect](https://github.com/victor-moreno/jamovi-corrInspect)
- [regInspect](https://github.com/victor-moreno/jamovi-regInspect)
- [jmvplus](https://github.com/victor-moreno/jamovi-jmvplus)

## Installation (sideload)

Prebuilt `.jmo` files are attached to the [Releases](../../releases) page — four per version,
one for each combination of jamovi series and CPU:

| your jamovi | Apple silicon | Intel / AMD |
| --- | --- | --- |
| **current** (bundles R 4.6.0) | `vmExtras_<version>_current_R4.6.0_arm64.jmo` | `vmExtras_<version>_current_R4.6.0_x64.jmo` |
| **solid** (bundles R 4.5.0) | `vmExtras_<version>_solid_R4.5.0_arm64.jmo` | `vmExtras_<version>_solid_R4.5.0_x64.jmo` |

The same file works on macOS, Windows and Linux: jamovi's compatibility check covers the R
version and the CPU, not the operating system. Check **Help -> About** if you are unsure which R
your jamovi bundles. Then, in jamovi: **Modules -> jamovi library -> Sideload** and select the
downloaded `.jmo`.

## How the combo module is built

`jamovi.yaml` supports multiple analyses in one module. `tools/assemble.R` builds `combo/` for every module listed in `modules.yaml`:

- copying its `R/*.b.R` and other hand-written `.R` files flat into `combo/R`
- copying its `jamovi/*.a.yaml` / `.r.yaml` / `.u.yaml` / `js/*.js` into `combo/jamovi`
- copying `data/*.csv` into `combo/data`
- merging its `jamovi/00refs.yaml` `refs:` entries by key
- merging its `jamovi/i18n/<locale>.po` files per locale with `msgcat --use-first`
- unioning its `DESCRIPTION` `Imports:` (by bare package name) and its
  `NAMESPACE` `import()`/`importFrom()` lines

<br />

## Command line Build & install

```
bash tools/install.sh
```

Assembles `combo/` and runs `jmvtools::install()` into jamovi desktop. Needs
an R on `PATH` matching jamovi.app's bundled R version, or jmvcore segfaults
on load. Release builds do not: they use the app's own R (see below).

Release builds go against a specific jamovi app, which is what stamps the artifact — the R on
`PATH` is not involved:

```
bash tools/build-jmo.sh current  # build against /Applications/jamovi.app, both CPUs, into dist/
bash tools/build-jmo.sh solid    # ... against /Applications/jamovi-solid.app
bash tools/release.sh            # build all four and publish them as one GitHub release
bash tools/release.sh --prune    # ... and delete superseded releases and their tags
```

`tools/build-jmo.sh` re-runs `tools/assemble.R` first, so a release is always built from the
submodules' current state.

## Adding a new module

```
git submodule add <url> <dir-name>
```

then add one entry to `modules.yaml`:

```yaml
  - repo: <dir-name>
    pkg: <R package subdir inside it>
```

Re-run `bash tools/install.sh`. If a filename or analysis-name collides with
an already-bundled module, `assemble.R` stops and names the conflict --
rename in the new module's source repo and retry.

## Updating a bundled module

```
bash tools/update-submodules.sh   # pulls each submodule's default branch
bash tools/install.sh             # rebuild & reinstall against the update
```

then commit the moved submodule pointers. A fix in one bundled module means
rebuilding and re-sideloading the whole combo -- versioning is coupled across
everything in `modules.yaml`.

##
