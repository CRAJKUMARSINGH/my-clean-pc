# My Clean PC - Uninstaller
# Run as Administrator: powershell -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges to uninstall My Clean PC..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait
    exit
}

$taskNames = @("MyCleanPC-7Min", "MyCleanPC-24Min", "MyCleanPC-Weekly", "MyCleanPC-AI-Cache", "24-Silent-Cleaner", "MyCleanPC")
foreach ($t in $taskNames) {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
}
Unregister-ScheduledTask -TaskPath "\My-Clean-PC\" -TaskName "Startup Guard" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Startup Guard" -Confirm:$false -ErrorAction SilentlyContinue

$installDir = "$env:LOCALAPPDATA\MyCleanPC"
if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }

Write-Host "My Clean PC uninstalled. All scheduled tasks and files removed." -ForegroundColor Green
exit 0
