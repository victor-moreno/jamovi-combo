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

Prebuilt `.jmo` files are attached to the [Releases](../../releases) page, one
release per jamovi/R version. Pick the file matching your OS, then in jamovi:
**Modules -> jamovi library -> Sideload** and select the downloaded `.jmo`.
Not sure which R version your jamovi bundles? Check **Help -> About** in
jamovi.

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
an R matching jamovi.app's bundled R version (see the jamovi-skill notes on
this project's two build machines -- the arm64 Mac has a known
`jmvtools::prepare()` / node-version issue; the Intel Mac's system R builds
cleanly). For other OS/arch targets once you have one working `.jmo`:

```
bash tools/prepare-jmo.sh 4.6.0 all       # metadata-only repackage, all platforms
bash tools/release.sh 4.6.0               # + publish a GitHub release
```

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
