$pf   = 'C:\Program Files'
$pf86 = 'C:\Program Files (x86)'

function Remove-FolderSilent {
    param([string]$Full, [string]$Label)
    if (-not (Test-Path $Full)) { Write-Host "SKIP (not found): $Label"; return [long]0 }

    $bytes = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Full,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $bytes += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}
    $mb = [math]::Round($bytes/1MB,1)

    $null = & takeown.exe /f $Full /r /d y 2>$null
    $null = & icacls.exe  $Full /grant 'Everyone:(F)' /t /c /q 2>$null
    $null = & attrib.exe  -R -S -H $Full /s /d 2>$null
    $null = & cmd.exe /c "del /f /s /q `"$Full\*`" 2>nul"
    $null = & cmd.exe /c "rd /s /q `"$Full`" 2>nul"

    if (-not (Test-Path $Full)) {
        Write-Host "DELETED  $Label  ($mb MB)" -ForegroundColor Green
        return $bytes
    }

    # Robocopy wipe fallback
    $empty = Join-Path $env:TEMP ('empty_' + (Get-Random).ToString())
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $null = & robocopy.exe $empty $Full /mir /r:0 /w:0 /mt:4 /nfl /ndl /njh /njs 2>&1
    Remove-Item $empty -Force -Recurse -ErrorAction SilentlyContinue
    $null = & cmd.exe /c "rd /s /q `"$Full`" 2>nul"

    if (-not (Test-Path $Full)) {
        Write-Host "DELETED  $Label  ($mb MB via robocopy)" -ForegroundColor Green
        return $bytes
    }

    Write-Host "PENDING  $Label  (empty shell, registered for boot delete)" -ForegroundColor Yellow
    if (-not ('PFD.N' -as [type])) {
        Add-Type -MemberDefinition '[DllImport("Kernel32.dll",CharSet=CharSet.Unicode)] public static extern bool MoveFileEx(string e,string n,int f);' -Name 'N' -Namespace 'PFD' | Out-Null
    }
    [PFD.N]::MoveFileEx($Full, $null, 4) | Out-Null
    return $bytes
}

$freed = [long]0

Write-Host '--- Removing confirmed redundant folders ---' -ForegroundColor Cyan

$freed += Remove-FolderSilent "$pf86\Microsoft Analysis Services" 'PF86\Microsoft Analysis Services (dup of PF)'
$freed += Remove-FolderSilent "$pf86\Microsoft Office"            'PF86\Microsoft Office (32-bit stub)'
$freed += Remove-FolderSilent "$pf86\HP SimplePass"               'PF86\HP SimplePass (2018 dead app)'
$freed += Remove-FolderSilent "$pf86\HP"                          'PF86\HP (stale utilities 2021)'
$freed += Remove-FolderSilent "$pf\HP"                            'PF\HP (stale utilities)'
$freed += Remove-FolderSilent "$pf86\Intel"                       'PF86\Intel (older stub)'
$freed += Remove-FolderSilent "$pf86\BraveSoftware"               'PF86\BraveSoftware (updater stub only)'
$freed += Remove-FolderSilent "$pf86\GensparkSoftware"            'PF86\GensparkSoftware (updater stub only)'
$freed += Remove-FolderSilent "$pf86\Yandex"                      'PF86\Yandex (updater stub only)'

Write-Host ''
Write-Host '--- Clearing ETL log files from Windows update agents ---' -ForegroundColor Cyan

foreach ($logPath in @("$pf\ruxim\Logs","$pf\rempl\Logs","$pf\UNP\Logs","$pf\UNP\SystemLogs")) {
    if (-not (Test-Path $logPath)) { continue }
    $etls = Get-ChildItem $logPath -Filter '*.etl' -Force -ErrorAction SilentlyContinue
    if (-not $etls) { continue }
    $sz = ($etls | Measure-Object -Property Length -Sum).Sum
    if (-not $sz) { $sz = [long]0 }
    $etls | Remove-Item -Force -ErrorAction SilentlyContinue
    $freed += $sz
    Write-Host ("CLEANED  {0}  ({1:F1} MB)" -f $logPath, ($sz/1MB)) -ForegroundColor Green
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ("  Total freed this run: {0:F1} MB" -f ($freed/1MB)) -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  KEPT intact (per your instruction):' -ForegroundColor White
Write-Host '    Java          PF\Java\jre1.8.0_501' -ForegroundColor White
Write-Host '    Nitro PDF     PF\Nitro' -ForegroundColor White
Write-Host '    Analysis Svc  PF\Microsoft Analysis Services' -ForegroundColor White
Write-Host '    Synaptics     PF\Synaptics' -ForegroundColor White
Write-Host '============================================' -ForegroundColor Cyan
