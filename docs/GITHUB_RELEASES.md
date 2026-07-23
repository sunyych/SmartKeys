# GitHub Release pipeline

LumiaKeys publishes installable assets only when a new semantic-version Tag is
pushed. Ordinary commits and branch pushes do not create a GitHub Release.

## Release contract

- The Tag format is `vMAJOR.MINOR.PATCH`, for example `v1.2.0`.
- The tagged commit must be contained in `main`.
- The Tag must be newer than every earlier stable version Tag on `main`.
- The Tag, without the leading `v`, is passed to Flutter as `--build-name` for
  the Android and Desktop products. The GitHub Actions run number is used as
  `--build-number`.
- Analysis and tests for the Android app, shared protocol, and Desktop app must
  pass before any release asset is published.
- GitHub creates the Release only after the APK, DMG, and EXE jobs all succeed.

The Release contains:

- `LumiaKeys-Android-vX.Y.Z.apk`
- `LumiaKeys-Desktop-macOS-vX.Y.Z.dmg`
- `LumiaKeys-Desktop-Windows-vX.Y.Z-Setup.exe`
- `SHA256SUMS.txt`

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

## Publish LumiaKeys 1.2

First merge the complete V1.2 source and this workflow into `main`. Then tag
that exact `main` commit and push the Tag:

```sh
git switch main
git pull --ff-only
git tag -a v1.2.0 -m "LumiaKeys 1.2.0"
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
