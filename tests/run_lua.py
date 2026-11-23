"""Compile addon Lua and execute isolated specs using the Lua 5.1 Lupa runtime.

Install the test dependency locally, outside the addon package:
    python -m pip install --target scratch/toolchain/python lupa==2.6
Then run:
    python tests/run_lua.py --lupa-path scratch/toolchain/python

This checks Lua language compatibility and mocked behavior; it does not emulate WoW.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys


def source_roots(explicit_roots: list[Path] | None, script_root: Path) -> list[Path]:
    """Use this clone by default; old neighbouring checkouts are not inputs."""
    return list(dict.fromkeys(root.resolve() for root in (explicit_roots or [script_root])))


def hoard_integration_root(root: Path | None) -> Path | None:
    if root is None:
        return None
    root = root.resolve()
    for filename in ("Core.lua", "Colors.lua", "Movement.lua"):
        source = root / "src" / "ForTheHoard" / filename
        if not source.is_file():
            raise ValueError(f"ForTheHoard integration source is missing: {source}")
    return root


def addon_sources(root: Path) -> dict[str, Path]:
    """Installed addon identities come from TOC filenames, not source aliases."""
    result = {}
    identities = {}
    for toc in sorted((root / "src").glob("*/*.toc")):
        name = toc.stem
        if name != "Menubar" and not name.startswith("Menubar_"):
            continue
        identity = name.casefold()
        if identity in identities:
            raise ValueError(f"Multiple source directories declare addon {name}: {identities[identity]} and {toc.parent}")
        identities[identity] = toc.parent
        result[name] = toc.parent
    return result


def integration_roots(roots: list[Path], script_root: Path) -> tuple[Path | None, dict[str, Path]]:
    """Resolve source-root ownership independently of checkout/source-folder names."""
    cores = []
    providers = {}
    for root in dict.fromkeys(path.resolve() for path in roots):
        packages = addon_sources(root)
        if "Menubar" in packages:
            cores.append(root)
        for name in packages:
            if name == "Menubar":
                continue
            addon_type = name.removeprefix("Menubar_").upper()
            variable = f"MENUBAR_{addon_type}_ROOT"
            previous = providers.get(variable)
            if previous is not None and previous != root:
                raise ValueError(f"Multiple roots for {name}: {previous} and {root}")
            providers[variable] = root
    if len(cores) > 1:
        raise ValueError("Multiple Menubar core roots: " + ", ".join(str(root) for root in cores))
    core = cores[0] if cores else None
    if core is None and "Menubar" in addon_sources(script_root):
        core = script_root.resolve()
    return core, providers


def integration_source_dirs(roots: list[Path], core: Path | None) -> dict[str, Path]:
    result = {"Menubar": addon_sources(core)["Menubar"]} if core is not None else {}
    for root in roots:
        result.update(addon_sources(root))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roots", nargs="+", type=Path, help="Explicit addon source roots; defaults to this repository")
    parser.add_argument("--lupa-path", type=Path, help="Local directory containing the lupa package")
    parser.add_argument("--hoard-root", type=Path, help="Opt into integration with a separate ForTheHoard checkout")
    parser.add_argument("--syntax-only", action="store_true", help="Compile Lua without executing specs")
    options = parser.parse_args()

    script_root = Path(__file__).resolve().parent.parent
    roots = source_roots(options.roots, script_root)
    try:
        core_root, addon_roots = integration_roots(roots, script_root)
        source_dirs = integration_source_dirs(roots, core_root)
        hoard_root = hoard_integration_root(options.hoard_root)
    except ValueError as error:
        parser.error(str(error))
    if hoard_root is not None:
        addon_roots["MENUBAR_HOARD_ROOT"] = hoard_root

    local_dependency = options.lupa_path or script_root / "scratch" / "toolchain" / "python"
    if local_dependency.is_dir():
        sys.path.insert(0, str(local_dependency.resolve()))
    try:
        from lupa.lua51 import LuaRuntime, LuaError
    except ImportError:
        print("Lua 5.1 runtime unavailable. Install lupa==2.6 into scratch/toolchain/python "
              "and supply --lupa-path, or use a Python environment containing Lupa.", file=sys.stderr)
        return 2

    if core_root is not None:
        print(f"Integration core: {core_root}", flush=True)
    failures = []
    source_count = 0
    test_count = 0
    original_cwd = Path.cwd()
    try:
        for root in roots:
            if not root.is_dir():
                failures.append(f"Repository does not exist: {root}")
                continue
            source_directory = root / "src"
            source_files = sorted(source_directory.rglob("*.lua")) if source_directory.is_dir() else []
            if not source_files:
                failures.append(f"No addon Lua sources found in {source_directory}")
                continue
            runtime = LuaRuntime(unpack_returned_tuples=True)
            compile_lua = runtime.eval("function(source, name) local chunk, err = loadstring(source, name); "
                                       "if not chunk then error(err, 0) end end")
            test_directory = root / "tests"
            all_test_files = sorted(test_directory.rglob("*.lua")) if test_directory.is_dir() else []
            compile_failed = False
            for source in [*source_files, *all_test_files]:
                try:
                    compile_lua(source.read_text(encoding="utf-8-sig"), "@" + source.as_posix())
                    source_count += 1
                except (LuaError, OSError, UnicodeError) as error:
                    failures.append(f"SYNTAX {source}: {error}")
                    compile_failed = True
            if options.syntax_only or compile_failed:
                continue
            test_files = [path for path in all_test_files if
                          path.name.endswith(("_spec.lua", "_test.lua", ".spec.lua"))]
            if options.hoard_root is None:
                test_files = [path for path in test_files if path.name != "hoard_integration_spec.lua"]
            if not test_files:
                failures.append(f"No specs found in {test_directory}")
                continue
            os.chdir(root)
            for test in test_files:
                runtime = LuaRuntime(unpack_returned_tuples=True)
                lua_globals = runtime.globals()
                lua_globals.REPO_ROOT = root.as_posix()
                lua_globals.MENUBAR_SOURCE_DIRS = runtime.table_from({name: directory.as_posix() for name, directory in source_dirs.items()})
                if core_root is not None:
                    lua_globals.MENUBAR_CORE_ROOT = core_root.as_posix()
                for variable, addon_root in addon_roots.items():
                    setattr(lua_globals, variable, addon_root.as_posix())
                lua_globals.arg = runtime.table_from({0: test.as_posix()})
                test_count += 1
                try:
                    # loadfile preserves the actual filename in Lua assertion traces.
                    runtime.eval("function(path) local chunk, err = loadfile(path); "
                                 "if not chunk then error(err, 0) end; return chunk() end")(test.as_posix())
                    runtime.execute("io.stdout:flush(); io.stderr:flush()")
                    print(f"PASS {root.name}/tests/{test.relative_to(test_directory).as_posix()}", flush=True)
                except (LuaError, OSError, UnicodeError) as error:
                    failures.append(f"FAIL {test}: {error}")
    finally:
        os.chdir(original_cwd)

    for failure in failures:
        print(failure, file=sys.stderr)
    print(f"Lua 5.1: compiled {source_count} files; ran {test_count} specs; {len(failures)} failures.", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
