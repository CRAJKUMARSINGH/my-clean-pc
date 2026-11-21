# Scan user profile folder sizes
$p = 'C:\Users\Rajkumar.DESKTOP-4ISBKM0'
$dirs = Get-ChildItem $p -Force -Directory -ErrorAction SilentlyContinue
$results = @()
foreach ($d in $dirs) {
    try {
        $bytes = [long]0
        foreach ($f in [System.IO.Directory]::EnumerateFiles($d.FullName, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $bytes += ([System.IO.FileInfo]$f).Length } catch {}
        }
        $results += [PSCustomObject]@{ Name = $d.Name; KB = [math]::Round($bytes/1KB); Modified = $d.LastWriteTime.ToString('yyyy-MM-dd') }
    } catch {
        $results += [PSCustomObject]@{ Name = $d.Name; KB = -1; Modified = $d.LastWriteTime.ToString('yyyy-MM-dd') }
    }
}
$results | Sort-Object KB -Descending | ForEach-Object {
    $sz = if ($_.KB -eq -1) { '       ?' } else { '{0,9} KB' -f $_.KB }
    "$sz   $($_.Modified)   $($_.Name)"
}
Write-Host '=== SCAN DONE ==='
