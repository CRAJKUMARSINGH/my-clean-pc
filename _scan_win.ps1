function Get-FolderMB([string]$path) {
    $b = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($path,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $b += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}
    return [math]::Round($b/1MB,1)
}

# Only scan known-redundant Windows subdirectories — not system dirs
$targets = @(
    'Temp',
    'Logs',
    'Panther',
    'debug',
    'minidump',
    'LiveKernelReports',
    'memory.dmp',
    'SoftwareDistribution\Download',
    'SoftwareDistribution\DataStore\Logs',
    'Prefetch',
    'inf',
    'tracing',
    'appcompat\Programs',
    'CSC',
    'Downloaded Installations',
    'Downloaded Program Files',
    'Help',
    'Web\Wallpaper',
    'winsxs\Backup',
    'system32\LogFiles',
    'system32\catroot2',
    'SysWOW64\catroot2',
    'Installer\$PatchCache$'
)

Write-Host '========== C:\Windows (redundant subfolders) =========='
foreach ($rel in $targets) {
    $full = "C:\Windows\$rel"
    if (-not (Test-Path $full)) { continue }
    $mb  = Get-FolderMB $full
    $mod = (Get-Item $full -Force -ErrorAction SilentlyContinue).LastWriteTime.ToString('yyyy-MM-dd')
    '{0,9} MB   {1}   Windows\{2}' -f $mb, $mod, $rel
}

# Also check WinSxS Backup and Installer PatchCache
$installer = 'C:\Windows\Installer'
if (Test-Path $installer) {
    $patchCache = Join-Path $installer '$PatchCache$'
    if (Test-Path $patchCache) {
        $mb = Get-FolderMB $patchCache
        Write-Host ("   {0,6} MB   Windows\Installer\`$PatchCache`$" -f $mb)
    }
    # Orphaned .msi/.msp files (no corresponding product)
    $msiCount = @(Get-ChildItem $installer -Filter '*.msi' -Force -ErrorAction SilentlyContinue).Count
    $mspCount = @(Get-ChildItem $installer -Filter '*.msp' -Force -ErrorAction SilentlyContinue).Count
    Write-Host "   Installer: $msiCount .msi files, $mspCount .msp files"
}

Write-Host '=== WIN DONE ==='
