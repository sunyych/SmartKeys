param(
    [ValidateSet('debug', 'release')][string]$Configuration = 'release',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments
)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path (Split-Path $PSScriptRoot -Parent) 'apps\bluetooth')
try {
    & flutter build apk "--$Configuration" --android-project-arg=kotlin.incremental=false --android-project-arg=kotlin.compiler.execution.strategy=in-process @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Lite Android build failed ($LASTEXITCODE)." }
} finally { Pop-Location }
