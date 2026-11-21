$pf   = 'C:\Program Files'
$pf86 = 'C:\Program Files (x86)'

Write-Host "=== CROSS-FOLDER DUPLICATES (exist in BOTH PF and PF86) ==="
$allNames = @(
    'BraveSoftware','GensparkSoftware','Yandex','Microsoft Analysis Services',
    'Microsoft Office','Reference Assemblies','Windows NT','WindowsPowerShell',
    'Windows Defender','Windows Photo Viewer','Windows Media Player','Windows Mail',
    'Internet Explorer','Windows Portable Devices','Windows Sidebar',
    'Windows Multimedia Platform','Microsoft.NET','HP','MSBuild','Common Files','Google'
)
foreach ($n in $allNames) {
    $a = Test-Path (Join-Path $pf $n)
    $b = Test-Path (Join-Path $pf86 $n)
    if ($a -and $b) {
        $szA = [long]0; $szB = [long]0
        try { foreach ($f in [System.IO.Directory]::EnumerateFiles("$pf\$n",'*',[System.IO.SearchOption]::AllDirectories)) { try { $szA += ([System.IO.FileInfo]$f).Length } catch {} } } catch {}
        try { foreach ($f in [System.IO.Directory]::EnumerateFiles("$pf86\$n",'*',[System.IO.SearchOption]::AllDirectories)) { try { $szB += ([System.IO.FileInfo]$f).Length } catch {} } } catch {}
        Write-Host ("  {0,-42} PF={1,7} MB   PF86={2,7} MB" -f $n, [math]::Round($szA/1MB,1), [math]::Round($szB/1MB,1))
    }
}

Write-Host "`n=== FOLDERS LAST MODIFIED BEFORE 2022 (potentially stale) ==="
foreach ($root in @($pf,$pf86)) {
    Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date '2022-01-01') } |
    ForEach-Object {
        $sz = [long]0
        try { foreach ($f in [System.IO.Directory]::EnumerateFiles($_.FullName,'*',[System.IO.SearchOption]::AllDirectories)) { try { $sz += ([System.IO.FileInfo]$f).Length } catch {} } } catch {}
        "  {0}   {1,7} MB   {2}" -f $_.LastWriteTime.ToString('yyyy-MM-dd'), [math]::Round($sz/1MB,1), $_.FullName
    }
}

Write-Host "`n=== MICROSOFT (PF86) top-level breakdown — 4 GB ==="
Get-ChildItem "$pf86\Microsoft" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $sz = [long]0
    try { foreach ($f in [System.IO.Directory]::EnumerateFiles($_.FullName,'*',[System.IO.SearchOption]::AllDirectories)) { try { $sz += ([System.IO.FileInfo]$f).Length } catch {} } } catch {}
    "{0,8} MB   {1}" -f [math]::Round($sz/1MB,1), $_.Name
} | Sort-Object

Write-Host "`n=== DOTNET breakdown ==="
Get-ChildItem "$pf\dotnet" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }

Write-Host "`n=== rempl / UNP / ruxim (Windows update residuals) ==="
Get-ChildItem "$pf\rempl" -Force -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, LastWriteTime | Select-Object -First 10
Get-ChildItem "$pf\UNP"   -Force -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime | Select-Object -First 6
Get-ChildItem "$pf\ruxim" -Force -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime

Write-Host "`n=== Java — version ==="
Get-ChildItem "$pf\Java" -Force -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime

Write-Host "`n=== Python314 — confirm version ==="
& "$pf\Python314\python.exe" --version 2>$null

Write-Host "`n=== Nitro top-level ==="
Get-ChildItem "$pf\Nitro" -Force -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime | Select-Object -First 8

Write-Host "`n=== Vistanita (PF86) ==="
Get-ChildItem "$pf86\Vistanita" -Force -Recurse -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime

Write-Host "`n=== InstallShield (PF86) — hidden uninstallers ==="
Get-ChildItem "$pf86\InstallShield Installation Information" -Force -ErrorAction SilentlyContinue | Select-Object -First 5

Write-Host '=== DONE ==='
