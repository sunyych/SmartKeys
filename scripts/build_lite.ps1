param(
    [ValidateSet('debug', 'release')][string]$Configuration = 'release',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & flutter build apk "--$Configuration" --flavor lite --target lib/main_lite.dart --dart-define=LUMIAKEY_EDITION=lite @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Lite Android build failed ($LASTEXITCODE)." }
} finally { Pop-Location }
