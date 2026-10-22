#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a scheduled task that re-asserts the on-demand startup policy.

.DESCRIPTION
    AnyDesk and Bentley updaters love re-adding their Run entries. This task
    re-runs startup-guard.ps1 on a schedule so autostart stays off.

.PARAMETER Schedule
    Weekly (default) | Daily | AtLogOn

.PARAMETER Time
    Trigger time for Daily/Weekly. Default 12:00.

.PARAMETER Remove
    Unregister the task instead of creating it.

.EXAMPLE
    .\create-startup-guard-task.ps1
.EXAMPLE
    .\create-startup-guard-task.ps1 -Schedule Daily -Time 09:30
.EXAMPLE
    .\create-startup-guard-task.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$TaskName = 'My-Clean-PC\Startup Guard',
    [ValidateSet('Weekly', 'Daily', 'AtLogOn')]
    [string]$Schedule = 'Weekly',
    [string]$Time = '12:00',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges to manage scheduled task '$TaskName'..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-TaskName', "`"$TaskName`"", '-Schedule', $Schedule, '-Time', $Time)
    if ($Remove) { $argList += '-Remove' }
    $p = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

if ($Remove) {
    $existing = Get-ScheduledTask -TaskName (Split-Path $TaskName -Leaf) -TaskPath ('\' + (Split-Path $TaskName -Parent) + '\') -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $existing.TaskName -TaskPath $existing.TaskPath -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'" -ForegroundColor Green
    }
    else { Write-Host "Scheduled task '$TaskName' not found" -ForegroundColor Yellow }
    return
}

$guard = Join-Path $PSScriptRoot 'startup-guard.ps1'
if (-not (Test-Path -LiteralPath $guard)) { throw "startup-guard.ps1 not found next to this script." }

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action Disable -Quiet' -f $guard)

switch ($Schedule) {
    'Daily'   { $trigger = New-ScheduledTaskTrigger -Daily -At $Time }
    'Weekly'  { $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $Time }
    'AtLogOn' { $trigger = New-ScheduledTaskTrigger -AtLogOn }
}

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

$taskPath = '\' + (Split-Path $TaskName -Parent) + '\'
$name     = Split-Path $TaskName -Leaf

Register-ScheduledTask -TaskName $name -TaskPath $taskPath `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Registered scheduled task '$TaskName' ($Schedule)" -ForegroundColor Green
