# Google account backup integration

The backup screen is available at `AccountBackupScreen`. It stores one latest
settings/Profile snapshot per verified Google account in the separately
deployed backup API. Sign-in, upload, restore and delete are explicit user
actions. The ID token is held in memory and sent only as the Bearer credential
to `SMARTKEYS_BACKUP_URL`; email is displayed only during that sign-in session.
This feature does not use Google Drive scopes or link anonymous community
ranking receipts.

## Flutter build configuration

Supply these compile-time values through `--dart-define` or the release build
configuration:

```text
SMARTKEYS_BACKUP_URL=https://backup.example.org
SMARTKEYS_GOOGLE_WEB_CLIENT_ID=<Web OAuth client ID>
SMARTKEYS_GOOGLE_IOS_CLIENT_ID=<iOS OAuth client ID>
```

The endpoint must use HTTPS. HTTP is accepted only for explicit loopback test
construction in code. If the endpoint or a required OAuth ID is missing, backup
actions stay disabled with a configuration message; the app does not use mock
sign-in or placeholder data.

## Google Cloud setup

Create a Web OAuth client and an iOS OAuth client in the same Google Cloud
project. Configure the server's `GOOGLE_CLIENT_IDS` allowlist with the Web
client ID used as the ID-token audience. Google may generate a client secret
for the Web OAuth client; never embed that secret in the app or commit it to
this repository. The server must validate the token signature and `iss`,
`aud`, `exp` and nonempty `sub` using Google's official JWKS before reading or
writing a backup.

For iOS, register the reversed iOS client ID as a URL scheme in the app target's
`ios/Runner/Info.plist`. For an ID such as
`123456.apps.googleusercontent.com`, the scheme is
`com.googleusercontent.apps.123456`. The app checks this scheme before invoking
the Google native sign-in SDK, since a missing URL registration can terminate
the iOS process. Keep the scheme and `SMARTKEYS_GOOGLE_IOS_CLIENT_ID` in sync.
This repository has no OAuth IDs configured yet, so iOS sign-in remains
unavailable until the app target is configured.

For Android, register the app's actual application ID and signing certificate
SHA-1/SHA-256 fingerprints for the Android OAuth client in the same Google
project. Include both debug and release fingerprints if both builds are used.
The Web client ID remains the server ID-token audience. Do not substitute a
debug package or signing certificate in a release build.

The current Android application ID and iOS Runner bundle ID are both
`com.lumiaiq.smartkey`. Recheck these project settings if creating a differently
branded build. On Windows, `cd android; .\gradlew.bat :app:signingReport` reports
the configured signing fingerprints; register the certificate used for the
build being installed. Do not upload a keystore or its password to this service.

For example, after configuring the server and Android OAuth registration:

```powershell
flutter build apk --release `
  --dart-define=SMARTKEYS_RANKING_URL=https://your-service.example `
  --dart-define=SMARTKEYS_BACKUP_URL=https://your-service.example `
  --dart-define=SMARTKEYS_GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Replace the example host and client ID. The corresponding iOS build on a Mac
also needs `SMARTKEYS_GOOGLE_IOS_CLIENT_ID` and the URL scheme described above.

## Data and recovery boundaries

The user selects App settings, individual Profiles and optionally custom
images, reviews the request, then starts the upload. Profile fields are the
app's current `ProfileConfig.toJson()` fields. Desktop companion action values
are preserved as configuration data when they are non-empty JSON objects no
larger than 16 KiB; the backup and restore flow never executes them. Device
pairing, local usage history, anonymous upload receipts, account identifiers
and tokens never enter a backup.

The backup envelope and upload request are bounded to 20 MiB. The client allows
an additional 4 KiB for the GET response wrapper and metadata. Each selected
image is at most 4 MiB, uses a safe relative `images/<folder>/<filename>` path
and a supported PNG, JPEG or WebP header; images above 16 megapixels are
rejected.
Restore merges selected Profiles by ID, checks the four-profile limit before
changing configuration, saves before updating the visible state, and writes
images under new private paths. It preserves local device pairing and usage.
Restored shortcuts are not executed. A profile image is retained only when its
backup bytes were selected or a matching local file still exists.

If a backup fails with an authentication error, the user can explicitly sign in
again. Signing out of Google clears only the in-memory account/token in this
feature; it does not delete the online snapshot. Use “Delete online backup” to
remove that account's stored snapshot.
