# Working on Menubar

The core and all thirteen official widgets are in this repository. Each folder under `src/` is a separate WoW addon. The builder maps `src/menubar-core` to installed `Menubar`, and `src/menubar-<widget>` to `Menubar_<Widget>`. Source folder names are separate from installed addon names; TOC filenames and runtime asset paths keep their existing identities.

## Check and build

Use PowerShell 7 and Python 3.12. Run these commands from the repository root:

```powershell
python -m pip install --only-binary=:all: --target scratch/toolchain/python lupa==2.6
python -B tests/run_lua.py --lupa-path scratch/toolchain/python
python -B -m unittest discover -s tests -p "test_*.py"
pwsh -File tests/build_spec.ps1
pwsh -File tools/Build.ps1
```

The builder writes an installable ZIP, copied addon folders and a hash manifest under `scratch/dist/`. Test changes in the Forever client as well as running the automated checks.

Use the built ZIP for installation. An archive of the source contains the development tree and needs to be built first.

Keep research, test output, downloaded tooling and build artifacts in `scratch/`.
