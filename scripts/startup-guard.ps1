#Requires -Version 5.1
<#
.SYNOPSIS
    Startup Guard - forces selected apps to start ONLY when the user starts them.

.DESCRIPTION
    Part of My-Clean-PC. Single source of truth for "on-demand only" enforcement.

    Managed targets:
        AnyDesk  - tray app, Run entry, AnyDesk service
        Bentley  - CONNECTION Client, License Service, SPC Server

    Autostart vectors neutralised:
        1. Windows services (Win32_Service)   -> StartMode Manual (Disabled with -Hard)
        2. HKLM/HKCU Run + RunOnce values     -> value removed, backed up
        3. Startup folder .lnk shortcuts      -> renamed *.lnk.disabled
        4. Scheduled Tasks                    -> Disabled

    Every change is recorded in a JSON restore point so -Action Enable restores
    the machine exactly as it was.

.PARAMETER Action
    Disable  Turn autostart OFF (default)
    Enable   Restore the state saved by the last Disable run
    Status   Report only, change nothing

.PARAMETER Target
    All (default) | AnyDesk | Bentley

.PARAMETER Hard
    Services become Disabled instead of Manual. Use when you never want the
    service running unless you start it yourself.

.PARAMETER StopNow
    Also stop matched services and close matched processes after disabling.

.PARAMETER Quiet
    No console output - suitable for scheduled task runs.

.EXAMPLE
    .\startup-guard.ps1 -Action Status
.EXAMPLE
    .\startup-guard.ps1 -Action Disable -Target AnyDesk -StopNow
.EXAMPLE
    .\startup-guard.ps1 -Action Enable
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Disable', 'Enable', 'Status')]
    [string]$Action = 'Disable',

    [ValidateSet('All', 'AnyDesk', 'Bentley')]
    [string[]]$Target = @('All'),

    [switch]$Hard,
    [switch]$StopNow,
    [switch]$Quiet,

    [string]$RestorePointPath = (Join-Path $env:ProgramData 'My-Clean-PC\startup-guard.json'),
    [string]$LogPath          = (Join-Path $env:ProgramData 'My-Clean-PC\startup-guard.log')
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------- definitions
$TargetDefs = @{
    AnyDesk = [pscustomobject]@{
        Id           = 'AnyDesk'
        Label        = 'AnyDesk'
        ExeNames     = @('AnyDesk.exe')
        ServiceNames = @('AnyDesk')
        Paths        = @(
            (Join-Path $env:ProgramFiles 'AnyDesk\AnyDesk.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'AnyDesk\AnyDesk.exe')
        )
    }
    Bentley = [pscustomobject]@{
        Id           = 'Bentley'
        Label        = 'Bentley (CONNECTION Client / License Service / SPC Server)'
        ExeNames     = @(
            'Bentley.Connect.Client.exe',
            'Bentley.Licensing.Service.exe',
            'Bentley.Structural.PropertyCatalog.Server.exe'
        )
        ServiceNames = @(
            'Bentley Licensing Service',
            'BentleyLicenseService',
            'Bentley Property Catalog Service',
            'Bentley SPC Server'
        )
        Paths        = @(
            (Join-Path $env:ProgramFiles 'Common Files\Bentley Shared\CONNECTION Client\Bentley.Connect.Client.exe'),
            (Join-Path $env:ProgramFiles 'Common Files\Bentley Shared\CONNECTION Client\LicenseService\Bentley.Licensing.Service.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Bentley\Engineering\SPC Server v8i SS4\Bentley.Structural.PropertyCatalog.Server.exe')
        )
    }
}

$RunKeyPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)

$StartModeMap = @{
    'Auto' = 'Automatic'; 'Automatic' = 'Automatic'; 'Manual' = 'Manual'
    'Disabled' = 'Disabled'; 'Boot' = 'Automatic'; 'System' = 'Automatic'
}

$script:Changes = @{ Services = @(); RunValues = @(); Shortcuts = @(); Tasks = @() }

# ------------------------------------------------------------------- helpers
function Write-GLog {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERR')][string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $Quiet) {
        switch ($Level) {
            'OK'    { Write-Host $line -ForegroundColor Green }
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'ERR'   { Write-Host $line -ForegroundColor Red }
            default { Write-Host $line }
        }
    }
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch { }
}

