# Desktop installer assets

Release builds populate this directory during the Android release job with the
Windows and macOS installers from the same workflow run. The job writes a
versioned, SHA-256-verified catalog and publishes it atomically before building
the APK.

Installer binaries and generated catalogs are build outputs. Do not commit
them. Development APKs intentionally contain no desktop installer catalog;
the Android app reports that state explicitly.
