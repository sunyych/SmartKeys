[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testRoot = Join-Path $repository "build/verify-installer-test-$([guid]::NewGuid().ToString('N'))"
$expectedPath = Join-Path $testRoot 'catalog.json'
$apkPath = Join-Path $testRoot 'fixture.apk'
$expanded = Join-Path $testRoot 'expanded'
$verifier = Join-Path $PSScriptRoot 'verify_android_desktop_installers.ps1'

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch { return }
    throw $Message
}

function Write-FixtureZip {
    param([switch]$OmitWindows, [switch]$TamperMac, [switch]$MismatchCatalog, [switch]$ExtraInstaller)
    if (Test-Path -LiteralPath $expanded) { Remove-Item -LiteralPath $expanded -Recurse -Force }
    if (Test-Path -LiteralPath $apkPath) { Remove-Item -LiteralPath $apkPath -Force }
    New-Item -ItemType Directory -Force -Path $expanded | Out-Null
    $base = Join-Path $expanded 'assets/flutter_assets'
    $release = Join-Path $base 'assets/desktop_installers/releases/3.2.1-0123456789ab'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    $win = [byte[]](1, 2, 3, 4)
    $mac = [byte[]](5, 6, 7, 8, 9)
    [System.IO.File]::WriteAllBytes((Join-Path $release 'LumiaKey-Windows-v3.2.1-Setup.exe'), $win)
    [System.IO.File]::WriteAllBytes((Join-Path $release 'LumiaKey-macOS-v3.2.1.dmg'), $(if ($TamperMac) { [byte[]](5, 6, 7, 0, 9) } else { $mac }))
    if ($ExtraInstaller) {
        [System.IO.File]::WriteAllBytes((Join-Path $release 'unlisted-extra.bin'), [byte[]](0x99))
    }
    if ($OmitWindows) { Remove-Item -LiteralPath (Join-Path $release 'LumiaKey-Windows-v3.2.1-Setup.exe') }
    $manifest = [ordered]@{
        schemaVersion = 1
        version = '3.2.1'
        commit = '0123456789abcdef0123456789abcdef01234567'
        installers = @(
            [ordered]@{
                platform = 'windows'; filename = 'LumiaKey-Windows-v3.2.1-Setup.exe'
                assetPath = 'assets/desktop_installers/releases/3.2.1-0123456789ab/LumiaKey-Windows-v3.2.1-Setup.exe'
                sizeBytes = 4; sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($win)) -Algorithm SHA256).Hash.ToLowerInvariant()
            },
            [ordered]@{
                platform = 'macos'; filename = 'LumiaKey-macOS-v3.2.1.dmg'
                assetPath = 'assets/desktop_installers/releases/3.2.1-0123456789ab/LumiaKey-macOS-v3.2.1.dmg'
                sizeBytes = 5; sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($mac)) -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        )
    }
    if ($MismatchCatalog) { $manifest.commit = '1123456789abcdef0123456789abcdef01234567' }
    $json = $manifest | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $base 'assets/desktop_installers/catalog.json'), $json)
    [IO.File]::WriteAllText($expectedPath, $json)
    [IO.Compression.ZipFile]::CreateFromDirectory($expanded, $apkPath)
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Write-FixtureZip
    & $verifier -ApkPath $apkPath -CatalogPath $expectedPath | Out-Null
    Write-Output 'PASS: valid catalog and nested installer entries verify.'

    Write-FixtureZip -OmitWindows
    Assert-Throws { & $verifier -ApkPath $apkPath -CatalogPath $expectedPath } 'Verifier accepted a missing installer ZIP entry.'
    Write-Output 'PASS: missing installer entry is rejected.'

    Write-FixtureZip -TamperMac
    Assert-Throws { & $verifier -ApkPath $apkPath -CatalogPath $expectedPath } 'Verifier accepted a tampered installer ZIP entry.'
    Write-Output 'PASS: installer digest mismatch is rejected.'

    Write-FixtureZip -MismatchCatalog
    Assert-Throws { & $verifier -ApkPath $apkPath -CatalogPath $expectedPath } 'Verifier accepted an APK catalog that differs from expected release metadata.'
    Write-Output 'PASS: mismatched embedded catalog is rejected.'

    Write-FixtureZip -ExtraInstaller
    Assert-Throws { & $verifier -ApkPath $apkPath -CatalogPath $expectedPath } 'Verifier accepted an unlisted installer file.'
    Write-Output 'PASS: unlisted release-directory entries are rejected.'
} finally {
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $repository 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $testFullPath = [IO.Path]::GetFullPath($testRoot)
    if (-not $testFullPath.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFileName($testFullPath).StartsWith('verify-installer-test-', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete test artifacts outside build: $testFullPath"
    }
    if (Test-Path -LiteralPath $testFullPath) { Remove-Item -LiteralPath $testFullPath -Recurse -Force }
}
