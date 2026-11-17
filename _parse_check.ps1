$files = @(
    'scripts\Safe-Cleanup-Engine.ps1',
    'scripts\clean-pc-core.ps1',
    'scripts\cleanup_task.ps1',
    'scripts\ai-cache-cleaner.ps1',
    'scripts\Startup-Cleaner.ps1',
    'scripts\Master-PC-Cleanup.ps1',
    '.kiro\hooks\update-session-log.ps1'
)
$root = 'e:\Rajkumar\my-clean-pc'
$allOk = $true
foreach ($rel in $files) {
    $f = [System.IO.Path]::Combine($root, $rel)
    $errs = $null; $tok = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tok,[ref]$errs) | Out-Null
    if ($errs.Count -eq 0) {
        Write-Host "  OK   $rel" -ForegroundColor Green
    } else {
        $allOk = $false
        Write-Host "  ERR  $rel" -ForegroundColor Red
        $errs | ForEach-Object { Write-Host "       L$($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Yellow }
    }
}
if ($allOk) { Write-Host "`nAll scripts parse clean." -ForegroundColor Cyan; exit 0 }
else        { Write-Host "`nParse errors found." -ForegroundColor Red;        exit 1 }
