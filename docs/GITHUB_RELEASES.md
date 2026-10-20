# GitHub Release pipeline

LumiaKey publishes installable assets only when a new semantic-version Tag is
pushed. Ordinary commits and branch pushes do not create a GitHub Release.

## Release contract

- The Tag format is `vMAJOR.MINOR.PATCH`, for example `v1.2.0`.
- The tagged commit must be contained in `main`.
- The Tag must be newer than every earlier stable version Tag on `main`.
- The Tag, without the leading `v`, is passed to Flutter as `--build-name` for
  the Android and Desktop products. The GitHub Actions run number is used as
  `--build-number`.
- The Android APK job depends on both desktop package jobs. It downloads the
  Windows EXE and macOS DMG as artifacts from that exact workflow run, stages
  them under `assets/desktop_installers/releases/<version>-<commit12>/`, and
  generates a catalog with each filename, byte size, and SHA-256 before
  building the APK. It never resolves a package from another run or a latest
  download URL.
- Analysis and tests for the Android app, shared protocol, and Desktop app must
  pass before any release asset is published.
- GitHub creates the Release only after the APK, DMG, and EXE jobs all succeed.

The Release contains:

- `LumiaKey-Android-vX.Y.Z.apk`
- `LumiaKey-macOS-vX.Y.Z.dmg`
- `LumiaKey-Windows-vX.Y.Z-Setup.exe`
- `SHA256SUMS.txt`

The same EXE and DMG bytes are included as Flutter assets in the Android APK.
The phone's **Desktop installers** page verifies their catalog digest and can
export them to a user-selected local shared-storage folder through Android's
Storage Access Framework. The native exporter validates the packaged bytes,
reserves the requested filename without replacing an existing file, streams
the installer, and reopens the stored document to verify its size and
SHA-256. The file can be visible while the page reports that export is still
running. USB retrieval uses Android file
transfer (MTP), not USB mass-storage mode. Development builds without the
release-generated `assets/desktop_installers/catalog.json` show the packages
as unavailable.

For the Android-only installer stage, the release workflow creates both
desktop artifacts first, then runs
`scripts/prepare_android_desktop_installers.ps1` with the version, full commit
SHA, and downloaded artifact paths. That script checks the exact expected
filenames, stages and re-hashes both files, publishes a versioned directory,
and atomically updates `catalog.json`. It registers only that release's exact
nested asset directory in `pubspec.yaml`; old release directories remain
available for reproducibility but are not re-embedded. After building the APK,
the workflow verifies the embedded catalog and exact installer entries, sizes,
and SHA-256 values before uploading it. Generated installers and catalog files
are build inputs and are not committed to the repository. Each installer is
limited to 512 MiB so the embedded asset remains within the app's package
budget. `pwsh -NoProfile -File scripts/test_prepare_android_desktop_installers.ps1`
checks generator success, rollback, nested-content rejection, SHA-256,
filename/version/size failures, and repeat/version switching using temporary
fixtures. `pwsh -NoProfile -File scripts/test_verify_android_desktop_installers.ps1`
checks the APK ZIP verifier against valid, missing, tampered, and mismatched
fixtures. For an end-to-end debug-only APK
ZIP check with those tiny fixtures, run
`pwsh -NoProfile -File scripts/test_android_installer_bundle.ps1`; it removes
the test APK and restores the source tree, so fixtures never become release APK
inputs.

## Required Android signing secrets

Create one long-lived Android release keystore and store these repository
secrets under **Settings → Secrets and variables → Actions**:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded contents of the `.jks` file.
- `ANDROID_KEY_ALIAS`: key alias inside that keystore.
- `ANDROID_KEY_PASSWORD`: password for the key alias.
- `ANDROID_STORE_PASSWORD`: password for the keystore.

On macOS, encode an existing keystore without line wrapping:

```sh
base64 -i /absolute/path/lumiakeys-release.jks | pbcopy
```

The workflow refuses to publish an APK if any signing secret is missing. Local
release builds continue to use the existing debug-signing fallback unless
`android/key.properties` or the equivalent environment variables are present.
Never commit the keystore or `android/key.properties`; both are ignored.

## Publish LumiaKey 1.2

First merge the complete V1.2 source and this workflow into `main`. Then tag
that exact `main` commit and push the Tag:

```sh
git switch main
git pull --ff-only
git tag -a v1.2.0 -m "LumiaKey 1.2.0"
git push origin v1.2.0
```

The workflow appears under **Actions → Build release assets**. Once all jobs
finish, the downloadable files appear on the repository's **Releases** page.

## Platform trust

The APK is signed with the configured stable Android release key. The current
DMG and Windows installer are not Apple-notarized or Authenticode-signed, so
macOS Gatekeeper and Windows SmartScreen may display an unverified-developer
warning. Code-signing/notarization credentials can be added later without
changing the Tag or asset naming contract.
