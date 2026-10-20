[CmdletBinding()]
param(
  [string]$ArtifactRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\artifacts\windows'),
  [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\LumiaKey'),
  [string]$ShortcutRoot = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\LumiaKey'),
  [switch]$DryRun,
  [switch]$SkipShortcut,
  [switch]$FailShortcutPublishForTest
)

$ErrorActionPreference = 'Stop'
$productName = 'LumiaKey'
$executableName = 'lumiakeys_companion.exe'

function Get-FullPath([string]$Path) {
  $fullPath = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($fullPath)
  if ($fullPath.Length -gt $root.Length) {
    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  }
  return $fullPath
}

function Assert-NoReparseAncestors([string]$Path) {
  $current = Get-FullPath $Path
  while (-not [string]::IsNullOrWhiteSpace($current)) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to use a path beneath a reparse point: $($item.FullName)"
      }
    }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($current, [StringComparison]::OrdinalIgnoreCase)) { break }
    $current = $parent
  }
}

function Assert-SafeOwnedPath([string]$Path, [string]$ExpectedLeaf) {
  $fullPath = Get-FullPath $Path
  $parent = [IO.Path]::GetDirectoryName($fullPath)
  $root = [IO.Path]::GetPathRoot($fullPath)
  if ([string]::IsNullOrWhiteSpace($parent) -or
      $fullPath.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
      -not [IO.Path]::GetFileName($fullPath).Equals($ExpectedLeaf, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe path: $fullPath"
  }
  Assert-NoReparseAncestors $fullPath
  return $fullPath
}

function Assert-DirectChild([string]$Path, [string]$ParentPath) {
  $fullPath = Get-FullPath $Path
  $fullParent = Get-FullPath $ParentPath
  $prefix = $fullParent.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing recursive operation outside the owned parent '$fullParent': $fullPath"
  }
  return $fullPath
}

function Assert-NoReparsePoints([string]$RootPath) {
  $rootItem = Get-Item -LiteralPath $RootPath -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Reparse-point bundle roots are not supported: $RootPath"
  }
  foreach ($item in Get-ChildItem -LiteralPath $RootPath -Recurse -Force) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Reparse points are not allowed in the release bundle: $($item.FullName)"
    }
  }
}

function Get-FileSnapshot([string]$RootPath) {
  $root = Get-FullPath $RootPath
  $entries = @{}
  foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force) {
    $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
    if ($relative -in @('install-manifest.json', 'Uninstall-LumiaKey.ps1')) {
      throw "The release bundle contains a reserved deployment filename: $relative"
    }
    $entries[$relative] = [ordered]@{
      path = $relative
      length = [int64]$file.Length
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  }
  if (-not $entries.ContainsKey($executableName) -or
      -not $entries.ContainsKey('flutter_windows.dll') -or
      -not $entries.ContainsKey('data/icudtl.dat')) {
    throw "The source is not a complete LumiaKey Windows Release bundle: $root"
  }
  return $entries
}

function Assert-SnapshotMatches($Expected, $Actual, [string]$Label) {
  $expectedKeys = @($Expected.Keys | Sort-Object)
  $actualKeys = @($Actual.Keys | Sort-Object)
  if (($expectedKeys -join "`n") -cne ($actualKeys -join "`n")) {
    throw "$Label file list differs from the pre-install SHA-256 snapshot."
  }
  foreach ($relative in $expectedKeys) {
    if ($Expected[$relative].length -ne $Actual[$relative].length -or
        $Expected[$relative].sha256 -cne $Actual[$relative].sha256) {
      throw "$Label hash mismatch: $relative"
    }
  }
}

function Assert-NoRunningLumiaKey([string]$InstallPath) {
  $targetExe = Get-FullPath (Join-Path $InstallPath $executableName)
  $runningIds = @()
  foreach ($process in @(Get-Process -Name 'lumiakeys_companion' -ErrorAction SilentlyContinue)) {
    $processPath = $null
    try { $processPath = $process.Path } catch { }
    if ([string]::IsNullOrWhiteSpace($processPath)) {
      try { $processPath = $process.MainModule.FileName } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($processPath)) {
      if (Test-Path -LiteralPath $targetExe -PathType Leaf) { $runningIds += $process.Id }
      continue
    }
    if ((Get-FullPath $processPath).Equals($targetExe, [StringComparison]::OrdinalIgnoreCase)) {
      $runningIds += $process.Id
    }
  }
  if ($runningIds.Count -gt 0) {
    $ids = $runningIds -join ', '
    throw "LumiaKey from this install is running (PID $ids). Close it before installing or uninstalling; no process was stopped."
  }
}

