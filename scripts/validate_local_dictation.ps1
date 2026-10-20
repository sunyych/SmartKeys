param(
    [switch]$BuildAndroid,
    [string]$PubCache
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:PUB_CACHE = if ($PubCache) { $PubCache } else { Join-Path $repoRoot '.pub-cache' }
$screenshotRoot = if ($env:SMARTKEYS_SCREENSHOT_DIR) {
    [IO.Path]::GetFullPath($env:SMARTKEYS_SCREENSHOT_DIR)
} else {
    Join-Path $repoRoot 'build/ui_screenshots'
}
$env:SMARTKEYS_SCREENSHOT_DIR = $screenshotRoot
New-Item -ItemType Directory -Path $screenshotRoot -Force | Out-Null
$flutter = 'D:\Flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { $flutter = 'flutter' }
$dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
if (-not (Test-Path -LiteralPath $dart)) { $dart = 'dart' }
$packageRoots = @(
    @{ Name = 'root'; Path = $repoRoot; Kind = 'flutter' },
    @{ Name = 'desktop'; Path = (Join-Path $repoRoot 'desktop_companion'); Kind = 'flutter' },
    @{ Name = 'protocol'; Path = (Join-Path $repoRoot 'packages/lumiakeys_protocol'); Kind = 'dart' },
    @{ Name = 'local_dictation'; Path = (Join-Path $repoRoot 'packages/local_dictation'); Kind = 'flutter' }
)

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Program $($Arguments -join ' ')"
    }
}

foreach ($package in $packageRoots) {
    Write-Host "=== $($package.Name): resolve dependencies ===" -ForegroundColor Cyan
    Push-Location $package.Path
    try {
        if ($package.Kind -eq 'flutter') {
            Invoke-Checked $flutter @('pub', 'get')
        } else {
            Invoke-Checked $dart @('pub', 'get')
        }
    } finally {
        Pop-Location
    }
}

foreach ($package in $packageRoots) {
    Write-Host "=== $($package.Name): analyze ===" -ForegroundColor Cyan
    Push-Location $package.Path
    try {
        if ($package.Kind -eq 'flutter') {
            Invoke-Checked $flutter @('analyze')
            Write-Host "=== $($package.Name): full tests + LCOV ===" -ForegroundColor Cyan
            Invoke-Checked $flutter @('test', '--coverage')
        } else {
            Invoke-Checked $dart @('analyze')
            Write-Host "=== protocol: full tests + LCOV ===" -ForegroundColor Cyan
            $rawCoverage = 'coverage/raw-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
            Invoke-Checked $dart @('test', "--coverage=$rawCoverage")
            $coverageInfo = Join-Path $package.Path 'coverage/lcov.info'
            Invoke-Checked $dart @('run', 'coverage:format_coverage', '--lcov', "--in=$rawCoverage", "--out=$coverageInfo", '--packages=.dart_tool/package_config.json', '--report-on=lib')
        }
    } finally {
        Pop-Location
    }
}

$androidBuildStatus = 'not requested'
if ($BuildAndroid) {
    Write-Host '=== Android debug APK ===' -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        Invoke-Checked $flutter @('build', 'apk', '--debug')
        $androidBuildStatus = 'passed'
    } finally { Pop-Location }
}

$kotlinTestStatus = 'skipped: android/gradlew.bat is absent from this checkout'
$gradleWrapper = Join-Path $repoRoot 'android/gradlew.bat'
if (Test-Path -LiteralPath $gradleWrapper) {
    Write-Host '=== Android Kotlin unit tests ===' -ForegroundColor Cyan
    Push-Location (Join-Path $repoRoot 'android')
    try {
        Invoke-Checked '.\gradlew.bat' @(':app:testDebugUnitTest')
        $kotlinTestStatus = 'passed'
    } finally { Pop-Location }
} else {
    $kotlinTestStatus = 'unavailable: Android Gradle wrapper is missing'
}

Write-Host '=== Generate UI screenshot gallery ===' -ForegroundColor Cyan
$screenshotGenerator = Join-Path $repoRoot 'scripts/generate_screenshot_index.ps1'
if (-not (Test-Path -LiteralPath $screenshotGenerator)) {
    throw "Screenshot gallery generator is missing: $screenshotGenerator"
}
& $screenshotGenerator -ScreenshotRoot $screenshotRoot
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Screenshot gallery generation failed with exit code $LASTEXITCODE."
}

