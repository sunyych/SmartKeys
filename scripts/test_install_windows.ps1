[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installScript = Join-Path $PSScriptRoot 'install_windows.ps1'
$uninstallScript = Join-Path $PSScriptRoot 'uninstall_windows.ps1'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$testRoot = Join-Path $tempParent "LumiaKey-install-test-$([Guid]::NewGuid().ToString('N'))"
$testRootFull = [IO.Path]::GetFullPath($testRoot)
if (-not $testRootFull.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or
    -not [IO.Path]::GetFileName($testRootFull).StartsWith('LumiaKey-install-test-', [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to use an unsafe test directory: $testRootFull"
}

$bundle = Join-Path $testRoot 'fixture-bundle'
$installRoot = Join-Path $testRoot 'Programs\LumiaKey'
$shortcutRoot = Join-Path $testRoot 'StartMenu\LumiaKey'

function Assert-UninstallRefuses([string]$ExpectedMessage = '') {
  $rejected = $false
  try {
    & (Join-Path $installRoot 'Uninstall-LumiaKey.ps1') -InstallRoot $installRoot -ShortcutRoot $shortcutRoot
  } catch {
    if ($ExpectedMessage -and $_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
    $rejected = $true
  }
  if (-not $rejected -or -not (Test-Path -LiteralPath $installRoot) -or
      -not (Test-Path -LiteralPath (Join-Path $shortcutRoot 'LumiaKey.lnk'))) {
    throw 'Uninstall did not refuse the invalid deployment while preserving its app directory and shortcut.'
  }
}

try {
  New-Item -ItemType Directory -Path (Join-Path $bundle 'data') -Force | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $bundle 'lumiakeys_companion.exe'), [byte[]](0x4c, 0x75, 0x6d, 0x69, 0x61, 0x4b, 0x65, 0x79))
  [IO.File]::WriteAllBytes((Join-Path $bundle 'flutter_windows.dll'), [byte[]](1, 2, 3, 4))
  [IO.File]::WriteAllBytes((Join-Path $bundle 'data\icudtl.dat'), [byte[]](5, 6, 7, 8))
  [IO.File]::WriteAllBytes((Join-Path $bundle 'data\test.payload'), [byte[]](9, 10, 11))

  & $installScript -ArtifactRoot $bundle -InstallRoot $installRoot -ShortcutRoot $shortcutRoot -DryRun
  if (Test-Path -LiteralPath (Split-Path -Parent $installRoot)) {
    throw 'Dry run unexpectedly created the installation parent.'
  }

  $failedFirstInstall = $false
  try {
    & $installScript -ArtifactRoot $bundle -InstallRoot $installRoot -ShortcutRoot $shortcutRoot -FailShortcutPublishForTest
  } catch {
    if ($_.Exception.Message -notlike '*Injected shortcut-publish failure*') { throw }
    $failedFirstInstall = $true
  }
  if (-not $failedFirstInstall -or (Test-Path -LiteralPath $installRoot) -or
      (Test-Path -LiteralPath (Join-Path $shortcutRoot 'LumiaKey.lnk'))) {
    throw 'A failed first install did not roll back its new directory and shortcut.'
  }

  & $installScript -ArtifactRoot $bundle -InstallRoot $installRoot -ShortcutRoot $shortcutRoot
  $installedFile = Join-Path $installRoot 'data\test.payload'
  if (-not (Test-Path -LiteralPath $installedFile) -or
      (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $bundle 'data\test.payload') -Algorithm SHA256).Hash) {
    throw 'The first temporary deployment did not match the artifact hashes.'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $shortcutRoot 'LumiaKey.lnk'))) {
    throw 'The temporary current-user shortcut was not created.'
  }

  $unmanagedFile = Join-Path $installRoot 'user-note.txt'
  [IO.File]::WriteAllText($unmanagedFile, 'keep this unmanaged fixture')
  $unmanagedRejected = $false
  try {
    & $installScript -ArtifactRoot $bundle -InstallRoot $installRoot -ShortcutRoot $shortcutRoot
  } catch {
    if ($_.Exception.Message -notlike '*unmanaged or missing files*') { throw }
    $unmanagedRejected = $true
  }
  if (-not $unmanagedRejected -or -not (Test-Path -LiteralPath $unmanagedFile)) {
    throw 'An install update did not refuse and preserve an unmanaged file.'
  }
  Remove-Item -LiteralPath $unmanagedFile -Force

  [IO.File]::WriteAllBytes((Join-Path $bundle 'data\test.payload'), [byte[]](12, 13, 14, 15))
  $oldInstalledHash = (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash
  $failedUpdate = $false
  try {
    & $installScript -ArtifactRoot $bundle -InstallRoot $installRoot -ShortcutRoot $shortcutRoot -FailShortcutPublishForTest
  } catch {
    if ($_.Exception.Message -notlike '*Injected shortcut-publish failure*') { throw }
    $failedUpdate = $true
  }
  if (-not $failedUpdate -or
      (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash -ne $oldInstalledHash -or
      -not (Test-Path -LiteralPath (Join-Path $shortcutRoot 'LumiaKey.lnk'))) {
    throw 'A failed update did not restore the previous app and shortcut.'
  }

  & $installScript -ArtifactRoot $bundle -InstallRoot $installRoot -ShortcutRoot $shortcutRoot
  if ((Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $bundle 'data\test.payload') -Algorithm SHA256).Hash) {
    throw 'The second temporary deployment did not replace the managed bundle atomically.'
  }

  $unmanagedFile = Join-Path $installRoot 'user-note.txt'
  [IO.File]::WriteAllText($unmanagedFile, 'keep this unmanaged fixture')
  Assert-UninstallRefuses 'unmanaged or missing files'
  Remove-Item -LiteralPath $unmanagedFile -Force

  [IO.File]::WriteAllBytes($installedFile, [byte[]](0xff, 0xee, 0xdd))
  Assert-UninstallRefuses 'hash mismatch'
  Copy-Item -LiteralPath (Join-Path $bundle 'data\test.payload') -Destination $installedFile -Force

  $manifestPath = Join-Path $installRoot 'install-manifest.json'
  $validManifest = [IO.File]::ReadAllText($manifestPath)
  [IO.File]::WriteAllText($manifestPath, '{"product":"LumiaKey","formatVersion":1,"files":[]}')
  Assert-UninstallRefuses 'does not list any managed files'
  $missingLengthManifest = $validManifest | ConvertFrom-Json
  $missingLengthManifest.files[0].PSObject.Properties.Remove('length')
  [IO.File]::WriteAllText($manifestPath, ($missingLengthManifest | ConvertTo-Json -Depth 8))
  Assert-UninstallRefuses 'invalid managed file entry'
  [IO.File]::WriteAllText($manifestPath, '{ malformed json')
  Assert-UninstallRefuses
  [IO.File]::WriteAllText($manifestPath, $validManifest)

  & (Join-Path $installRoot 'Uninstall-LumiaKey.ps1') -InstallRoot $installRoot -ShortcutRoot $shortcutRoot
  if ((Test-Path -LiteralPath $installRoot) -or (Test-Path -LiteralPath (Join-Path $shortcutRoot 'LumiaKey.lnk'))) {
    throw 'The temporary uninstall did not remove the app and its owned shortcut.'
  }
  Write-Host 'Temporary dry-run, install/update rollback, hash verification, invalid-uninstall protection, shortcut, and uninstall checks passed.'
}
finally {
  if (Test-Path -LiteralPath $testRootFull) {
    $parent = [IO.Path]::GetDirectoryName($testRootFull)
    $prefix = $parent.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($testRootFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($testRootFull).StartsWith('LumiaKey-install-test-', [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $testRootFull -Recurse -Force
    }
  }
}
