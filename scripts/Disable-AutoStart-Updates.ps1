#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables auto-start and auto-update scheduled tasks for:
    Microsoft Edge, Brave, Yandex, Vivaldi, Opera, Firefox, Chrome, AnyDesk, NordVPN

.DESCRIPTION
    1. Disables matching Windows Scheduled Tasks
    2. Removes / disables Run & RunOnce registry startup entries
    3. Disables known Windows Services used for background updates

    Run this script as Administrator.
#>

$ErrorActionPreference = 'SilentlyContinue'

# ─────────────────────────────────────────────
# Helper: disable a scheduled task safely
# ─────────────────────────────────────────────
function Disable-TaskSafe {
    param([string]$Path, [string]$Name)
    $task = Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction SilentlyContinue
    if ($task) {
        Disable-ScheduledTask -TaskPath $Path -TaskName $Name | Out-Null
        Write-Host "  [DISABLED TASK]  $Path$Name" -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────
# Helper: disable ALL tasks whose name matches a pattern
# ─────────────────────────────────────────────
function Disable-TasksByPattern {
    param([string]$Pattern)
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -match $Pattern }
    foreach ($t in $tasks) {
        if ($t.State -ne 'Disabled') {
            Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName | Out-Null
            Write-Host "  [DISABLED TASK]  $($t.TaskPath)$($t.TaskName)" -ForegroundColor Green
        }
    }
}

# ─────────────────────────────────────────────
# Helper: remove a registry startup value
# ─────────────────────────────────────────────
function Remove-StartupEntry {
    param([string]$KeyPath, [string]$ValuePattern)
    if (Test-Path $KeyPath) {
        $vals = (Get-Item $KeyPath).Property | Where-Object { $_ -match $ValuePattern }
        foreach ($v in $vals) {
            Remove-ItemProperty -Path $KeyPath -Name $v -Force
            Write-Host "  [REMOVED STARTUP REG]  $KeyPath  ->  $v" -ForegroundColor Yellow
        }
    }
}

# ─────────────────────────────────────────────
# Helper: stop & disable a Windows service
# ─────────────────────────────────────────────
function Disable-ServiceSafe {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service  -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service   -Name $Name -StartupType Disabled
        Write-Host "  [DISABLED SERVICE]  $Name" -ForegroundColor Cyan
    }
}

# ══════════════════════════════════════════════
#  MICROSOFT EDGE
# ══════════════════════════════════════════════
Write-Host "`n── Microsoft Edge ──" -ForegroundColor Magenta

# Scheduled tasks
Disable-TasksByPattern -Pattern 'MicrosoftEdge'
Disable-TasksByPattern -Pattern 'Edge'

# Registry startups
$RunKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Edge|MicrosoftEdge' }

# Edge update service
Disable-ServiceSafe -Name 'edgeupdate'
Disable-ServiceSafe -Name 'edgeupdatem'

# ══════════════════════════════════════════════
#  BRAVE BROWSER
# ══════════════════════════════════════════════
Write-Host "`n── Brave Browser ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'Brave'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Brave' }
Disable-ServiceSafe -Name 'brave'
Disable-ServiceSafe -Name 'BraveUpdate'
Disable-ServiceSafe -Name 'bravem'

# ══════════════════════════════════════════════
#  YANDEX BROWSER
# ══════════════════════════════════════════════
Write-Host "`n── Yandex Browser ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'Yandex'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Yandex' }
Disable-ServiceSafe -Name 'yandex'
Disable-ServiceSafe -Name 'YandexBrowserUpdate'

# ══════════════════════════════════════════════
#  VIVALDI
# ══════════════════════════════════════════════
Write-Host "`n── Vivaldi ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'Vivaldi'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Vivaldi' }
Disable-ServiceSafe -Name 'VivaldiUpdate'

# ══════════════════════════════════════════════
#  OPERA
# ══════════════════════════════════════════════
Write-Host "`n── Opera ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'Opera'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Opera' }
Disable-ServiceSafe -Name 'opera_autoupdate'

# ══════════════════════════════════════════════
#  MOZILLA FIREFOX
# ══════════════════════════════════════════════
Write-Host "`n── Mozilla Firefox ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'Firefox'
Disable-TasksByPattern -Pattern 'Mozilla'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Firefox|Mozilla' }
Disable-ServiceSafe -Name 'MozillaMaintenance'

# Firefox also uses a policies.json to block updates — write it if Firefox is installed
$FirefoxPolicyDirs = @(
    "$env:ProgramFiles\Mozilla Firefox\distribution",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\distribution"
)
$FirefoxPolicy = '{ "policies": { "DisableAppUpdate": true, "DisableTelemetry": true } }'
foreach ($dir in $FirefoxPolicyDirs) {
    if (Test-Path (Split-Path $dir -Parent)) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $FirefoxPolicy | Set-Content "$dir\policies.json" -Encoding UTF8
        Write-Host "  [POLICY WRITTEN]  $dir\policies.json" -ForegroundColor Yellow
    }
}

# ══════════════════════════════════════════════
#  GOOGLE CHROME
# ══════════════════════════════════════════════
Write-Host "`n── Google Chrome ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'GoogleUpdate|Chrome'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Chrome|GoogleUpdate' }
Disable-ServiceSafe -Name 'gupdate'
Disable-ServiceSafe -Name 'gupdatem'

# Chrome also respects a Group Policy / registry flag
$ChromePolicyKey = 'HKLM:\SOFTWARE\Policies\Google\Update'
if (-not (Test-Path $ChromePolicyKey)) { New-Item -Path $ChromePolicyKey -Force | Out-Null }
Set-ItemProperty -Path $ChromePolicyKey -Name 'AutoUpdateCheckPeriodMinutes' -Value 0 -Type DWord
Set-ItemProperty -Path $ChromePolicyKey -Name 'DisableAutoUpdateChecksCheckboxValue' -Value 1 -Type DWord
Write-Host "  [REGISTRY POLICY]  Chrome auto-update disabled via policy key" -ForegroundColor Yellow

# ══════════════════════════════════════════════
#  ANYDESK
# ══════════════════════════════════════════════
Write-Host "`n── AnyDesk ──" -ForegroundColor Magenta

Disable-TasksByPattern -Pattern 'AnyDesk'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'AnyDesk' }
Disable-ServiceSafe -Name 'AnyDesk'

# ══════════════════════════════════════════════
#  NORDVPN
# ══════════════════════════════════════════════
Write-Host "`n── NordVPN ──" -ForegroundColor Magenta

# Note: Do NOT disable 'nordvpn-service' as it is the core engine required for NordVPN to function at all.
# We only disable startup tasks and background updater services.
Disable-TasksByPattern -Pattern 'Nord'
foreach ($k in $RunKeys) { Remove-StartupEntry -KeyPath $k -ValuePattern 'Nord' }
Disable-ServiceSafe -Name 'NordUpdater'
Disable-ServiceSafe -Name 'NordUpdaterService'

# ══════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════
Write-Host "`n✅  Done! All matched auto-start / auto-update tasks, services, and registry entries have been disabled." -ForegroundColor White
Write-Host "    Reboot is NOT required, but a restart will confirm everything is clean." -ForegroundColor Gray
Write-Host "    To RE-ENABLE anything, open Task Scheduler or Services and set them back to 'Ready' / 'Automatic'." -ForegroundColor Gray