function Get-TargetSet {
    param([string[]]$Names)
    if ($Names -contains 'All') { $Names = @('AnyDesk', 'Bentley') }
    $out = @()
    foreach ($n in $Names) { if ($TargetDefs.ContainsKey($n)) { $out += $TargetDefs[$n] } }
    return $out
}

function Test-MatchText {
    param([string]$Text, [object[]]$Targets)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    foreach ($t in $Targets) {
        foreach ($p in $t.Paths) {
            if ($Text.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
        foreach ($e in $t.ExeNames) {
            if ($Text.IndexOf($e, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
    }
    return $false
}

function Test-MatchServiceName {
    param([string]$Name, [object[]]$Targets)
    foreach ($t in $Targets) { if ($t.ServiceNames -contains $Name) { return $true } }
    return $false
}

function Find-Autostart {
    param([object[]]$Targets)

    $found = @{ Services = @(); RunValues = @(); Shortcuts = @(); Tasks = @() }

    # 1 - services
    foreach ($svc in (Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue)) {
        if ((Test-MatchServiceName -Name $svc.Name -Targets $Targets) -or
            (Test-MatchText -Text $svc.PathName -Targets $Targets)) {
            $found.Services += [pscustomobject]@{
                Name = $svc.Name; DisplayName = $svc.DisplayName
                PathName = $svc.PathName; StartMode = $svc.StartMode; State = $svc.State
            }
        }
    }

    # 2 - Run / RunOnce
    foreach ($rk in $RunKeyPaths) {
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
            if (Test-MatchText -Text ([string]$p.Value) -Targets $Targets) {
                $found.RunValues += [pscustomobject]@{ Key = $rk; Name = $p.Name; Value = [string]$p.Value }
            }
        }
    }

    # 3 - Startup folder shortcuts
    $folders = @()
    try { $folders += [Environment]::GetFolderPath('CommonStartup') } catch { }
    try { $folders += [Environment]::GetFolderPath('Startup') } catch { }
    $wsh = $null
    try { $wsh = New-Object -ComObject WScript.Shell } catch { }
    foreach ($f in ($folders | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
        foreach ($lnk in (Get-ChildItem -LiteralPath $f -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
            $tgt = ''
            if ($wsh) { try { $tgt = $wsh.CreateShortcut($lnk.FullName).TargetPath } catch { } }
            if ((Test-MatchText -Text $tgt -Targets $Targets) -or
                (Test-MatchText -Text $lnk.Name -Targets $Targets)) {
                $found.Shortcuts += [pscustomobject]@{ Path = $lnk.FullName; Target = $tgt }
            }
        }
    }

    # 4 - scheduled tasks
    foreach ($task in (Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        foreach ($a in $task.Actions) {
            if (-not $a.Execute) { continue }
            if (Test-MatchText -Text ([string]$a.Execute) -Targets $Targets) {
                $found.Tasks += [pscustomobject]@{
                    TaskPath = $task.TaskPath
                    TaskName = $task.TaskName
                    FullName = ('{0}{1}' -f $task.TaskPath, $task.TaskName)
                    State    = [string]$task.State
                    Execute  = [string]$a.Execute
                }
                break
            }
        }
    }

    return $found
}

function Import-RestorePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try { $existing = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return }

    foreach ($s in $existing.Changes.Services) {
        if (-not (@($script:Changes.Services | Where-Object { $_.Name -eq $s.Name }).Count)) {
            $script:Changes.Services += $s
        }
    }
    foreach ($r in $existing.Changes.RunValues) {
        if (-not (@($script:Changes.RunValues | Where-Object { "$($_.Key)|$($_.Name)" -eq "$($r.Key)|$($r.Name)" }).Count)) {
            $script:Changes.RunValues += $r
        }
    }
    foreach ($c in $existing.Changes.Shortcuts) {
        if (-not (@($script:Changes.Shortcuts | Where-Object { $_.OriginalPath -eq $c.OriginalPath }).Count)) {
            $script:Changes.Shortcuts += $c
        }
    }
    foreach ($t in $existing.Changes.Tasks) {
        if (-not (@($script:Changes.Tasks | Where-Object { $_.FullName -eq $t.FullName }).Count)) {
            $script:Changes.Tasks += $t
        }
    }
}

function Save-RestorePoint {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $payload = [pscustomobject]@{
        SchemaVersion = 1
        CreatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        Computer      = $env:COMPUTERNAME
        User          = "$env:USERDOMAIN\$env:USERNAME"
        Changes       = $script:Changes
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-GLog "Restore point written: $Path" 'OK'
}

# ------------------------------------------------------------------- actions
function Invoke-Disable {
    param([object]$Found, [switch]$Hard, [switch]$StopNow)

    $desiredMode = if ($Hard) { 'Disabled' } else { 'Manual' }

    if ($Found.Services.Count) {
        Write-GLog "--- Services -> $desiredMode ---"
        foreach ($s in $Found.Services) {
            if ($s.StartMode -eq $desiredMode) {
                Write-GLog "Service '$($s.Name)' already $desiredMode - skipped"
            }
            elseif ($PSCmdlet.ShouldProcess("Service '$($s.Name)'", "StartMode $($s.StartMode) -> $desiredMode")) {
                Set-Service -Name $s.Name -StartupType $desiredMode -ErrorAction Stop
                $script:Changes.Services += [pscustomobject]@{ Name = $s.Name; OriginalStartMode = $s.StartMode }
                Write-GLog "Service '$($s.Name)': $($s.StartMode) -> $desiredMode" 'OK'
            }
            if ($StopNow -and $s.State -eq 'Running') {
                try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Write-GLog "Service '$($s.Name)' stopped" 'OK' }
                catch { Write-GLog "Could not stop '$($s.Name)': $($_.Exception.Message)" 'WARN' }
            }
        }
    }

    if ($Found.RunValues.Count) {
        Write-GLog '--- Run / RunOnce values -> quarantined ---'
        foreach ($r in $Found.RunValues) {
            if ($PSCmdlet.ShouldProcess("$($r.Key) :: $($r.Name)", 'Remove autostart value')) {
                Remove-ItemProperty -LiteralPath $r.Key -Name $r.Name -ErrorAction SilentlyContinue
                $script:Changes.RunValues += $r
                Write-GLog "Removed $($r.Key) :: $($r.Name)" 'OK'
            }
        }
    }

    if ($Found.Shortcuts.Count) {
        Write-GLog '--- Startup folder shortcuts -> *.lnk.disabled ---'
        foreach ($c in $Found.Shortcuts) {
            $newPath = '{0}.disabled' -f $c.Path
            if ($PSCmdlet.ShouldProcess($c.Path, "Rename to $newPath")) {
                Move-Item -LiteralPath $c.Path -Destination $newPath -Force
                $script:Changes.Shortcuts += [pscustomobject]@{ OriginalPath = $c.Path; DisabledPath = $newPath }
                Write-GLog "Renamed $($c.Path)" 'OK'
            }
        }
    }

    if ($Found.Tasks.Count) {
        Write-GLog '--- Scheduled tasks -> disabled ---'
        foreach ($t in $Found.Tasks) {
            if ($t.State -eq 'Disabled') {
                Write-GLog "Task '$($t.FullName)' already disabled - skipped"
            }
            elseif ($PSCmdlet.ShouldProcess($t.FullName, 'Disable scheduled task')) {
                Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName | Out-Null
                $script:Changes.Tasks += [pscustomobject]@{ TaskPath = $t.TaskPath; TaskName = $t.TaskName; FullName = $t.FullName }
                Write-GLog "Disabled task '$($t.FullName)'" 'OK'
            }
        }
    }
}

function Invoke-Enable {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-GLog "No restore point at $Path - nothing to restore" 'WARN'
        return
    }
    $rp = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    foreach ($s in $rp.Changes.Services) {
        $mode = $StartModeMap[[string]$s.OriginalStartMode]
        if (-not $mode) { $mode = 'Automatic' }
        if ($PSCmdlet.ShouldProcess("Service '$($s.Name)'", "Restore StartMode -> $mode")) {
            try { Set-Service -Name $s.Name -StartupType $mode -ErrorAction Stop; Write-GLog "Service '$($s.Name)' -> $mode" 'OK' }
            catch { Write-GLog "Failed restoring '$($s.Name)': $($_.Exception.Message)" 'WARN' }
        }
    }

    foreach ($r in $rp.Changes.RunValues) {
        if ($PSCmdlet.ShouldProcess("$($r.Key) :: $($r.Name)", 'Restore autostart value')) {
            if (-not (Test-Path -LiteralPath $r.Key)) { New-Item -Path $r.Key -Force | Out-Null }
            Set-ItemProperty -LiteralPath $r.Key -Name $r.Name -Value $r.Value -Type String -Force
            Write-GLog "Restored $($r.Key) :: $($r.Name)" 'OK'
        }
    }

    foreach ($c in $rp.Changes.Shortcuts) {
        if (Test-Path -LiteralPath $c.DisabledPath) {
            Move-Item -LiteralPath $c.DisabledPath -Destination $c.OriginalPath -Force
            Write-GLog "Restored shortcut $($c.OriginalPath)" 'OK'
        }
    }

    foreach ($t in $rp.Changes.Tasks) {
        if ($PSCmdlet.ShouldProcess($t.FullName, 'Re-enable scheduled task')) {
            try { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName | Out-Null; Write-GLog "Enabled task '$($t.FullName)'" 'OK' }
            catch { Write-GLog "Failed enabling '$($t.FullName)': $($_.Exception.Message)" 'WARN' }
        }
    }
}

function Show-Status {
    param([object[]]$Targets)

    $found = Find-Autostart -Targets $Targets

    Write-GLog '=== Services ==='
    if ($found.Services.Count) {
        $found.Services | Select-Object Name, DisplayName, StartMode, State | Format-Table -AutoSize | Out-String | Write-Host
    } else { Write-Host '  (none matched)' }

    Write-GLog '=== Run / RunOnce ==='
    if ($found.RunValues.Count) {
        $found.RunValues | Select-Object Key, Name, Value | Format-Table -AutoSize | Out-String | Write-Host
    } else { Write-Host '  (none matched)' }

    Write-GLog '=== Startup folder ==='
    if ($found.Shortcuts.Count) {
        $found.Shortcuts | Select-Object Path, Target | Format-Table -AutoSize | Out-String | Write-Host
    } else { Write-Host '  (none matched)' }

    Write-GLog '=== Scheduled tasks ==='
    if ($found.Tasks.Count) {
        $found.Tasks | Select-Object FullName, State, Execute | Format-Table -AutoSize | Out-String | Write-Host
    } else { Write-Host '  (none matched)' }

    Write-GLog ('Total: {0} service(s), {1} run value(s), {2} shortcut(s), {3} task(s)' -f
        $found.Services.Count, $found.RunValues.Count, $found.Shortcuts.Count, $found.Tasks.Count)
}

# ---------------------------------------------------------------------- main
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Action -ne 'Status') {
        Write-GLog 'Requesting Administrator privileges to modify system services and HKLM registry...' 'INFO'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Action', $Action)
        if ($Hard) { $argList += '-Hard' }
        if ($StopNow) { $argList += '-StopNow' }
        if ($Quiet) { $argList += '-Quiet' }
        foreach ($t in $Target) { $argList += @('-Target', $t) }
        try {
            $p = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -Wait -PassThru
            exit $p.ExitCode
        } catch {
            Write-GLog "Elevation failed or was cancelled: $($_.Exception.Message)" 'ERR'
            exit 1
        }
    } else {
        Write-GLog 'Not elevated - HKLM Run values and services may fail. Re-run as Administrator.' 'WARN'
    }
}

$targets = Get-TargetSet -Names $Target

switch ($Action) {
    'Status' {
        Show-Status -Targets $targets
    }
    'Disable' {
        Write-GLog ('Startup Guard: DISABLE ({0})' -f (($targets | ForEach-Object { $_.Id }) -join ', '))
        $found = Find-Autostart -Targets $targets
        Import-RestorePoint -Path $RestorePointPath
        Invoke-Disable -Found $found -Hard:$Hard -StopNow:$StopNow
        Save-RestorePoint -Path $RestorePointPath
        Write-GLog 'Done. Run "start-on-demand.ps1" whenever you want the apps.' 'OK'
    }
    'Enable' {
        Write-GLog 'Startup Guard: ENABLE (restoring saved autostart state)'
        Invoke-Enable -Path $RestorePointPath
        Write-GLog 'Done.' 'OK'
    }
}
