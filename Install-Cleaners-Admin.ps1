# My Clean PC - Universal Installer Script
# Supports installing Both tasks (7Min + Weekly), 7-Minute only, 24-Minute only, or Weekly only
# Usage:
#   powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task Both
#   powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task 7Min
#   powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task 24Min
#   powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task Weekly

param(
    [ValidateSet("Both", "7Min", "24Min", "Weekly")]
    [string]$Task = "Both"
)

$ErrorActionPreference = "Stop"

# Self-elevate if not running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges to install Windows Scheduled Tasks..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Task $Task" -Verb RunAs -Wait
    exit
}

$InstallDir = "$env:LOCALAPPDATA\MyCleanPC"
$RepoRoot   = Split-Path -Parent $PSCommandPath
$ScriptsDir = Join-Path $RepoRoot "scripts"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Write-Host "1. Copying cleaner scripts to $InstallDir..." -ForegroundColor Cyan
Copy-Item -Force (Join-Path $ScriptsDir "Safe-Cleanup-Engine.ps1") (Join-Path $InstallDir "Safe-Cleanup-Engine.ps1")
Copy-Item -Force (Join-Path $ScriptsDir "ai-cache-cleaner.ps1") (Join-Path $InstallDir "ai-cache-cleaner.ps1")
Copy-Item -Force (Join-Path $ScriptsDir "clean-pc-core.ps1") (Join-Path $InstallDir "clean-pc-core.ps1")
Copy-Item -Force (Join-Path $ScriptsDir "cleanup_task.ps1") (Join-Path $InstallDir "cleanup_task.ps1")

# Register session-log 12-minute update task
$sessionLogScript = Join-Path $RepoRoot ".kiro\hooks\update-session-log.ps1"
if (Test-Path $sessionLogScript) {
    Write-Host "1a. Registering Task: MyCleanPC-SessionLog-12Min..." -ForegroundColor Cyan
    $slTaskName = "MyCleanPC-SessionLog-12Min"
    $slAction   = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$sessionLogScript`" -RepoRoot `"$RepoRoot`""
    $slStartAt  = (Get-Date).AddMinutes(1)
    $slTrigger  = New-ScheduledTaskTrigger -Once -At $slStartAt `
                    -RepetitionInterval (New-TimeSpan -Minutes 12) `
                    -RepetitionDuration (New-TimeSpan -Days 9999)
    $slSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                    -MultipleInstances IgnoreNew -StartWhenAvailable `
                    -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -Priority 7
    Unregister-ScheduledTask -TaskName $slTaskName -Confirm:$false -ErrorAction SilentlyContinue
    try {
        Register-ScheduledTask -TaskName $slTaskName -Action $slAction -Trigger $slTrigger `
            -Settings $slSettings -Principal $principal -Force | Out-Null
        Write-Host "  MyCleanPC-SessionLog-12Min registered (updates creat.md + README.md every 12 min)." -ForegroundColor Green
    } catch {
        Write-Host "  Warning: Could not register session log task: $_" -ForegroundColor Yellow
    }
}
# Create Interactive user principal for background task execution so user %LOCALAPPDATA% and browser caches are accessed
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

$install7Min   = ($Task -eq "Both" -or $Task -eq "7Min")
$install24Min  = ($Task -eq "24Min")
$installWeekly = ($Task -eq "Both" -or $Task -eq "Weekly")

# --- TASK 1A: 7-Minute Interval Cleaner ---
if ($install7Min) {
    Write-Host "2. Registering Task: MyCleanPC-7Min (Runs every 7 minutes)..." -ForegroundColor Cyan
    $Task1Name   = "MyCleanPC-7Min"
    $Task1Script = Join-Path $InstallDir "ai-cache-cleaner.ps1"
    $Action1     = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Task1Script`""
    $StartAt1    = (Get-Date).AddMinutes(1)
    $Trigger1    = New-ScheduledTaskTrigger -Once -At $StartAt1 -RepetitionInterval (New-TimeSpan -Minutes 7) -RepetitionDuration (New-TimeSpan -Days 9999)
    $Settings1   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -Priority 7

    Unregister-ScheduledTask -TaskName $Task1Name -Confirm:$false -ErrorAction SilentlyContinue
    try {
        Register-ScheduledTask -TaskName $Task1Name -Action $Action1 -Trigger $Trigger1 -Settings $Settings1 -Principal $principal -Force | Out-Null
        Write-Host "  MyCleanPC-7Min registered cleanly via PowerShell API (User: $currentUser)." -ForegroundColor Green
    } catch {
        Write-Host "  Retrying MyCleanPC-7Min via schtasks.exe..." -ForegroundColor Yellow
        $tr1 = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Task1Script`""
        $startAtStr = (Get-Date).AddMinutes(1).ToString('HH:mm')
        & schtasks.exe /Create /TN $Task1Name /TR $tr1 /SC ONCE /ST $startAtStr /RI 7 /DU 9999:00 /RU $currentUser /RL HIGHEST /F | Out-Null
    }
}

