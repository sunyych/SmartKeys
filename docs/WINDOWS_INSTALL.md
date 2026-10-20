# Install LumiaKey for the current Windows user

The repository deployment script installs the verified Windows Release bundle
from `build/artifacts/windows` to `%LOCALAPPDATA%\Programs\LumiaKey` and creates
a Start Menu shortcut for the current user. It does not require administrator
rights or Inno Setup, launch the app, change startup settings, or write registry
settings. Run it from the repository root:

```powershell
pwsh -NoProfile -File .\scripts\install_windows.ps1
```

Before staging, the script records SHA-256 hashes for the release files and
checks that the staged copy matches them. It then switches the install using a
same-volume staging directory. If an update fails, it restores the previous
deployment. Close LumiaKey before installing or updating; the script refuses
to replace files while `lumiakeys_companion.exe` is running and never stops it
for you. Unknown files in an existing LumiaKey install directory also block an
update so they are not discarded.

To preview the bundle verification and destination without writing files, add
`-DryRun`. The repeatable fixture test uses a temporary directory and exercises
hash verification, first-install and update rollback, shortcut creation,
protection of unmanaged files, and uninstall:

```powershell
pwsh -NoProfile -File .\scripts\install_windows.ps1 -DryRun
pwsh -NoProfile -File .\scripts\test_install_windows.ps1
```

LumiaKey stores preferences and local model data outside the program directory.
Uninstall removes the managed program files and LumiaKey's Start Menu shortcut,
but leaves preferences, downloaded/imported models, and other user data in
place. Close LumiaKey first, then run:

```powershell
pwsh -NoProfile -File .\scripts\uninstall_windows.ps1
```
