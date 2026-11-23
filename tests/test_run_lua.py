"""Package-root selection checks; only the Python standard library is needed.

Run: python -B -m unittest discover -s tests -p test_run_lua.py
"""
from pathlib import Path
import tempfile
import unittest

from run_lua import addon_sources, hoard_integration_root, integration_roots, integration_source_dirs, source_roots


class IntegrationRootsTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parent.parent / "scratch" / "run-lua-spec"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()

    def package(self, checkout, addon, directory=None):
        root = self.directory / checkout
        source = root / "src" / (directory or addon)
        source.mkdir(parents=True)
        (source / f"{addon}.toc").write_text("## Interface: 16001\n", encoding="utf-8")
        return root

    def test_named_staging_core_wins_over_the_runners_core(self):
        runner = self.package("original", "Menubar")
        stage = self.package("v060-candidate-42", "Menubar")
        provider = self.package("clock-work", "Menubar_Time")
        core, providers = integration_roots([stage, provider], runner)
        self.assertEqual(core, stage)
        self.assertEqual(providers, {"MENUBAR_TIME_ROOT": provider})

    def test_provider_only_run_can_use_the_runners_actual_core(self):
        runner = self.package("runner-checkout", "Menubar")
        provider = self.package("time", "Menubar_Time")
        core, _ = integration_roots([provider], runner)
        self.assertEqual(core, runner)

    def test_directory_name_is_not_a_core_or_provider_contract(self):
        misleading = self.directory / "menubar-core"
        source = misleading / "src" / "Menubar_Time"
        source.mkdir(parents=True)
        (source / "Time.lua").write_text("return true\n", encoding="utf-8")
        core, providers = integration_roots([misleading], self.directory / "runner")
        self.assertIsNone(core)
        self.assertEqual(providers, {})

    def test_two_distinct_core_packages_are_rejected(self):
        first = self.package("first", "Menubar")
        second = self.package("second", "Menubar")
        with self.assertRaisesRegex(ValueError, "Multiple Menubar core roots"):
            integration_roots([first, second], first)

    def test_two_distinct_copies_of_a_provider_are_rejected(self):
        first = self.package("first", "Menubar_Time")
        second = self.package("second", "Menubar_Time")
        with self.assertRaisesRegex(ValueError, "Multiple roots for Menubar_Time"):
            integration_roots([first, second], self.directory / "runner")

    def test_duplicate_spelling_of_the_same_root_is_not_ambiguous(self):
        root = self.package("same", "Menubar")
        provider = root / "src" / "Menubar_Time"
        provider.mkdir()
        (provider / "Menubar_Time.toc").write_text("", encoding="utf-8")
        core, providers = integration_roots([root, root / ".", root / "src" / ".."], root)
        self.assertEqual(core, root)
        self.assertEqual(providers, {"MENUBAR_TIME_ROOT": root})

    def test_different_provider_types_remain_independent(self):
        first = self.package("first", "Menubar_Time")
        second = self.package("second", "Menubar_XP")
        _, providers = integration_roots([first, second], self.directory / "runner")
        self.assertEqual(providers, {"MENUBAR_TIME_ROOT": first, "MENUBAR_XP_ROOT": second})

    def test_monorepo_resolves_core_and_every_official_provider_from_one_root(self):
        root = self.package("single-clone", "Menubar")
        names = ("Ammo", "Currency", "Durability", "Eyes", "Location", "Mail", "Network",
                 "Performance", "Reputation", "Social", "Time", "Volume", "XP")
        for name in names:
            source = root / "src" / ("Menubar_" + name)
            source.mkdir()
            (source / ("Menubar_" + name + ".toc")).write_text("## Dependencies: Menubar\n", encoding="utf-8")
        core, providers = integration_roots([root], root)
        self.assertEqual(core, root)
        self.assertEqual(providers, {"MENUBAR_" + name.upper() + "_ROOT": root for name in names})

    def test_default_sources_ignore_neighbouring_old_repositories(self):
        root = self.package("new-monorepo", "Menubar")
        self.package("menubar-core", "Menubar")
        old_provider = self.package("menubar-time", "Menubar_Time")
        self.assertEqual(source_roots(None, root), [root])
        self.assertEqual(source_roots([old_provider, old_provider / "."], root), [old_provider])

    def test_hoard_is_optional_and_explicit_selection_requires_its_actual_sources(self):
        self.assertIsNone(hoard_integration_root(None))
        root = self.directory / "separate-hoard"
        for filename in ("Core.lua", "Colors.lua", "Movement.lua"):
            with self.assertRaisesRegex(ValueError, filename):
                hoard_integration_root(root)
            source = root / "src" / "ForTheHoard" / filename
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("-- Native-contract fixture placeholder; no sibling code copied.\n", encoding="utf-8")
        self.assertEqual(hoard_integration_root(root / "."), root.resolve())

    def test_original_toc_identities_work_inside_the_renamed_source_aliases(self):
        root = self.package("renamed-clone", "Menubar", "menubar-core")
        self.package("renamed-clone", "Menubar_Time", "menubar-time")
        core, providers = integration_roots([root], root)
        self.assertEqual(core, root)
        self.assertEqual(providers, {"MENUBAR_TIME_ROOT": root})
        self.assertEqual(integration_source_dirs([root], core),
                         {"Menubar": root / "src/menubar-core", "Menubar_Time": root / "src/menubar-time"})

    def test_toc_identity_is_independent_of_an_unrelated_source_folder_label(self):
        root = self.package("clone", "Menubar_Time", "clock-experiment")
        self.assertEqual(addon_sources(root), {"Menubar_Time": root / "src/clock-experiment"})

    def test_duplicate_toc_identity_inside_a_source_root_is_rejected(self):
        root = self.package("clone", "Menubar_Time", "first-clock")
        self.package("clone", "Menubar_Time", "second-clock")
        with self.assertRaisesRegex(ValueError, "Multiple source directories"):
            integration_roots([root], root)


if __name__ == "__main__":
    unittest.main()
