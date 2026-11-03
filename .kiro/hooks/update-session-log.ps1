# update-session-log.ps1
# Called by the session-log-12min hook.
# Reads creat.md, updates the timestamp line, then mirrors the Session Log
# section into README.md.

param(
    [string]$RepoRoot = "e:\Rajkumar\my-clean-pc"
)

$ErrorActionPreference = "SilentlyContinue"

$creatPath  = Join-Path $RepoRoot "creat.md"
$readmePath = Join-Path $RepoRoot "README.md"
$now        = Get-Date -Format "yyyy-MM-dd HH:mm"
$today      = Get-Date -Format "yyyy-MM-dd"

# ── 1. Update the "Last updated" timestamp in creat.md ──────────────────────
if (Test-Path $creatPath) {
    $content = Get-Content $creatPath -Raw
    $content = $content -replace '\*Last updated:.*\*', "*Last updated: $now — hook will keep this current automatically.*"
    Set-Content -Path $creatPath -Value $content -Encoding UTF8 -NoNewline
}

# ── 2. Mirror the Session Log table row in README.md ────────────────────────
if (Test-Path $readmePath) {
    $readme = Get-Content $readmePath -Raw

    # Build today's table row (append if not present for this date)
    $rowMarker = "| $today |"
    if ($readme -notmatch [regex]::Escape($rowMarker)) {
        $newRow = "| $today | Session log auto-updated at $now via `session-log-12min` hook |"
        $readme = $readme -replace '(\| Time \| Action \|\r?\n\|---.*\|\r?\n)', "`$1$newRow`n"
        Set-Content -Path $readmePath -Value $readme -Encoding UTF8 -NoNewline
    } else {
        # Update existing row timestamp
        $readme = $readme -replace "(\| $today \|[^\n]*)", "| $today | Session log auto-updated at $now via \`session-log-12min\` hook |"
        Set-Content -Path $readmePath -Value $readme -Encoding UTF8 -NoNewline
    }
}

Write-Output "Session log updated at $now"
