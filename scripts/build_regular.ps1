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
} finally { Pop-Location }
