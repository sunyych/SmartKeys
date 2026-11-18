#!/usr/bin/env python3
"""Verify the standalone Lite source and optionally its actual Android APK."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile

APP_ID = "com.lumiaiq.bluetoothlite"
ALLOWED_PERMISSIONS = {
    "android.permission.BLUETOOTH", "android.permission.BLUETOOTH_ADMIN",
    "android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_ADVERTISE",
    APP_ID + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
}
FORBIDDEN_PACKAGES = re.compile(r"^(?:http|google_sign_in.*|record(?:_.*)?|sherpa_onnx.*|local_dictation|lumiakeys_protocol|firebase.*|cloud_.*|flutter_sound.*)$")
ANDROID_NAME = "{http://schemas.android.com/apk/res/android}name"


def verify_source(root: Path) -> dict[str, object]:
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    production = pubspec.split("\ndependencies:\n", 1)[1].split("\ndev_dependencies:", 1)[0]
    dependencies = set(re.findall(r"^  ([a-zA-Z0-9_]+):", production, re.MULTILINE))
    if dependencies != {"flutter", "shared_preferences"}:
        raise ValueError(f"Unexpected production dependencies: {sorted(dependencies)}")
    if re.search(r"^\s+path:\s*", pubspec, re.MULTILINE):
        raise ValueError("Lite must not depend on a parent/path package.")
    lock_path = root / "pubspec.lock"
    if lock_path.exists():
        packages = re.findall(r"^  ([a-zA-Z0-9_]+):$", lock_path.read_text(encoding="utf-8"), re.MULTILINE)
        forbidden = [name for name in packages if FORBIDDEN_PACKAGES.fullmatch(name)]
        if forbidden:
            raise ValueError(f"Full-only dependencies in Lite lockfile: {forbidden}")
    for path in (root / "lib").rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        for package in re.findall(r"(?:import|export)\s+['\"]package:([^/]+)/", text):
            if package not in {"flutter", "shared_preferences", "lumiakey_bluetooth_lite"}:
                raise ValueError(f"Unexpected package import in {path}: {package}")
        if re.search(r"\b(?:HttpClient|WebSocket|RawSocket|ServerSocket|Socket\.connect)\b", text):
            raise ValueError(f"Network API in Lite application code: {path}")
        for reference in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", text):
            if ":" not in reference and not (path.parent / reference).resolve().is_relative_to(root):
                raise ValueError(f"Source import escapes Lite project: {path}: {reference}")
    manifests = list((root / "android" / "app" / "src").rglob("AndroidManifest.xml"))
    manifests += list((root / "build" / "app" / "intermediates" / "merged_manifests").glob("**/AndroidManifest.xml"))
    for manifest in manifests:
        tree = ET.parse(manifest)
        permissions = {element.attrib.get(ANDROID_NAME, "") for element in tree.getroot() if element.tag.startswith("uses-permission")}
        if permissions - ALLOWED_PERMISSIONS:
            raise ValueError(f"Unexpected permissions in {manifest}: {permissions - ALLOWED_PERMISSIONS}")
    gradle = (root / "android" / "app" / "build.gradle.kts").read_text(encoding="utf-8")
    if f'applicationId = "{APP_ID}"' not in gradle:
        raise ValueError("Wrong independent Lite applicationId.")
    for path in (root / "android" / "app" / "src" / "main").rglob("*.kt"):
        if re.search(r"DesktopInstaller|Companion|GoogleSignIn|RecordPlugin|lumiakeys/app_icon", path.read_text(encoding="utf-8")):
            raise ValueError(f"Full-only native integration in {path}")
    if any((root / name).exists() for name in ("desktop_companion", "community_server", "packages/local_dictation")):
        raise ValueError("Full source bundled inside independent Lite.")
    return {"applicationId": APP_ID, "productionDependencies": sorted(dependencies), "manifestsChecked": len(manifests)}


def find_aapt(root: Path, explicit: Path | None) -> Path:
    if explicit:
        return explicit
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    properties = root / "android" / "local.properties"
    if not sdk and properties.exists():
        for line in properties.read_text(encoding="utf-8").splitlines():
            if line.startswith("sdk.dir="):
                sdk = line.split("=", 1)[1].replace("\\:", ":").replace("\\\\", "\\")
    if not sdk:
        raise ValueError("Set ANDROID_HOME or pass --aapt to verify the APK manifest.")
    executable = "aapt.exe" if os.name == "nt" else "aapt"
    candidates = sorted((Path(sdk) / "build-tools").glob("*/" + executable), reverse=True)
    if not candidates:
        raise ValueError("No aapt found in the Android SDK build-tools.")
    return candidates[0]


def verify_apk(root: Path, apk: Path, aapt: Path | None) -> dict[str, object]:
    tool = find_aapt(root, aapt)
    result = subprocess.run([str(tool), "dump", "permissions", str(apk)], check=True, capture_output=True, text=True, timeout=30)
    permissions = set(re.findall(r"uses-permission(?:-sdk-\d+)?: name='([^']+)'", result.stdout))
    if permissions - ALLOWED_PERMISSIONS:
        raise ValueError(f"Unexpected permissions in APK: {permissions - ALLOWED_PERMISSIONS}")
    badging = subprocess.run([str(tool), "dump", "badging", str(apk)], check=True, capture_output=True, text=True, timeout=30).stdout
    if f"package: name='{APP_ID}'" not in badging:
        raise ValueError("APK package does not match independent Lite.")
    with ZipFile(apk) as archive:
        forbidden = [name for name in archive.namelist() if re.search(r"desktop_installers|sherpa|onnx|record_android|google_sign_in|local_dictation", name, re.IGNORECASE)]
    if forbidden:
        raise ValueError(f"Full-only assets/libraries in Lite APK: {forbidden}")
    return {"apk": str(apk.resolve()), "permissions": sorted(permissions), "bytes": apk.stat().st_size}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--aapt", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        result = verify_source(root)
        if args.apk:
            result.update(verify_apk(root, args.apk, args.aapt))
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Bluetooth Lite isolation failed: {error}\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
