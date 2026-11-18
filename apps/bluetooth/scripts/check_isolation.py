#!/usr/bin/env python3
"""Verify the standalone Lite source and optionally its actual Android APK."""
from __future__ import annotations

import argparse
import hashlib
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
LITE_SURFACE_MARKERS = (
    b"lite-header-controls", b"lite-brand-icon", b"lite-twelve-key-grid",
    b"lite-app-library-catalog",
)
ANDROID_ORIENTATION = "{http://schemas.android.com/apk/res/android}screenOrientation"
ANDROID_NAME = "{http://schemas.android.com/apk/res/android}name"


def verify_source(root: Path) -> dict[str, object]:
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    production = pubspec.split("\ndependencies:\n", 1)[1].split("\ndev_dependencies:", 1)[0]
    dependencies = set(re.findall(r"^  ([a-zA-Z0-9_]+):", production, re.MULTILINE))
    if dependencies != {"flutter", "shared_preferences", "diagnostics_core"}:
        raise ValueError(f"Unexpected production dependencies: {sorted(dependencies)}")
    paths = re.findall(r"^\s+path:\s*(\S+)\s*$", pubspec, re.MULTILINE)
    if paths != ["packages/diagnostics_core"]:
        raise ValueError("Lite may depend only on its contained diagnostics core.")
    vendor = root / "packages" / "diagnostics_core"
    if not vendor.resolve().is_relative_to(root.resolve()) or vendor.is_symlink():
        raise ValueError("Diagnostics core must stay inside standalone Lite.")
    vendor_spec = (vendor / "pubspec.yaml").read_text(encoding="utf-8")
    if re.search(r"^(?:dependencies|dev_dependencies):|^\s+path:", vendor_spec, re.MULTILINE):
        raise ValueError("Vendored diagnostics runtime must have zero dependencies.")
    for item in vendor.rglob("*"):
        if item.is_symlink() or not item.resolve().is_relative_to(vendor.resolve()):
            raise ValueError("Unexpected link in diagnostics vendor.")
        if item.is_file() and not (item.relative_to(vendor).as_posix() in {"pubspec.yaml", "README.md"} or item.relative_to(vendor).as_posix().startswith("lib/") and item.suffix == ".dart"):
            raise ValueError("Only production source is allowed in diagnostics vendor.")
        if item.suffix == ".dart":
            code = item.read_text(encoding="utf-8")
            references = re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", code)
            if any(reference not in {"dart:convert", "dart:math"} for reference in references):
                raise ValueError("Unexpected diagnostics runtime import.")
    catalog = root / "lib" / "icons" / "builtin_icon_catalog.g.dart"
    data = catalog.read_text(encoding="utf-8")
    assets = re.findall(r'assetPath:\s*"([^"]+)"', data)
    if len(assets) != 50 or len(set(assets)) != 50:
        raise ValueError("Lite must bundle fifty unique offline icon resources.")
    for asset in assets:
        target = (root / asset).resolve()
        if not target.is_relative_to((root / "assets/app_icons").resolve()) or not target.is_file() or target.stat().st_size > 65536:
            raise ValueError("Missing or invalid contained Lite icon asset.")
    lock_path = root / "pubspec.lock"
    if lock_path.exists():
        packages = re.findall(r"^  ([a-zA-Z0-9_]+):$", lock_path.read_text(encoding="utf-8"), re.MULTILINE)
        forbidden = [name for name in packages if FORBIDDEN_PACKAGES.fullmatch(name)]
        if forbidden:
            raise ValueError(f"Full-only dependencies in Lite lockfile: {forbidden}")
    for path in (root / "lib").rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        for package in re.findall(r"(?:import|export)\s+['\"]package:([^/]+)/", text):
            if package not in {"flutter", "shared_preferences", "lumiakey_bluetooth_lite", "diagnostics_core"}:
                raise ValueError(f"Unexpected package import in {path}: {package}")
        if re.search(r"(?:lumiakeys/installed_apps|startDictation|sendTextBatch|nativeAppLaunch|launchApplication|KvmController)", text):
            raise ValueError(f"Full-only capability in Lite application code: {path}")
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
    activity = ET.parse(root / "android/app/src/main/AndroidManifest.xml").find("application/activity")
    if activity is None or activity.attrib.get(ANDROID_ORIENTATION) != "sensorLandscape":
        raise ValueError("Lite must declare sensorLandscape and keep its runtime portrait guard.")
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


def verify_packaged_surface(archive: ZipFile) -> dict[str, object]:
    """Inspect real compiled code, so new metadata cannot hide stale UI binaries."""
    aot = [name for name in archive.namelist() if re.fullmatch(r"lib/[^/]+/libapp\.so", name)]
    if aot:
        for name in aot:
            code = archive.read(name)
            if not code.startswith(b"\x7fELF") or len(code) < 1024 * 1024:
                raise ValueError("Invalid or unexpectedly small Lite AOT binary.")
            if any(marker not in code for marker in LITE_SURFACE_MARKERS):
                raise ValueError("Lite AOT binary does not contain the current control surface.")
        return {"compiledSurface": "AOT", "aotAbisVerified": len(aot)}
    kernel_name = "assets/flutter_assets/kernel_blob.bin"
    if kernel_name not in archive.namelist():
        raise ValueError("APK has neither Lite AOT code nor a debug kernel.")
    kernel = archive.read(kernel_name)
    if len(kernel) < 1024 * 1024 or any(marker not in kernel for marker in LITE_SURFACE_MARKERS):
        raise ValueError("Debug kernel does not contain the current Lite control surface.")
    return {"compiledSurface": "debug kernel (AOT not present)", "aotAbisVerified": 0}


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
        surface = verify_packaged_surface(archive)
        forbidden = [name for name in archive.namelist() if re.search(r"desktop_installers|sherpa|onnx|record_android|google_sign_in|local_dictation", name, re.IGNORECASE)]
        catalog = (root / "lib/icons/builtin_icon_catalog.g.dart").read_text(encoding="utf-8")
        assets = re.findall(r'assetPath:\s*"([^"]+)"', catalog)
        for asset in assets:
            payload = archive.read('assets/flutter_assets/' + asset)
            if hashlib.sha256(payload).digest() != hashlib.sha256((root / asset).read_bytes()).digest():
                raise ValueError("APK offline icon content does not match the registered Lite asset.")
    if forbidden:
        raise ValueError(f"Full-only assets/libraries in Lite APK: {forbidden}")
    return {"apk": str(apk.resolve()), "permissions": sorted(permissions), "bytes": apk.stat().st_size, "bundledIconsVerified": len(assets), **surface}


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
