[CmdletBinding()]
param(
  [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\LumiaKey'),
  [string]$ShortcutRoot = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\LumiaKey'),
  [switch]$SkipShortcut
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

function Assert-NoReparsePoints([string]$RootPath) {
  $rootItem = Get-Item -LiteralPath $RootPath -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Refusing to uninstall through a reparse point: $RootPath"
  }
  foreach ($item in Get-ChildItem -LiteralPath $RootPath -Recurse -Force) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Refusing to recursively remove a directory containing a reparse point: $($item.FullName)"
    }
  }
}

$install = Assert-SafeOwnedPath $InstallRoot 'LumiaKey'
if (-not (Test-Path -LiteralPath $install -PathType Container)) {
  throw "LumiaKey is not installed at $install"
}
$manifestPath = Join-Path $install 'install-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "No LumiaKey deployment manifest was found; the directory was left untouched: $install"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.product -cne $productName -or $manifest.formatVersion -ne 1) {
  throw "The deployment manifest does not identify a supported LumiaKey installation: $manifestPath"
}
if ($null -eq $manifest.files -or @($manifest.files).Count -eq 0) {
  throw "The LumiaKey deployment manifest does not list any managed files: $manifestPath"
}

$targetExe = Get-FullPath (Join-Path $install $executableName)
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
  throw "LumiaKey from this install is running (PID $ids). Close it before uninstalling; no process was stopped."
}

$shortcut = $null
if (-not $SkipShortcut) {
  $shortcut = Assert-SafeOwnedPath $ShortcutRoot 'LumiaKey'
  $shortcutFile = Join-Path $shortcut 'LumiaKey.lnk'
  if (Test-Path -LiteralPath $shortcutFile -PathType Leaf) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcutFile)
    $expectedTarget = Join-Path $install $executableName
    if ([string]::IsNullOrWhiteSpace($link.TargetPath) -or
        -not (Get-FullPath $link.TargetPath).Equals((Get-FullPath $expectedTarget), [StringComparison]::OrdinalIgnoreCase)) {
      throw "The Start Menu shortcut has a different target and was left untouched: $shortcutFile"
    }
  }
}

Assert-NoReparsePoints $install
$managedFiles = @{}
foreach ($entry in @($manifest.files)) {
  $relative = ([string]$entry.path).Replace('\', '/')
  $parsedLength = [int64]0
  $hasLength = $null -ne $entry.PSObject.Properties['length'] -and
    [int64]::TryParse(
      [string]$entry.length,
      [Globalization.NumberStyles]::Integer,
      [Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsedLength
    )
  if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or
      $relative.Contains(':') -or $relative -match '(^|/)\.\.?(/|$)' -or
      $relative -in @('install-manifest.json', 'Uninstall-LumiaKey.ps1') -or
      [string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
      -not $hasLength -or $parsedLength -lt 0) {
    throw "The LumiaKey deployment manifest has an invalid managed file entry: $relative"
  }
  if ($managedFiles.ContainsKey($relative)) {
    throw "The LumiaKey deployment manifest lists a duplicate managed file: $relative"
  }
  $managedFiles[$relative] = $entry
}
foreach ($requiredPath in @($executableName, 'flutter_windows.dll', 'data/icudtl.dat')) {
  if (-not $managedFiles.ContainsKey($requiredPath)) {
    throw "The LumiaKey deployment manifest is missing a required runtime file: $requiredPath"
  }
}
$installPrefix = $install.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
foreach ($relative in @($managedFiles.Keys)) {
  $filePath = Get-FullPath (Join-Path $install ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
  if (-not $filePath.StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The LumiaKey deployment manifest points outside the install directory: $relative"
  }
  if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
    throw "The LumiaKey install is missing a managed file: $relative"
  }
  $file = Get-Item -LiteralPath $filePath -Force
  $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
  if ($file.Length -ne [int64]$managedFiles[$relative].length -or
      $hash -ine [string]$managedFiles[$relative].sha256) {
    throw "The LumiaKey install has a managed-file hash mismatch: $relative"
  }
}
$expectedPaths = @($managedFiles.Keys) + @('install-manifest.json', 'Uninstall-LumiaKey.ps1')
$actualPaths = @(Get-ChildItem -LiteralPath $install -File -Recurse -Force | ForEach-Object {
  $_.FullName.Substring($install.Length + 1).Replace('\', '/')
})
if ((@($expectedPaths | Sort-Object) -join "`n") -cne (@($actualPaths | Sort-Object) -join "`n")) {
  throw "The LumiaKey install contains unmanaged or missing files; it was left untouched: $install"
}
$parent = [IO.Path]::GetDirectoryName($install)
$prefix = $parent.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $install.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to recursively remove outside its parent directory: $install"
}

if ($shortcut -and (Test-Path -LiteralPath (Join-Path $shortcut 'LumiaKey.lnk') -PathType Leaf)) {
  Remove-Item -LiteralPath (Join-Path $shortcut 'LumiaKey.lnk') -Force
}
Remove-Item -LiteralPath $install -Recurse -Force
if ($shortcut -and (Test-Path -LiteralPath $shortcut -PathType Container) -and
    @(Get-ChildItem -LiteralPath $shortcut -Force).Count -eq 0) {
  [IO.Directory]::Delete($shortcut)
}
Write-Host 'LumiaKey was uninstalled for the current user. User settings and model data were left untouched.'
