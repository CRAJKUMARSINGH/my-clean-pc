# My Clean PC - Scheduled Cleanup Task (PowerShell)
# Requires clean-pc-core.ps1 in the same folder (e.g. C:\Scripts\)
# Run as SYSTEM via Task Scheduler - shows warning before cleaning
# Downloads folder is intentionally NEVER touched.
# Passwords (Login Data, key4.db) are intentionally NEVER touched.

$ErrorActionPreference = "SilentlyContinue"
$ConfirmPreference = "None"
$ProgressPreference = "SilentlyContinue"
$logFile = Join-Path $PSScriptRoot "cleanup_log.txt"
$tempLogFile = Join-Path $PSScriptRoot "temp_cleaner_log.txt"

$corePath = Join-Path $PSScriptRoot "clean-pc-core.ps1"
if (-not (Test-Path $corePath)) {
    $errLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: clean-pc-core.ps1 not found beside cleanup_task.ps1"
    Add-Content -Path $logFile -Value $errLine -ErrorAction SilentlyContinue
    Add-Content -Path $tempLogFile -Value $errLine -ErrorAction SilentlyContinue
    exit 1
}
. $corePath

# PERF-FIX #25: Buffer log writes — use StreamWriter instead of two Add-Content calls per line.
$script:TaskLogBuffer = [System.Collections.Generic.List[string]]::new()

function Flush-TaskLog {
    if ($script:TaskLogBuffer.Count -eq 0) { return }
    foreach ($lp in @($logFile, $tempLogFile)) {
        try {
            $sw = [System.IO.StreamWriter]::new($lp, $true, [System.Text.Encoding]::UTF8)
            try { foreach ($line in $script:TaskLogBuffer) { $sw.WriteLine($line) } }
            finally { $sw.Close() }
        } catch {}
    }
    $script:TaskLogBuffer.Clear()
}

function Write-Log {
    param([string]$Message)
    $logLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $logLine
    $script:TaskLogBuffer.Add($logLine)
    if ($script:TaskLogBuffer.Count -ge 20) { Flush-TaskLog }
}

# Pre-load MoveFileEx P/Invoke so it is available inside the try block
if (-not ('WC.RBN' -as [type])) {
    try {
        Add-Type `
            -MemberDefinition '[DllImport("Kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool MoveFileEx(string e,string n,int f);' `
            -Name "RBN" `
            -Namespace "WC" `
            -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

# Helper: format byte size for log output
function Format-WupSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:F2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:F1} MB' -f ($Bytes / 1MB)) }
    return "$Bytes B"
}

# Helper: silently delete C:\$WINDOWS.~BT via cmd rd /s /q
function Remove-WindowsUpgradeStaging {
    param([string]$Path)

    # Measure size before deletion
    $sizeBefore = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $sizeBefore += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}

    Write-Log "Found Windows upgrade staging folder: $Path ($(Format-WupSize $sizeBefore)) - taking ownership and deleting..."

    # Take ownership + grant full control to break permission locks
    try { $null = & takeown.exe /f $Path /r /d y 2>$null } catch {}
    try { $null = & icacls.exe $Path /grant "Everyone:(F)" /t /c /q 2>$null } catch {}
    try { $null = & icacls.exe $Path /grant "${env:USERNAME}:(F)" /t /c /q 2>$null } catch {}

    # Silent delete via cmd.exe - no Explorer shell, no dialog
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = 'cmd.exe'
        $psi.Arguments              = "/c rd /s /q `"$Path`" 2>nul"
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $soTask = $proc.StandardOutput.ReadToEndAsync()
        $seTask = $proc.StandardError.ReadToEndAsync()
        try { $proc.StandardInput.Close() } catch {}
        $proc.WaitForExit(120000) | Out-Null
        try { [void]$soTask.Result } catch {}
        try { [void]$seTask.Result } catch {}
    } catch {
        Write-Log "  WARNING: rd /s /q failed - $($_.Exception.Message)"
    }

    if (Test-Path -LiteralPath $Path) {
        # Still present - register for deletion at next reboot
        Write-Log "  PARTIAL: Some files are locked - registering for deletion at next reboot."
        try { [WC.RBN]::MoveFileEx($Path, $null, 4) | Out-Null } catch {}
    } else {
        Write-Log "  SUCCESS: $Path deleted - freed $(Format-WupSize $sizeBefore)"
    }
}

try {
    Write-Log "===== Cleanup Started ====="

    # PERF-FIX #24: Removed unconditional Start-Sleep -Seconds 30 that blocked every run.
    # The toast notification fires immediately; cleaning starts right away.
    try {
        Show-MyCleanPCNotice `
            -Title "My Clean PC - Scheduled Cleaning Starting" `
            -Body "Scheduled cleanup is running now. You can continue using your computer normally." `
            -Log { param([string]$Message) Write-Log $Message }
    } catch {
        Write-Log "Warning notification failed, proceeding with cleanup"
    }

    Invoke-MyCleanPCCore -Log { param([string]$Message) Write-Log $Message } -ManageWindowsUpdateService

    # -----------------------------------------------------------------
    # Windows upgrade staging folder: C:\$WINDOWS.~BT
    # Created by Windows Update when preparing a feature upgrade.
    # Can consume 3-8 GB. Safe to delete when no upgrade is in progress.
    # Requires Admin rights - weekly task runs elevated.
    # -----------------------------------------------------------------
    $wupgradePath = 'C:\$WINDOWS.~BT'
    if (Test-Path -LiteralPath $wupgradePath) {
        Remove-WindowsUpgradeStaging -Path $wupgradePath
    } else {
        Write-Log "Windows upgrade staging folder not present ($wupgradePath) - nothing to clean."
    }

    Write-Log "===== Cleanup Finished ====="
    Flush-TaskLog
} catch {
    Write-Log "===== Cleanup FAILED: $($_.Exception.Message) ====="
    Flush-TaskLog
    try {
        Show-MyCleanPCNotice `
            -Title "My Clean PC stopped" `
            -Body "Cleanup did not finish. You can still use your browsers and AI tools." `
            -Log { param([string]$Message) Write-Log $Message }
    } catch {}
    exit 1
}