# --- TASK 1B: 24-Minute Interval Cleaner ---
if ($install24Min) {
    Write-Host "2. Registering Task: MyCleanPC-24Min (Runs every 24 minutes)..." -ForegroundColor Cyan
    $Task1Name   = "MyCleanPC-24Min"
    $Task1Script = Join-Path $InstallDir "ai-cache-cleaner.ps1"
    $Action1     = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Task1Script`""
    $StartAt1    = (Get-Date).AddMinutes(2)
    $Trigger1    = New-ScheduledTaskTrigger -Once -At $StartAt1 -RepetitionInterval (New-TimeSpan -Minutes 24) -RepetitionDuration (New-TimeSpan -Days 9999)
    $Settings1   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -Priority 7

    Unregister-ScheduledTask -TaskName $Task1Name -Confirm:$false -ErrorAction SilentlyContinue
    try {
        Register-ScheduledTask -TaskName $Task1Name -Action $Action1 -Trigger $Trigger1 -Settings $Settings1 -Principal $principal -Force | Out-Null
        Write-Host "  MyCleanPC-24Min registered cleanly via PowerShell API (User: $currentUser)." -ForegroundColor Green
    } catch {
        Write-Host "  Retrying MyCleanPC-24Min via schtasks.exe..." -ForegroundColor Yellow
        $tr1 = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Task1Script`""
        $startAtStr = (Get-Date).AddMinutes(2).ToString('HH:mm')
        & schtasks.exe /Create /TN $Task1Name /TR $tr1 /SC ONCE /ST $startAtStr /RI 24 /DU 9999:00 /RU $currentUser /RL HIGHEST /F | Out-Null
    }
}

# --- TASK 2: Weekly (7-Day) Cleaner ---
if ($installWeekly) {
    Write-Host "3. Registering Task: MyCleanPC-Weekly (Runs every Monday at 9:00 AM)..." -ForegroundColor Cyan
    $Task2Name   = "MyCleanPC-Weekly"
    $Task2Script = Join-Path $InstallDir "cleanup_task.ps1"
    $Action2     = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Task2Script`""
    $Trigger2    = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "09:00AM"
    $Settings2   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -Priority 7

    Unregister-ScheduledTask -TaskName $Task2Name -Confirm:$false -ErrorAction SilentlyContinue
    try {
        Register-ScheduledTask -TaskName $Task2Name -Action $Action2 -Trigger $Trigger2 -Settings $Settings2 -Principal $principal -Force | Out-Null
        Write-Host "  MyCleanPC-Weekly registered cleanly via PowerShell API (User: $currentUser)." -ForegroundColor Green
    } catch {
        Write-Host "  Retrying MyCleanPC-Weekly via schtasks.exe..." -ForegroundColor Yellow
        $tr2 = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Task2Script`""
        & schtasks.exe /Create /TN $Task2Name /TR $tr2 /SC WEEKLY /D MON /ST 09:00 /RU $currentUser /RL HIGHEST /F | Out-Null
    }
}

# --- VERIFICATION ---
Write-Host "4. Verifying task registration..." -ForegroundColor Cyan
$t7  = Get-ScheduledTask -TaskName "MyCleanPC-7Min"      -ErrorAction SilentlyContinue
$t1  = Get-ScheduledTask -TaskName "MyCleanPC-24Min"     -ErrorAction SilentlyContinue
$t2  = Get-ScheduledTask -TaskName "MyCleanPC-Weekly"    -ErrorAction SilentlyContinue
$tsl = Get-ScheduledTask -TaskName "MyCleanPC-SessionLog-12Min" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " SUCCESS: CLEANER INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
if ($t7)  { Write-Host " Task: MyCleanPC-7Min             -> Every 7 Minutes [State: $($t7.State)]" -ForegroundColor White }
if ($t1)  { Write-Host " Task: MyCleanPC-24Min            -> Every 24 Minutes [State: $($t1.State)]" -ForegroundColor White }
if ($t2)  { Write-Host " Task: MyCleanPC-Weekly           -> Every Week [State: $($t2.State)]" -ForegroundColor White }
if ($tsl) { Write-Host " Task: MyCleanPC-SessionLog-12Min -> Every 12 Min [State: $($tsl.State)]" -ForegroundColor White }
Write-Host " Mode: Silent background execution when PC is ON" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
