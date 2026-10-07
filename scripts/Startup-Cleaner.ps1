# My Clean PC - Startup Cleaner Script
# Invoked by My-Clean-PC-Starter.bat on logon

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$aiCleaner = Join-Path $scriptDir "ai-cache-cleaner.ps1"

if (-not (Test-Path -LiteralPath $aiCleaner)) {
    $aiCleaner = "$env:LOCALAPPDATA\MyCleanPC\ai-cache-cleaner.ps1"
}

if (Test-Path -LiteralPath $aiCleaner) {
    & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $aiCleaner -Clean
}