function Assert-RecognizedExistingInstall([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $item = Get-Item -LiteralPath $Path -Force
  if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "The destination exists and is not a safe LumiaKey install directory: $Path"
  }
  $manifestPath = Join-Path $Path 'install-manifest.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "An existing directory has no LumiaKey deployment manifest; it was left untouched: $Path"
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ($manifest.product -cne $productName -or $manifest.formatVersion -ne 1) {
    throw "The existing deployment manifest does not identify a supported LumiaKey install: $manifestPath"
  }
  Assert-NoReparsePoints $Path
  $managedFiles = @{}
  foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or
        $relative.Contains(':') -or $relative -match '(^|/)\.\.?(/|$)' -or
        $relative -in @('install-manifest.json', 'Uninstall-LumiaKey.ps1') -or
        [string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [int64]$entry.length -lt 0) {
      throw "The existing install manifest has an invalid managed file entry: $relative"
    }
    if ($managedFiles.ContainsKey($relative)) {
      throw "The existing install manifest lists a duplicate managed file: $relative"
    }
    $managedFiles[$relative] = $entry
  }
  $installPrefix = (Get-FullPath $Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  foreach ($relative in @($managedFiles.Keys)) {
    $filePath = Get-FullPath (Join-Path $Path ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $filePath.StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "The existing install manifest points outside the install directory: $relative"
    }
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
      throw "The existing LumiaKey install is missing a managed file: $relative"
    }
    $file = Get-Item -LiteralPath $filePath -Force
    $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    if ($file.Length -ne [int64]$managedFiles[$relative].length -or
        $hash -ine [string]$managedFiles[$relative].sha256) {
      throw "The existing LumiaKey install has a managed-file hash mismatch: $relative"
    }
  }
  $expectedPaths = @($managedFiles.Keys) + @('install-manifest.json', 'Uninstall-LumiaKey.ps1')
  $actualPaths = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force | ForEach-Object {
    $_.FullName.Substring((Get-FullPath $Path).Length + 1).Replace('\', '/')
  })
  if ((@($expectedPaths | Sort-Object) -join "`n") -cne (@($actualPaths | Sort-Object) -join "`n")) {
    throw "The existing LumiaKey install contains unmanaged or missing files; it was left untouched: $Path"
  }
  Write-Host "Detected existing per-user LumiaKey install at $Path"
}

function Remove-SafeTree([string]$Path, [string]$ParentPath) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $safePath = Assert-DirectChild $Path $ParentPath
  Assert-NoReparsePoints $safePath
  Remove-Item -LiteralPath $safePath -Recurse -Force
}