$packages = @()
$coverageByFile = @{}
$ownedPrefixes = @{
    root = 'lib/'
    desktop = 'desktop_companion/lib/'
    protocol = 'packages/lumiakeys_protocol/lib/'
    local_dictation = 'packages/local_dictation/lib/'
}
foreach ($package in $packageRoots) {
    $lcov = Join-Path $package.Path 'coverage/lcov.info'
    if (-not (Test-Path -LiteralPath $lcov)) {
        throw "LCOV file missing for $($package.Name): $lcov"
    }
    $found = 0
    $hit = 0
    $currentFile = $null
    foreach ($line in Get-Content -LiteralPath $lcov) {
        if ($line -match '^SF:(.+)$') {
            $sourcePath = $Matches[1].Replace('\', '/')
            if ([IO.Path]::IsPathRooted($sourcePath)) {
                $fullSourcePath = [IO.Path]::GetFullPath($sourcePath)
                $sourcePath = [IO.Path]::GetRelativePath($repoRoot, $fullSourcePath).Replace('\', '/')
            } elseif (-not $sourcePath.StartsWith('packages/') -and -not $sourcePath.StartsWith('desktop_companion/')) {
                $sourcePath = switch ($package.Name) {
                    'root' { $sourcePath }
                    'desktop' { "desktop_companion/$sourcePath" }
                    'protocol' { "packages/lumiakeys_protocol/$sourcePath" }
                    'local_dictation' { "packages/local_dictation/$sourcePath" }
                }
            }
            $currentFile = $sourcePath
        } elseif ($line -match '^DA:(\d+),(\d+)') {
            $lineNumber = [int]$Matches[1]
            $count = [int]$Matches[2]
            if ($currentFile -and $currentFile.StartsWith($ownedPrefixes[$package.Name])) {
                $found++
                if ($count -gt 0) { $hit++ }
                $key = "$currentFile`:$lineNumber"
                if (-not $coverageByFile.ContainsKey($key) -or $coverageByFile[$key] -lt $count) {
                    $coverageByFile[$key] = $count
                }
            }
        }
    }
    $coverage = if ($found -eq 0) { 0.0 } else { 100.0 * $hit / $found }
    if ($found -eq 0) { throw "No owned lib coverage records found for $($package.Name). Check its LCOV source paths." }
    $packages += [pscustomobject]@{ Package = $package.Name; CoveredLines = $hit; TotalLines = $found; LineCoveragePercent = [math]::Round($coverage, 2) }
}

Write-Host ''
Write-Host 'Measured line coverage (DA records; percentages are not thresholds):' -ForegroundColor Cyan
$packages | Format-Table -AutoSize
$totalFound = $coverageByFile.Count
if ($totalFound -eq 0) { throw 'Merged LCOV contains no source lines.' }
$totalHit = @($coverageByFile.Values | Where-Object { $_ -gt 0 }).Count
$totalPercent = if ($totalFound -eq 0) { 0.0 } else { 100.0 * $totalHit / $totalFound }
Write-Host ('TOTAL: {0}/{1} lines ({2:N2}%)' -f $totalHit, $totalFound, $totalPercent)
$mergedLines = [System.Collections.Generic.List[string]]::new()
foreach ($file in ($coverageByFile.Keys | ForEach-Object { ($_ -split ':')[0] } | Sort-Object -Unique)) {
    $mergedLines.Add("SF:$file")
    foreach ($entry in ($coverageByFile.Keys | Where-Object { $_.StartsWith("$file`:") } | Sort-Object { [int]($_ -split ':')[-1] })) {
        $parts = $entry -split ':'
        $mergedLines.Add("DA:$($parts[-1]),$($coverageByFile[$entry])")
    }
    $mergedLines.Add('end_of_record')
}
$coverageDirectory = Join-Path $repoRoot 'coverage'
New-Item -ItemType Directory -Path $coverageDirectory -Force | Out-Null
Set-Content -LiteralPath (Join-Path $coverageDirectory 'local-dictation-merged.lcov') -Value $mergedLines -Encoding utf8
$summary = [pscustomobject]@{
    Packages = $packages
    ScreenshotGallery = [pscustomobject]@{
        Directory = $screenshotRoot
        Index = (Join-Path $screenshotRoot 'index.html')
    }
    NativeChecks = [pscustomobject]@{
        AndroidDebugApk = $androidBuildStatus
        AndroidKotlinUnitTests = $kotlinTestStatus
    }
    Total = [pscustomobject]@{
        CoveredLines = $totalHit
        TotalLines = $totalFound
        LineCoveragePercent = [math]::Round($totalPercent, 2)
    }
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $coverageDirectory 'summary.json') -Encoding utf8
if (-not (Test-Path -LiteralPath $gradleWrapper)) {
    throw 'Android Kotlin tests were not run because android/gradlew.bat is absent. Run the Android debug build once to bootstrap the wrapper, then rerun this validation script.'
}
