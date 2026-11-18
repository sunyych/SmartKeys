#!/usr/bin/env python3
"""Export two self-contained source products without overwriting a directory."""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile

FULL_DIRECTORIES = {
    "lib", "android", "ios", "assets", "desktop_companion", "packages",
    "community_server", "docs", "scripts", "packaging", ".github", "test",
    "integration_test", "linux", "macos", "windows",
}
FULL_FILES = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", ".metadata",
              ".gitignore", ".gitattributes", "README.md", "LICENSE", "LICENSE.md", "CHANGELOG.md"}
EXCLUDED_DIRECTORIES = {
    ".git", "build", "dist", "outputs", "output", ".dart_tool", ".gradle",
    ".idea", ".vscode", ".codex", ".agents", ".scratch", "target", "node_modules",
    ".cache", "__pycache__", ".venv", "venv", "work", "Pods", ".symlinks", "ephemeral", ".staging",
}
EXCLUDED_PATTERNS = (
    ".env", ".env.*", "*.jks", "*.keystore", "*.p12", "*.pfx", "*.pem", "*.key",
    "*.mobileprovision", "*.provisionprofile", "key.properties", "local.properties",
    ".flutter-plugins", ".flutter-plugins-dependencies", "*.apk", "*.aab", "*.ipa",
    "*.log", "*.tmp", "*.dill", ".DS_Store", "GeneratedPluginRegistrant.*",
    "generated_plugin_registrant.*", "generated_plugins.cmake", "Generated.xcconfig",
    "flutter_export_environment.sh", "*.xcuserstate", "google-services.json",
    "GoogleService-Info.plist", "signing.properties",
)
FULL_SKIP = {
    "scripts/build-bluetooth-lite.sh", "scripts/build_lite.ps1",
    ".github/workflows/bluetooth-lite.yml",
}
PUBLIC_TEST_FIXTURES = {
    "community_server/tests/fixtures/test-rsa-private.pem",
    "community_server/tests/fixtures/test-rsa-public.pem",
}


def excluded(path: Path) -> bool:
    return path.name in EXCLUDED_DIRECTORIES or any(
        fnmatch.fnmatch(path.name, pattern) for pattern in EXCLUDED_PATTERNS
    )


def is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path, "is_junction", lambda: False)()) or (
        os.name == "nt" and bool(getattr(path.lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT)
    )


def copy_sources(source: Path, target: Path, *, full: bool = False) -> int:
    count = 0
    target.mkdir()
    for current, directories, files in os.walk(source, followlinks=False):
        current_path = Path(current)
        relative = current_path.relative_to(source)
        keep = []
        for name in sorted(directories):
            candidate = current_path / name
            if excluded(candidate) or (full and relative == Path(".") and name not in FULL_DIRECTORIES) or (full and relative.as_posix() == "assets/desktop_installers"):
                continue
            if is_link(candidate):
                raise ValueError(f"Source directory symlinks are not exported: {candidate}")
            keep.append(name)
        directories[:] = keep
        destination = target / relative
        destination.mkdir(parents=True, exist_ok=True)
        for name in sorted(files):
            candidate = current_path / name
            path = (relative / name).as_posix()
            public_test_fixture = full and path in PUBLIC_TEST_FIXTURES
            if (excluded(candidate) and not public_test_fixture) or (full and relative == Path(".") and name not in FULL_FILES) or (full and path in FULL_SKIP) or (full and path.startswith("assets/desktop_installers/") and name not in {"README.md", ".gitignore"}):
                continue
            if is_link(candidate):
                raise ValueError(f"Source file symlinks are not exported: {candidate}")
            shutil.copy2(candidate, destination / name)
            count += 1
    return count


def export_editions(source: Path, destination: Path) -> dict[str, int]:
    source = source.resolve(strict=True)
    # lexists rejects dangling links as well as existing directories and files.
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing path: {destination}")
    destination = destination.resolve()
    if destination.is_relative_to(source):
        raise ValueError("Export destination must be outside the source repository.")
    lite = source / "apps" / "bluetooth"
    if not (lite / "pubspec.yaml").is_file():
        raise ValueError("The independent Bluetooth Lite source project is missing.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".lumia-export-", dir=destination.parent))
    try:
        counts = {
            "full": copy_sources(source, staging / "lumia-key-full", full=True),
            "bluetooth_lite": copy_sources(lite, staging / "lumia-key-bluetooth-lite"),
        }
        manifest = {"format": 1, "products": counts,
                    "excluded": ["Git metadata", "build output", "signing keys", "local SDK configuration"]}
        (staging / "EXPORT-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        # mkdir atomically claims a new path. We never rename over an existing
        # target, including a directory created while the copy was in progress.
        destination.mkdir()
        marker = destination / ".source-export-incomplete"
        marker.write_text("Export is incomplete until this marker is removed.\n", encoding="utf-8")
        for child in staging.iterdir():
            child.rename(destination / child.name)
        marker.unlink()
        return counts
    finally:
        # Only the freshly allocated staging tree is eligible for cleanup.
        if staging.parent.resolve() != destination.parent.resolve() or not staging.name.startswith(".lumia-export-") or staging.is_symlink():
            raise RuntimeError("Unexpected staging path; refusing cleanup.")
        shutil.rmtree(staging)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="New directory outside the source repository")
    args = parser.parse_args()
    try:
        counts = export_editions(Path(__file__).resolve().parent.parent, args.destination)
    except (OSError, ValueError) as error:
        parser.exit(2, f"Export failed: {error}\n")
    print(json.dumps({"destination": str(args.destination.resolve()), "files": counts}))


if __name__ == "__main__":
    main()
