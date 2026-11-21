$ErrorActionPreference = 'Stop'
try {
    . "$env:LOCALAPPDATA\MyCleanPC\clean-pc-core.ps1"
    Write-Host "Dot-source OK"
    if (Get-Command Invoke-MyCleanPCCore -ErrorAction SilentlyContinue) {
        Write-Host "Invoke-MyCleanPCCore: FOUND"
    } else {
        Write-Host "Invoke-MyCleanPCCore: NOT FOUND after dot-source"
    }
} catch {
    Write-Host "Dot-source FAILED: $($_.Exception.Message)"
}
