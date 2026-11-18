param(
    [ValidateSet('android', 'ios')][string]$Platform = 'android',
    [ValidateSet('debug', 'release')][string]$Configuration = 'release',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Platform -eq 'android') {
        & flutter build apk "--$Configuration" --flavor regular --target lib/main.dart --dart-define=LUMIAKEY_EDITION=regular @FlutterArguments
    } else {
        & flutter build ios "--$Configuration" --target lib/main.dart --dart-define=LUMIAKEY_EDITION=regular @FlutterArguments
    }
    if ($LASTEXITCODE -ne 0) { throw "Regular $Platform build failed ($LASTEXITCODE)." }
    if ($Platform -eq 'android' -and $Configuration -eq 'release') {
        # Metadata/assets can be fresh while Gradle reuses stale merged JNI.
        # Check the packaged release AOT, never a debug kernel_blob build.
        & python (Join-Path $PSScriptRoot 'verify_full_apk.py') 'build/app/outputs/flutter-apk/app-regular-release.apk'
        if ($LASTEXITCODE -ne 0) { throw 'Full release APK contains missing or outdated Dart AOT. Rebuild from a clean source directory before delivery.' }
    }
} finally { Pop-Location }
