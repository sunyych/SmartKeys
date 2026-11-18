import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("export_editions", Path(__file__).with_name("export_editions.py"))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class ExportEditionsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lumia-export-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.source = self.base / "source"
        for name, content in {
            "pubspec.yaml": "name: full\n", "lib/main.dart": "void main() {}\n",
            "apps/bluetooth/pubspec.yaml": "name: lite\n",
            "apps/bluetooth/lib/main.dart": "void main() {}\n",
            "apps/bluetooth/.gitignore": "build/\n",
            "apps/bluetooth/android/local.properties": "sdk.dir=private\n",
            "apps/bluetooth/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java": "generated\n",
            ".git/config": "private remote\n", "android/key.properties": "private\n",
            "android/local.properties": "sdk.dir=private\n", "assets/signing.jks": "private\n",
            "assets/certificate.p12": "private\n", "assets/.env.production": "private\n",
            "assets/desktop_installers/README.md": "generated bundles are prepared separately\n",
            "assets/desktop_installers/releases/windows/setup.exe": "generated installer\n",
            "community_server/tests/fixtures/test-rsa-private.pem": "public test fixture\n",
            "community_server/tests/fixtures/test-rsa-public.pem": "public test fixture\n",
            "community_server/production-private.pem": "private\n",
            "build/out.apk": "generated\n", "community_server/target/cache": "generated\n",
            "apps/bluetooth/build/output.apk": "generated\n", "unrelated-private.txt": "private\n",
        }.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")

    def test_fresh_export_contains_two_self_contained_sources_without_secrets_or_builds(self):
        target = self.base / "export"
        result = exporter.export_editions(self.source, target)
        self.assertGreater(result["full"], 0)
        self.assertTrue((target / "lumia-key-full/lib/main.dart").is_file())
        self.assertTrue((target / "lumia-key-bluetooth-lite/pubspec.yaml").is_file())
        self.assertFalse((target / "lumia-key-full/apps").exists())
        self.assertFalse((target / ".source-export-incomplete").exists())
        for name in ("test-rsa-private.pem", "test-rsa-public.pem"):
            self.assertTrue((target / "lumia-key-full/community_server/tests/fixtures" / name).is_file())
        self.assertFalse((target / "lumia-key-full/community_server/production-private.pem").exists())
        names = [path.as_posix() for path in target.rglob("*")]
        for forbidden in (".git/config", "local.properties", "key.properties", ".jks", ".p12", ".env.production", "output.apk", "GeneratedPluginRegistrant.java", "unrelated-private.txt", "/target/", "setup.exe"):
            self.assertFalse(any(forbidden in name for name in names), forbidden)

    def test_existing_destination_is_never_replaced(self):
        target = self.base / "exists"
        target.mkdir()
        marker = target / "keep.txt"
        marker.write_text("keep", encoding="utf-8")
        with self.assertRaises(ValueError):
            exporter.export_editions(self.source, target)
        self.assertEqual(marker.read_text(), "keep")

    def test_destination_inside_repository_is_rejected(self):
        with self.assertRaises(ValueError):
            exporter.export_editions(self.source, self.source / "new-export")
        self.assertFalse((self.source / "new-export").exists())

    def test_source_link_is_rejected_before_destination_is_created(self):
        linked = self.source / "lib/main.dart"
        original = exporter.is_link
        with patch.object(exporter, "is_link", side_effect=lambda path: path == linked or original(path)):
            with self.assertRaisesRegex(ValueError, "symlinks"):
                exporter.export_editions(self.source, self.base / "linked-export")
        self.assertFalse((self.base / "linked-export").exists())
        self.assertFalse(list(self.base.glob(".lumia-export-*")))

    def test_concurrent_destination_creation_cannot_be_overwritten(self):
        destination = self.base / "raced-export"
        original = exporter.copy_sources
        def copy_and_claim(*args, **kwargs):
            result = original(*args, **kwargs)
            if not destination.exists():
                destination.mkdir()
                (destination / "other-owner.txt").write_text("preserve", encoding="utf-8")
            return result
        with patch.object(exporter, "copy_sources", side_effect=copy_and_claim):
            with self.assertRaises(FileExistsError):
                exporter.export_editions(self.source, destination)
        self.assertEqual((destination / "other-owner.txt").read_text(), "preserve")


if __name__ == "__main__":
    unittest.main()