$artifact = Get-FullPath $ArtifactRoot
$target = Assert-SafeOwnedPath $InstallRoot 'LumiaKey'
$targetParent = [IO.Path]::GetDirectoryName($target)
$shortcut = $null
if (-not $SkipShortcut) {
  $shortcut = Assert-SafeOwnedPath $ShortcutRoot 'LumiaKey'
  if ($shortcut.Equals($target, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The installation directory and Start Menu shortcut directory must be different.'
  }
  if (Test-Path -LiteralPath $shortcut) { Assert-NoReparsePoints $shortcut }
}
if (-not (Test-Path -LiteralPath $artifact -PathType Container)) {
  throw "Windows Release bundle was not found: $artifact"
}
Assert-NoReparsePoints $artifact
$sourceSnapshot = Get-FileSnapshot $artifact
Assert-NoRunningLumiaKey $target
Assert-RecognizedExistingInstall $target

if ($DryRun) {
  Write-Host "Dry run passed: $($sourceSnapshot.Count) bundle files were SHA-256 checked before installation."
  Write-Host "Would deploy LumiaKey to $target"
  if ($shortcut) { Write-Host "Would create the current-user Start Menu shortcut under $shortcut" }
  return
}

New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
$id = [Guid]::NewGuid().ToString('N')
$stage = Join-Path $targetParent ".LumiaKey.stage-$id"
$backup = Join-Path $targetParent ".LumiaKey.backup-$id"
$shortcutStage = $null
$shortcutBackup = $null
$shortcutInstalled = $false
$targetBackedUp = $false
$newTargetInstalled = $false

try {
  New-Item -ItemType Directory -Path $stage | Out-Null
  foreach ($entry in Get-ChildItem -LiteralPath $artifact -Force) {
    Copy-Item -LiteralPath $entry.FullName -Destination $stage -Recurse -Force
  }
  Assert-NoReparsePoints $stage
  $stagedSnapshot = Get-FileSnapshot $stage
  Assert-SnapshotMatches $sourceSnapshot $stagedSnapshot 'Staged copy'
  $sourceAfterCopy = Get-FileSnapshot $artifact
  Assert-SnapshotMatches $sourceSnapshot $sourceAfterCopy 'Source bundle'

  $exeInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $stage $executableName))
  $version = if (-not [string]::IsNullOrWhiteSpace($exeInfo.ProductVersion)) { $exeInfo.ProductVersion } else { $exeInfo.FileVersion }
  if ([string]::IsNullOrWhiteSpace($version)) { $version = 'unknown' }
  $manifest = [ordered]@{
    formatVersion = 1
    product = $productName
    version = $version
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    files = @($sourceSnapshot.Values | Sort-Object path)
  }
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'install-manifest.json') -Encoding UTF8
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall_windows.ps1') -Destination (Join-Path $stage 'Uninstall-LumiaKey.ps1')

  if ($shortcut) {
    New-Item -ItemType Directory -Force -Path $shortcut | Out-Null
    $shortcutPath = Join-Path $shortcut 'LumiaKey.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
      $shell = New-Object -ComObject WScript.Shell
      $existingLink = $shell.CreateShortcut($shortcutPath)
      $previousExe = Join-Path $target $executableName
      $existingTarget = $existingLink.TargetPath
      if ([string]::IsNullOrWhiteSpace($existingTarget) -or
          (-not (Get-FullPath $existingTarget).Equals($previousExe, [StringComparison]::OrdinalIgnoreCase) -and
           -not (Get-FullPath $existingTarget).Equals((Join-Path $stage $executableName), [StringComparison]::OrdinalIgnoreCase))) {
        throw "A Start Menu shortcut already exists with a different target; it was left untouched: $shortcutPath"
      }
    }
    $shortcutStage = Join-Path $shortcut ".LumiaKey-$id.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcutStage)
    $link.TargetPath = Join-Path $target $executableName
    $link.WorkingDirectory = $target
    $link.Description = 'LumiaKey'
    $link.Save()
  }

  Assert-NoRunningLumiaKey $target
  Assert-RecognizedExistingInstall $target
  if (Test-Path -LiteralPath $target) {
    [IO.Directory]::Move($target, $backup)
    $targetBackedUp = $true
  }
  [IO.Directory]::Move($stage, $target)
  $newTargetInstalled = $true

  if ($shortcut) {
    if ($FailShortcutPublishForTest) {
      throw 'Injected shortcut-publish failure for rollback testing.'
    }
    $shortcutPath = Join-Path $shortcut 'LumiaKey.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
      $shortcutBackup = Join-Path $shortcut ".LumiaKey-$id.previous.lnk"
      [IO.File]::Replace($shortcutStage, $shortcutPath, $shortcutBackup)
    } else {
      [IO.File]::Move($shortcutStage, $shortcutPath)
    }
    $shortcutInstalled = $true
  }

  if ($targetBackedUp) {
    try { Remove-SafeTree $backup $targetParent }
    catch { Write-Warning "Install succeeded, but the previous app backup needs cleanup: $backup ($($_.Exception.Message))" }
  }
  if ($shortcutBackup -and (Test-Path -LiteralPath $shortcutBackup)) {
    try { Remove-Item -LiteralPath $shortcutBackup -Force }
    catch { Write-Warning "Install succeeded, but the previous shortcut backup needs cleanup: $shortcutBackup ($($_.Exception.Message))" }
  }
  Write-Host "Installed LumiaKey $version for the current user at $target"
  Write-Host "To uninstall, run: `"$(Join-Path $target 'Uninstall-LumiaKey.ps1')`""
}
catch {
  if ($shortcutInstalled -and $shortcut) {
    $shortcutPath = Join-Path $shortcut 'LumiaKey.lnk'
    if ($shortcutBackup -and (Test-Path -LiteralPath $shortcutBackup)) {
      [IO.File]::Replace($shortcutBackup, $shortcutPath, $null)
    } elseif (Test-Path -LiteralPath $shortcutPath) {
      Remove-Item -LiteralPath $shortcutPath -Force
    }
  }
  if ($targetBackedUp -and (Test-Path -LiteralPath $backup)) {
    if ($newTargetInstalled -and (Test-Path -LiteralPath $target)) {
      $failed = Join-Path $targetParent ".LumiaKey.failed-$id"
      [IO.Directory]::Move($target, $failed)
      [IO.Directory]::Move($backup, $target)
      Remove-SafeTree $failed $targetParent
    } elseif (-not (Test-Path -LiteralPath $target)) {
      [IO.Directory]::Move($backup, $target)
    }
  } elseif ($newTargetInstalled -and (Test-Path -LiteralPath $target)) {
    Remove-SafeTree $target $targetParent
  }
  if (Test-Path -LiteralPath $stage) { Remove-SafeTree $stage $targetParent }
  if ($shortcutStage -and (Test-Path -LiteralPath $shortcutStage)) { Remove-Item -LiteralPath $shortcutStage -Force }
  throw
}
