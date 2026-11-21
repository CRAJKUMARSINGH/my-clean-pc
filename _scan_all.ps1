function Get-FolderSizeMB([string]$path) {
    $b = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($path,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $b += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}
    return [math]::Round($b/1MB,1)
}

function Scan-Root([string]$root, [string]$label) {
    Write-Host "`n========== $label =========="
    if (-not (Test-Path $root)) { Write-Host "NOT FOUND"; return }
    $dirs = Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue
    foreach ($d in ($dirs | Sort-Object Name)) {
        $mb  = Get-FolderSizeMB $d.FullName
        $mod = $d.LastWriteTime.ToString('yyyy-MM-dd')
        '{0,9} MB   {1}   {2}' -f $mb, $mod, $d.Name
    }
}

Scan-Root 'C:\Program Files'       'C:\Program Files'
Scan-Root 'C:\Program Files (x86)' 'C:\Program Files (x86)'
Scan-Root 'C:\ProgramData'         'C:\ProgramData'

# Windows — only top-level non-system dirs that could have redundants
Write-Host "`n========== C:\Windows (selective) =========="
$winJunk = @('Temp','Prefetch','SoftwareDistribution','Logs','inf','debug',
             'Panther','memory.dmp','minidump','LiveKernelReports','ServiceProfiles',
             'assembly','Microsoft.NET','WinSxS','Installer','Downloaded Installations',
             'Downloaded Program Files','Help','Web','Media','Cursors','Globalization',
             'L2Schemas','Performance','PolicyDefinitions','Resources','SchCache',
             'SysWOW64\catroot2','system32\catroot2','system32\LogFiles','SysWOW64\config',
             'CSC','Tasks','tracing','appcompat','AppReadiness','SystemApps',
             'winsxs\Backup','winsxs\ManifestCache','winsxs\Manifests')
foreach ($name in $winJunk) {
    $full = "C:\Windows\$name"
    if (Test-Path $full) {
        $mb  = Get-FolderSizeMB $full
        $mod = (Get-Item $full -Force -ErrorAction SilentlyContinue).LastWriteTime.ToString('yyyy-MM-dd')
        '{0,9} MB   {1}   {2}' -f $mb, $mod, "Windows\$name"
    }
}
Write-Host '=== ALL SCANS DONE ==='
