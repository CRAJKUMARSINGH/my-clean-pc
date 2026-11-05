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

function Write-Log {
    param([string]$Message)
    $logLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $logLine
    Add-Content -Path $logFile -Value $logLine -ErrorAction SilentlyContinue
    Add-Content -Path $tempLogFile -Value $logLine -ErrorAction SilentlyContinue
}

try {
    Write-Log "===== Cleanup Started ====="
    
    # Show warning before cleaning starts
    try {
        Show-MyCleanPCNotice -Title "My Clean PC - Scheduled Cleaning Starting" -Body "Scheduled cleanup will begin in 30 seconds. You can continue using your computer normally." -Log { param([string]$Message) Write-Log $Message }
        Start-Sleep -Seconds 30
    } catch {
        Write-Log "Warning notification failed, proceeding with cleanup"
    }
    
    Invoke-MyCleanPCCore -Log { param([string]$Message) Write-Log $Message } -ManageWindowsUpdateService

    # ── Windows Upgrade Staging Folder ────────────────────────────────────────
    # C:\$WINDOWS.~BT is created by Windows Update when preparing a feature
    # upgrade. It can consume 3-8 GB and is safe to delete once the upgrade is
    # not actively in progress. Requires Admin rights (weekly task runs elevated).
    $wupgradePath = 'C:\$WINDOWS.~BT'
    if (Test-Path -LiteralPath $wupgradePath) {
        Write-Log "Found Windows upgrade staging folder: $wupgradePath — measuring size..."
        $sizeBefore = [long]0
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($wupgradePath, '*', [System.IO.SearchOption]::AllDirectories)) {
                try { $sizeBefore += ([System.IO.FileInfo]$f).Length } catch {}
            }
        } catch {}
        $sizeLabel = if ($sizeBefore -ge 1GB) { '{0:F2} GB' -f ($sizeBefore / 1GB) } `
                     elseif ($sizeBefore -ge 1MB) { '{0:F1} MB' -f ($sizeBefore / 1MB) } `
                     else { "$sizeBefore B" }
        Write-Log "  Size: $sizeLabel — taking ownership and deleting..."
        try {
            # Take ownership + grant full control so rd /s /q can proceed
            $null = & takeown.exe /f $wupgradePath /r /d y 2>$null
            $null = & icacls.exe $wupgradePath /grant "Everyone:(F)" /t /c /q 2>$null
            $null = & icacls.exe $wupgradePath /grant "${env:USERNAME}:(F)" /t /c /q 2>$null
            # Silent delete via cmd so no Explorer dialog appears
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName        = 'cmd.exe'
            $psi.Arguments       = "/c rd /s /q `"$wupgradePath`" 2>nul"
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow  = $true
            $psi.RedirectStandardInput  = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            [void]$proc.Start()
            $soTask = $proc.StandardOutput.ReadToEndAsync()
            $seTask = $proc.StandardError.ReadToEndAsync()
            try { $proc.StandardInput.Close() } catch {}
            $proc.WaitForExit(120000) | Out-Null
            try { [void]$soTask.Result } catch {}
            try { [void]$seTask.Result } catch {}
        } catch {
            Write-Log "  WARNING: Delete encountered an error: $($_.Exception.Message)"
        }
        if (Test-Path -LiteralPath $wupgradePath) {
            Write-Log "  PARTIAL: Some files remain locked — folder will be removed on next reboot (MoveFileEx registered)."
            try {
                Add-Type -MemberDefinition '[DllImport("Kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool MoveFileEx(string e,string n,int f);' -Name "RBN" -Namespace "WC" -ErrorAction SilentlyContinue | Out-Null
                [WC.RBN]::MoveFileEx($wupgradePath, $null, 4) | Out-Null
            } catch {}
        } else {
            Write-Log "  SUCCESS: $wupgradePath deleted — freed $sizeLabel"
        }
    } else {
        Write-Log "Windows upgrade staging folder not present ($wupgradePath) — nothing to clean."
    }
    # ─────────────────────────────────────────────────────────────────────────

    Write-Log "===== Cleanup Finished ====="
} catch {
    Write-Log "===== Cleanup FAILED: $($_.Exception.Message) ====="
    try {
        Show-MyCleanPCNotice -Title "My Clean PC stopped" -Body "Cleanup did not finish. You can still use your browsers and AI tools." -Log { param([string]$Message) Write-Log $Message }
    } catch {}
    exit 1
}
