# Scan both Program Files folders - top level only first
$roots = @('C:\Program Files', 'C:\Program Files (x86)')

foreach ($root in $roots) {
    Write-Host "`n========== $root =========="
    if (-not (Test-Path $root)) { Write-Host "NOT FOUND"; continue }
    
    $dirs = Get-ChildItem $root -Force -Directory -ErrorAction SilentlyContinue
    $results = @()
    foreach ($d in $dirs) {
        $bytes = [long]0
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($d.FullName,'*',[System.IO.SearchOption]::AllDirectories)) {
                try { $bytes += ([System.IO.FileInfo]$f).Length } catch {}
            }
        } catch {}
        $results += [PSCustomObject]@{
            Name     = $d.Name
            MB       = [math]::Round($bytes/1MB, 1)
            Modified = $d.LastWriteTime.ToString('yyyy-MM-dd')
        }
    }
    $results | Sort-Object MB -Descending | ForEach-Object {
        '{0,9} MB   {1,-12}   {2}' -f $_.MB, $_.Modified, $_.Name
    }
}
Write-Host "`n=== SCAN DONE ==="
