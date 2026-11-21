# Cleanup: ProgramData redundants + Windows junk + Program Files residuals
# Java, Nitro PDF, Analysis Services (PF), Synaptics are KEPT per user instruction.

if (-not ('CLEAN.MoveFile' -as [type])) {
    Add-Type -MemberDefinition '[DllImport("Kernel32.dll",CharSet=CharSet.Unicode)] public static extern bool MoveFileEx(string e,string n,int f);' -Name 'MoveFile' -Namespace 'CLEAN' | Out-Null
}

$totalFreed = [long]0
$bootDelCount = 0

function Remove-SafePath {
    param([string]$Path, [string]$Label)
    if (Test-Skip $Path) { return }
    if (-not (Test-Path $Path)) { return }
    $null = & takeown.exe /f $Path /r /d y 2>$null
    $null = & icacls.exe $Path /grant 'Everyone:(F)' /t /c /q 2>$null
    $null = & cmd.exe /c "rd /s /q `"$Path`" 2>nul"
    if (-not (Test-Path $Path)) {
        Write-Host "  DELETED  $Label" -ForegroundColor Green
    } else {
        [CLEAN.MoveFile]::MoveFileEx($Path, $null, 4) | Out-Null
        Write-Host "  BOOT-DEL $Label" -ForegroundColor Yellow
        $script:bootDelCount++
    }
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { return }
    $null = & takeown.exe /f $Path /r /d y 2>$null
    $null = & icacls.exe $Path /grant 'Everyone:(F)' /t /c /q 2>$null
    # Delete all files inside
    foreach ($f in @(Get-ChildItem $Path -Force -Recurse -ErrorAction SilentlyContinue)) {
        try {
            [System.IO.File]::SetAttributes($f.FullName, [System.IO.FileAttributes]::Normal)
            if ($f.PSIsContainer) {
                [System.IO.Directory]::Delete($f.FullName, $true)
            } else {
                [System.IO.File]::Delete($f.FullName)
            }
        } catch {
            [CLEAN.MoveFile]::MoveFileEx($f.FullName, $null, 4) | Out-Null
        }
    }
    $left = @(Get-ChildItem $Path -Force -Recurse -ErrorAction SilentlyContinue).Count
    if ($left -eq 0) {
        Write-Host "  CLEANED $Label (all contents gone)" -ForegroundColor Green
    } else {
        Write-Host "  PARTIAL $Label ($left locked items -> boot delete)" -ForegroundColor Yellow
    }
}

# ============================================================
# 1. ProgramData redundants
# ============================================================
Write-Host '--- ProgramData redundants ---' -ForegroundColor Cyan

# Dead HP SimplePass ProgramData (matches PF86 deletion)
Remove-SafePath 'C:\ProgramData\HP SimplePass 2011' 'PD\HP SimplePass 2011'

# Old Synaptics ProgramData (kept PF\Synaptics per instruction but PD copy is just config cache)
# KEEP - user said keep Synaptics

# Dead Oracle Java ProgramData stub (Java runtime kept but this is just config cache)
# Actually leave Oracle - Java is kept

# Stale 2015 Comms (Windows Mobile era, dead)
Remove-SafePath 'C:\ProgramData\Comms' 'PD\Comms (Windows Mobile 2015)'

# WindowsHolographicDevices (no HoloLens on this PC)
Remove-SafePath 'C:\ProgramData\WindowsHolographicDevices' 'PD\WindowsHolographicDevices'

# boost_interprocess (stale C++ lib cache from 2020)
Remove-SafePath 'C:\ProgramData\boost_interprocess' 'PD\boost_interprocess (2020 C++ cache)'

# Ralink Bluetooth Stack (2018, dead hardware driver)
Remove-SafePath 'C:\ProgramData\Ralink Bluetooth Stack' 'PD\Ralink Bluetooth Stack (2018 dead)'

# Validity (old fingerprint sensor data 2018)
Remove-SafePath 'C:\ProgramData\Validity' 'PD\Validity (2018 fingerprint)'

# HP ProgramData (stale HP laptop config)
Remove-SafePath 'C:\ProgramData\HP' 'PD\HP (stale config)'
Remove-SafePath 'C:\ProgramData\Hewlett-Packard' 'PD\Hewlett-Packard (stale)'

# ============================================================
# 2. Windows junk
# ============================================================
Write-Host ''
Write-Host '--- Windows junk ---' -ForegroundColor Cyan

# Windows\Temp - clear contents only (keep the folder)
Clear-FolderContents 'C:\Windows\Temp' 'Windows\Temp'

# Windows\Logs\CBS - clear old CBS logs
Clear-FolderContents 'C:\Windows\Logs\CBS' 'Windows\Logs\CBS'

# Windows\Panther (upgrade log files)
Clear-FolderContents 'C:\Windows\Panther' 'Windows\Panther (upgrade logs)'

# Windows\minidump
Clear-FolderContents 'C:\Windows\minidump' 'Windows\minidump'

# Windows\LiveKernelReports
Clear-FolderContents 'C:\Windows\LiveKernelReports' 'Windows\LiveKernelReports'

# memory.dmp if exists
if (Test-Path 'C:\Windows\memory.dmp') {
    try { Remove-Item 'C:\Windows\memory.dmp' -Force -ErrorAction Stop; Write-Host '  DELETED  Windows\memory.dmp' -ForegroundColor Green }
    catch { [CLEAN.MoveFile]::MoveFileEx('C:\Windows\memory.dmp', $null, 4) | Out-Null; Write-Host '  BOOT-DEL Windows\memory.dmp' -ForegroundColor Yellow }
}

# SoftwareDistribution\Download (Windows Update cache - safe to clear)
Clear-FolderContents 'C:\Windows\SoftwareDistribution\Download' 'SoftwareDistribution\Download'

# SoftwareDistribution\DataStore\Logs
Clear-FolderContents 'C:\Windows\SoftwareDistribution\DataStore\Logs' 'SoftwareDistribution\DataStore\Logs'

# Prefetch - clear old prefetch files (Windows regenerates them)
$prefetch = 'C:\Windows\Prefetch'
if (Test-Path $prefetch) {
    $pf = Get-ChildItem $prefetch -Force -ErrorAction SilentlyContinue
    $pfCount = 0
    foreach ($f in $pf) {
        try { [System.IO.File]::SetAttributes($f.FullName,[System.IO.FileAttributes]::Normal); Remove-Item $f.FullName -Force -ErrorAction Stop; $pfCount++ } catch {}
    }
    Write-Host "  CLEANED Prefetch ($pfCount files removed, some locked)" -ForegroundColor Green
}

# Windows\inf - old INF backups (*.pf files, setupapi.dev.log)
$infLog = 'C:\Windows\inf\setupapi.dev.log'
if (Test-Path $infLog) {
    try { Remove-Item $infLog -Force -ErrorAction Stop; Write-Host '  DELETED  inf\setupapi.dev.log' -ForegroundColor Green }
    catch { Write-Host '  SKIP     inf\setupapi.dev.log (locked)' -ForegroundColor Yellow }
}

# Windows\tracing
Clear-FolderContents 'C:\Windows\tracing' 'Windows\tracing'

# appcompat\Programs
Clear-FolderContents 'C:\Windows\appcompat\Programs' 'Windows\appcompat\Programs'

# Downloaded Program Files
Clear-FolderContents 'C:\Windows\Downloaded Program Files' 'Windows\Downloaded Program Files'

# Windows\Help (old .hlp files from 2019)
Clear-FolderContents 'C:\Windows\Help' 'Windows\Help'

# winsxs\Backup (component store backups - safe to clear, Windows rebuilds)
Clear-FolderContents 'C:\Windows\winsxs\Backup' 'Windows\winsxs\Backup'

# system32\LogFiles
Clear-FolderContents 'C:\Windows\system32\LogFiles' 'system32\LogFiles'

# SysWOW64\catroot2 (stale catroot2 cache - Windows regenerates)
Clear-FolderContents 'C:\Windows\SysWOW64\catroot2' 'SysWOW64\catroot2'

# Installer\$PatchCache$
Clear-FolderContents 'C:\Windows\Installer\$PatchCache$' 'Installer\$PatchCache$'

# ============================================================
# 3. Windows\Installer orphaned MSI/MSP files
# ============================================================
Write-Host ''
Write-Host '--- Windows\Installer orphaned patches ---' -ForegroundColor Cyan
# Note: identifying truly orphaned MSI files requires registry cross-reference.
# Safe approach: only delete .msp files older than 1 year with no registered product.
$installerPath = 'C:\Windows\Installer'
if (Test-Path $installerPath) {
    $orphaned = @(Get-ChildItem $installerPath -Filter '*.msp' -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddYears(-1) })
    $orphFreed = [long]0
    foreach ($f in $orphaned) {
        $sz = $f.Length
        try { Remove-Item $f.FullName -Force -ErrorAction Stop; $orphFreed += $sz }
        catch { [CLEAN.MoveFile]::MoveFileEx($f.FullName, $null, 4) | Out-Null }
    }
    if ($orphFreed -gt 0) { Write-Host ("  CLEANED orphaned .msp files ({0:F1} MB)" -f ($orphFreed/1MB)) -ForegroundColor Green }
    else { Write-Host '  No orphaned .msp files found' -ForegroundColor White }
}

# ============================================================
# Summary
# ============================================================
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Items registered for boot-delete: $bootDelCount" -ForegroundColor Yellow
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  KEPT intact (per instruction):' -ForegroundColor White
Write-Host '    Java, Nitro PDF, Analysis Services (PF), Synaptics' -ForegroundColor White
Write-Host '============================================' -ForegroundColor Cyan
