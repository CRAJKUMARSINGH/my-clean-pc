$p = 'C:\Users\Rajkumar.DESKTOP-4ISBKM0'
$suspects = @(
    '.grok','.gemini','.fly','.kimi-work','.kimi-webbridge',
    '.ai_completion','.codeium','.workbuddy','.icube-remote-ssh',
    '.ms-ad','.supabase','.qoder','.qmind','.zcode',
    '.antigravity-ide','.antigravity_cockpit',
    'go','.rustup','.cargo'
)
foreach ($name in $suspects) {
    $full = [System.IO.Path]::Combine($p, $name)
    if (-not [System.IO.Directory]::Exists($full)) { continue }
    $latestDate = 'no files'
    try {
        $latest = $null
        foreach ($f in [System.IO.Directory]::EnumerateFiles($full,'*',[System.IO.SearchOption]::AllDirectories)) {
            $fi = [System.IO.FileInfo]::new($f)
            if ($null -eq $latest -or $fi.LastWriteTime -gt $latest.LastWriteTime) { $latest = $fi }
        }
        if ($null -ne $latest) { $latestDate = $latest.LastWriteTime.ToString('yyyy-MM-dd') }
    } catch {}
    Write-Host "$name  ->  $latestDate"
}
Write-Host '=== DONE ==='
