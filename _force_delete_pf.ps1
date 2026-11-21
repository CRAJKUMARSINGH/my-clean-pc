$targets = @(
    'C:\Program Files (x86)\Microsoft Analysis Services',
    'C:\Program Files (x86)\Microsoft Office',
    'C:\Program Files (x86)\HP SimplePass',
    'C:\Program Files (x86)\HP',
    'C:\Program Files\HP',
    'C:\Program Files (x86)\Intel',
    'C:\Program Files (x86)\BraveSoftware',
    'C:\Program Files (x86)\GensparkSoftware',
    'C:\Program Files (x86)\Yandex'
)

if (-not ('PFD3.N' -as [type])) {
    Add-Type -MemberDefinition '[DllImport("Kernel32.dll",CharSet=CharSet.Unicode)] public static extern bool MoveFileEx(string e,string n,int f);' -Name 'N' -Namespace 'PFD3' | Out-Null
}

$totalFreed = [long]0

foreach ($full in $targets) {
    if (-not (Test-Path $full)) { Write-Host "ALREADY GONE: $full" -ForegroundColor Green; continue }

    # Measure size before
    $bytes = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($full,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $bytes += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}

    # Full ownership takeover — /a flag to cover hidden/system
    $null = & takeown.exe /f $full /r /a /d y 2>$null
    $null = & icacls.exe $full /grant 'Administrators:(F)' /t /c /q 2>$null
    $null = & icacls.exe $full /grant 'Everyone:(F)' /t /c /q 2>$null
    $null = & attrib.exe -R -S -H $full /s /d 2>$null

    # Kill any processes locking files in this folder
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($full,[System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    # Delete all files individually first (handles locked files better than rd /s /q)
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($full,'*',[System.IO.SearchOption]::AllDirectories)) {
            try {
                [System.IO.File]::SetAttributes($f,[System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($f)
            } catch {}
        }
    } catch {}

    # Remove directory tree
    $null = & cmd.exe /c "rd /s /q `"$full`" 2>nul"

    if (-not (Test-Path $full)) {
        $totalFreed += $bytes
        Write-Host ("DELETED  {0}  ({1:F1} MB)" -f $full, ($bytes/1MB)) -ForegroundColor Green
        continue
    }

    # Robocopy /MIR wipe then rd
    $empty = Join-Path $env:TEMP ('empty_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $null = & robocopy.exe $empty $full /mir /r:0 /w:0 /mt:8 /nfl /ndl /njh /njs /nc /ns /np 2>&1
    Remove-Item $empty -Force -Recurse -ErrorAction SilentlyContinue
    $null = & cmd.exe /c "rd /s /q `"$full`" 2>nul"

    if (-not (Test-Path $full)) {
        $totalFreed += $bytes
        Write-Host ("DELETED  {0}  ({1:F1} MB via robocopy)" -f $full, ($bytes/1MB)) -ForegroundColor Green
        continue
    }

    # Still stuck — register every child + root for next-boot deletion
    $remaining = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($full,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $remaining += ([System.IO.FileInfo]$f).Length } catch {}
            try { [PFD3.N]::MoveFileEx($f,$null,4) | Out-Null } catch {}
        }
        foreach ($d in [System.IO.Directory]::EnumerateDirectories($full,'*',[System.IO.SearchOption]::AllDirectories) | Sort-Object Length -Descending) {
            try { [PFD3.N]::MoveFileEx($d,$null,4) | Out-Null } catch {}
        }
    } catch {}
    [PFD3.N]::MoveFileEx($full,$null,4) | Out-Null
    $freed = $bytes - $remaining
    $totalFreed += $freed
    Write-Host ("BOOT-DEL {0}  ({1:F1} MB freed now, {2:F1} MB at next boot)" -f $full,($freed/1MB),($remaining/1MB)) -ForegroundColor Yellow
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ("  Total freed: {0:F1} MB" -f ($totalFreed/1MB)) -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
