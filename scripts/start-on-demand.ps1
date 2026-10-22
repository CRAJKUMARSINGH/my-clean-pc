#Requires -Version 5.1
<#
.SYNOPSIS
    Starts the apps that Startup Guard set to on-demand.

.DESCRIPTION
    Companion to startup-guard.ps1. Brings up the required service (if any),
    then launches the app. Nothing is launched if it is already running.

.PARAMETER App
    All (default) | AnyDesk | Bentley | ConnectionClient | LicenseService | SPC

.PARAMETER WaitForExit
    Block until the launched process exits.

.EXAMPLE
    .\start-on-demand.ps1 -App AnyDesk
.EXAMPLE
    .\start-on-demand.ps1 -App Bentley
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'AnyDesk', 'Bentley', 'ConnectionClient', 'LicenseService', 'SPC')]
    [string]$App = 'All',

    [switch]$WaitForExit
)

$ErrorActionPreference = 'Stop'

$BentleyShared = Join-Path $env:ProgramFiles 'Common Files\Bentley Shared\CONNECTION Client'

$Catalog = @{
    AnyDesk = [pscustomobject]@{
        Label       = 'AnyDesk'
        Services    = @('AnyDesk')
        Exe         = (@(
                (Join-Path $env:ProgramFiles 'AnyDesk\AnyDesk.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'AnyDesk\AnyDesk.exe')
            ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
        Args        = @('--tray')
        ProcessName = 'AnyDesk'
    }
    LicenseService = [pscustomobject]@{
        Label       = 'Bentley Licensing Service'
        Services    = @('Bentley Licensing Service', 'BentleyLicenseService')
        Exe         = (Join-Path $BentleyShared 'LicenseService\Bentley.Licensing.Service.exe')
        Args        = @()
        ProcessName = 'Bentley.Licensing.Service'
    }
    ConnectionClient = [pscustomobject]@{
        Label       = 'Bentley CONNECTION Client'
        Services    = @()
        Exe         = (Join-Path $BentleyShared 'Bentley.Connect.Client.exe')
        Args        = @()
        ProcessName = 'Bentley.Connect.Client'
    }
    SPC = [pscustomobject]@{
        Label       = 'Bentley SPC Server'
        Services    = @('Bentley Property Catalog Service', 'Bentley SPC Server')
        Exe         = (Join-Path ${env:ProgramFiles(x86)} 'Bentley\Engineering\SPC Server v8i SS4\Bentley.Structural.PropertyCatalog.Server.exe')
        Args        = @()
        ProcessName = 'Bentley.Structural.PropertyCatalog.Server'
    }
}

function Start-GuardService {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ($svc.Status -eq 'Running') { Write-Host "  service '$n' already running"; continue }
        try {
            Start-Service -Name $n -ErrorAction Stop
            Write-Host "  service '$n' started" -ForegroundColor Green
        }
        catch {
            try {
                $argCmd = "Start-Service -Name '$n'"
                Start-Process powershell.exe -ArgumentList @('-NoProfile', '-Command', $argCmd) -Verb RunAs -Wait
                $svc.Refresh()
                if ($svc.Status -eq 'Running') {
                    Write-Host "  service '$n' started (elevated)" -ForegroundColor Green
                } else {
                    Write-Warning "  could not start service '$n' (try an elevated shell): $($_.Exception.Message)"
                }
            } catch {
                Write-Warning "  could not start service '$n' (try an elevated shell): $($_.Exception.Message)"
            }
        }
    }
}

function Start-GuardApp {
    param([object]$Item, [switch]$WaitForExit)

    if ($Item.ProcessName -and (Get-Process -Name $Item.ProcessName -ErrorAction SilentlyContinue)) {
        Write-Host "  $($Item.Label) already running"
        return
    }
    if (-not $Item.Exe -or -not (Test-Path -LiteralPath $Item.Exe)) {
        Write-Warning "  not found: $($Item.Exe)"
        return
    }
    $p = if ($Item.Args -and $Item.Args.Count -gt 0) {
        Start-Process -FilePath $Item.Exe -ArgumentList $Item.Args -PassThru
    } else {
        Start-Process -FilePath $Item.Exe -PassThru
    }
    if ($WaitForExit) { $p.WaitForExit() }
    else { Write-Host "  launched $($Item.Label)" -ForegroundColor Green }
}

$selected = if ($App -eq 'All') {
    @('LicenseService', 'ConnectionClient', 'SPC', 'AnyDesk')
}
elseif ($App -eq 'Bentley') {
    @('LicenseService', 'ConnectionClient', 'SPC')
}
else { @($App) }

foreach ($key in $selected) {
    $item = $Catalog[$key]
    Write-Host "-> $($item.Label)"
    Start-GuardService -Names $item.Services
    Start-GuardApp -Item $item -WaitForExit:$WaitForExit
}
