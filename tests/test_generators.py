"""Original asset regeneration after relocation, using only the standard library.

All writes occur in isolated scratch trees. Client-export CSVs remain optional
local inputs for the territory generator, not a fresh-clone test dependency.
"""
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest


def source_alias(addon):
    return "menubar-core" if addon == "Menubar" else "menubar-" + addon.removeprefix("Menubar_").lower()


class GeneratorPathsTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parent.parent
        scratch = self.root / "scratch" / "generator-spec"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.isolated = Path(self.temporary.name)

    def test_relocated_tools_reproduce_every_original_asset_without_sibling_repositories(self):
        tools = (
            ("tools/generate_icon.py", "Menubar", "Media"),
            ("tools/widgets/eyes/generate_assets.py", "Menubar_Eyes", "Assets"),
            ("tools/widgets/network/generate_icon.py", "Menubar_Network", "Media"),
            ("tools/widgets/performance/generate_icon.py", "Menubar_Performance", "Media"),
            ("tools/widgets/volume/generate-icons.py", "Menubar_Volume", "Media"),
        )
        for index, (relative, addon, asset_directory) in enumerate(tools):
            with self.subTest(tool=relative):
                checkout = self.isolated / f"clone-{index}"
                tool = checkout / relative
                tool.parent.mkdir(parents=True)
                shutil.copy2(self.root / relative, tool)
                if addon == "Menubar":
                    # The project icon shares the widget's original HD eye sampler.
                    eye_sampler = Path("tools/widgets/eyes/generate_assets.py")
                    (checkout / eye_sampler).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(self.root / eye_sampler, checkout / eye_sampler)
                # Both status TOCs coexist in a monorepo; each tool must still
                # write only the provider named by its tools/widgets/<id> path.
                for name in ("Menubar_Network", "Menubar_Performance"):
                    toc = checkout / "src" / source_alias(name) / (name + ".toc")
                    toc.parent.mkdir(parents=True)
                    shutil.copy2(self.root / "src" / source_alias(name) / (name + ".toc"), toc)
                expected_root = self.root / "src" / source_alias(addon) / asset_directory
                expected = {path.name: path.read_bytes() for path in expected_root.glob("*.tga")}
                self.assertTrue(expected, f"Missing reference assets for {addon}")
                completed = subprocess.run([sys.executable, "-B", str(tool)], cwd=self.isolated,
                                           capture_output=True, text=True, check=False)
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                generated = {path.relative_to(checkout / "src").as_posix(): path.read_bytes()
                             for path in (checkout / "src").rglob("*.tga")}
                self.assertEqual(generated, {f"{source_alias(addon)}/{asset_directory}/{name}": data
                                             for name, data in expected.items()})
                if addon == "Menubar":
                    self.assertEqual((checkout / "assets" / "Menubar.png").read_bytes(),
                                     (self.root / "assets" / "Menubar.png").read_bytes())

    def test_territory_tool_keeps_provenance_and_requires_explicit_local_exports(self):
        path = self.root / "tools/widgets/location/generate-territories.py"
        namespace = runpy.run_path(str(path), run_name="territory_generator_contract")
        self.assertEqual(namespace["DEFAULT_OUTPUT"], self.root / "src/menubar-location/TerritoryData.lua")
        self.assertEqual(namespace["VERIFIED_BUILDS"], ("70938", "70959", "71037"))
        self.assertEqual(set(namespace["SNAPSHOT_SHA256"]), {"AreaTable", "UiMap", "UiMapAssignment", "FactionGroup", "Map"})
        data_path = self.root / "src/menubar-location/TerritoryData.lua"
        before = data_path.read_bytes()
        result = subprocess.run([sys.executable, "-B", str(path), "--help"], cwd=self.isolated,
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--check", result.stdout)
        self.assertIn("--area-table", result.stdout)
        self.assertEqual(data_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
