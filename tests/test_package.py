"""Release mistakes must fail locally before the workflow can upload a file."""

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("addon_package", ROOT / "tools/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / package.ADDON, self.root / package.ADDON)
        for name in ("README.md", "CHANGELOG.md"):
            shutil.copyfile(ROOT / name, self.root / name)
        self.output = self.root / "dist"

    def test_installable_allowlist_and_repeatable_archive(self):
        # Extra files must never leak into the upload, even inside the addon folder.
        (self.root / package.ADDON / "SavedVariables.lua").write_text("private test data")
        first = package.build(self.root, self.output)
        before = first.read_bytes()
        with zipfile.ZipFile(first) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(len(archive.namelist()), 13)
            self.assertTrue(all(n.startswith("borjes-magasin/") for n in archive.namelist()))
            self.assertNotIn("borjes-magasin/SavedVariables.lua", archive.namelist())
            for name in archive.namelist():
                relative = name.removeprefix("borjes-magasin/")
                source = self.root / relative if relative.endswith(".md") else self.root / name
                self.assertEqual(archive.read(name), source.read_bytes())
        self.assertEqual(package.build(self.root, self.output).read_bytes(), before)
        metadata = json.loads((self.output / "metadata.json").read_text())
        self.assertEqual(metadata["gameVersionNames"], ["1.60.1"])
        self.assertEqual(metadata["releaseType"], "beta")
        self.assertFalse(metadata["isMarkedForManualRelease"])

    def test_wrong_tag_rejected_before_build(self):
        with self.assertRaisesRegex(ValueError, "Release tag"):
            package.build(self.root, self.output, tag="v999.0.0")
        self.assertFalse(self.output.exists())

    def test_version_mismatch_rejected(self):
        (self.root / package.ADDON / "Data.lua").write_text('BM.VERSION = "999.0.0"')
        with self.assertRaisesRegex(ValueError, "versions must match"):
            package.build(self.root, self.output)

    def test_missing_changelog_rejected(self):
        (self.root / "CHANGELOG.md").write_text("# Changelog\n")
        with self.assertRaisesRegex(ValueError, "Missing changelog"):
            package.build(self.root, self.output)

    def test_changed_interface_requires_explicit_mapping(self):
        toc = self.root / package.ADDON / "borjes-magasin.toc"
        toc.write_text(toc.read_text().replace("16001", "99999"))
        with self.assertRaisesRegex(ValueError, "game version mapping"):
            package.build(self.root, self.output)

    def test_toc_cannot_include_files_outside_addon(self):
        toc = self.root / package.ADDON / "borjes-magasin.toc"
        toc.write_text(toc.read_text() + "\n../README.md\n")
        with self.assertRaisesRegex(ValueError, "inside the addon"):
            package.build(self.root, self.output)


if __name__ == "__main__":
    unittest.main()
