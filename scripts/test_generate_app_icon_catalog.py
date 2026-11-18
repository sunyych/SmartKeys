import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("icon_generator", Path(__file__).with_name("generate_app_icon_catalog.py"))
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class IconCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lumia-icon-catalog-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(generator.ROOT / generator.PACKAGE, self.root / generator.PACKAGE)
        self.catalog = self.root / generator.PACKAGE / "catalog.json"

    def change(self, update):
        data = json.loads(self.catalog.read_text(encoding="utf-8"))
        update(data)
        self.catalog.write_text(json.dumps(data), encoding="utf-8")

    def test_exact_required_fifty_and_ten_distinct_extra_resources(self):
        data = generator.load_catalog(self.root)
        required = json.loads((generator.ROOT / "docs/handoffs/app-icon-library/BUILTIN_APPS_50.json").read_text())
        self.assertEqual({icon["id"] for icon in data["icons"] if icon["bundled"]}, {icon["id"] for icon in required["apps"]})
        self.assertEqual(len({icon["sha256"] for icon in data["icons"]}), 60)
        self.assertEqual(data["legacyAliases"], {"codex": "chatgpt"})
        self.assertFalse(any("codex" in icon["aliases"] for icon in data["icons"]))

    def test_generated_apps_are_self_contained_and_server_has_ten_extras(self):
        generator.generate(self.root)
        generator.generate(self.root, check=True)
        for app in generator.APPS:
            self.assertEqual(len(list((self.root / app / "assets/app_icons").glob("*.png"))), 50)
            dart = (self.root / app / "lib/icons/builtin_icon_catalog.g.dart").read_text()
            self.assertNotIn("import ", dart)
            self.assertIn("class BuiltinIconEntry", dart)
            self.assertNotIn('id: "brave"', dart)
        self.assertEqual(len(list((self.root / generator.SERVER_ASSETS).glob("*.png"))), 60)

    def test_check_detects_asset_or_generated_mapping_drift(self):
        generator.generate(self.root)
        asset = self.root / "apps/bluetooth/assets/app_icons/chrome.png"
        asset.write_bytes(b"not png")
        with self.assertRaisesRegex(ValueError, "artifacts differ"):
            generator.generate(self.root, check=True)
        generator.generate(self.root)
        (self.root / "lib/icons/builtin_icon_catalog.g.dart").write_text("stale")
        with self.assertRaisesRegex(ValueError, "artifacts differ"):
            generator.generate(self.root, check=True)

    def test_full_only_export_does_not_recreate_independent_lite(self):
        generator.generate(self.root, include_lite=False)
        generator.generate(self.root, check=True, include_lite=False)
        self.assertFalse((self.root / "apps").exists())
        self.assertEqual(len(list((self.root / "assets/app_icons").glob("*.png"))), 50)
        self.assertEqual(len(list((self.root / generator.SERVER_ASSETS).glob("*.png"))), 60)

    def test_duplicate_alias_or_artwork_cannot_inflate_count(self):
        self.change(lambda data: data["icons"][0]["aliases"].append(data["icons"][1]["id"]))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            generator.load_catalog(self.root)

    def test_wrong_hash_and_broken_png_are_rejected(self):
        self.change(lambda data: data["icons"][0].update(sha256="0" * 64))
        with self.assertRaisesRegex(ValueError, "hash"):
            generator.load_catalog(self.root)
        with self.assertRaises(ValueError):
            generator.png_size(b"\x89PNG\r\n\x1a\n" + bytes(60))

    def test_parent_absolute_and_windows_paths_are_rejected(self):
        for path in ["../outside.png", "/outside.png", "C:/private.png", "sources\\private.png"]:
            with self.assertRaisesRegex(ValueError, "relative"):
                generator.checked_relative(path)

    def test_original_bytes_and_png_corruption_are_detected(self):
        data = generator.load_catalog(self.root)
        first = data["icons"][0]
        (self.root / generator.PACKAGE / first["original"]).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "Original source hash"):
            generator.load_catalog(self.root)
        raw = bytearray((generator.ROOT / generator.PACKAGE / first["png"]).read_bytes())
        raw[40] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            generator.png_size(raw)


if __name__ == "__main__":
    unittest.main()
