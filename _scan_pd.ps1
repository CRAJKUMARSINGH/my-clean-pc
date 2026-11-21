function Get-FolderMB([string]$path) {
    $b = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($path,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $b += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}
    return [math]::Round($b/1MB,1)
}

Write-Host '========== C:\ProgramData =========='
Get-ChildItem 'C:\ProgramData' -Directory -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        $mb  = Get-FolderMB $_.FullName
        $mod = $_.LastWriteTime.ToString('yyyy-MM-dd')
        '{0,9} MB   {1}   {2}' -f $mb, $mod, $_.Name
    } | Sort-Object
Write-Host '=== PD DONE ==='
