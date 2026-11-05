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
    # Use single-quoted replacement target; build the replacement string separately
    $replacement = "*Last updated: $now - hook will keep this current automatically.*"
    $content = $content -replace '\*Last updated:.*\*', [regex]::Escape($replacement) -replace '\\(.)', '$1'
    # Simpler: just do a clean string replace via -replace with literal substitution
    $content = [regex]::Replace($content, '\*Last updated:[^*]*\*', "*Last updated: $now - hook will keep this current automatically.*")
    Set-Content -Path $creatPath -Value $content -Encoding UTF8 -NoNewline
}

# ── 2. Mirror the Session Log table row in README.md ────────────────────────
if (Test-Path $readmePath) {
    $readme = Get-Content $readmePath -Raw

    # Build today's row text (no special regex chars in the literal row value)
    $hookName   = 'session-log-12min'
    $rowText    = "| $today | Session log auto-updated at $now via ``$hookName`` hook |"
    $rowMarker  = "| $today |"

    if ($readme -notmatch [regex]::Escape($rowMarker)) {
        # Insert new row after the header separator line of the table
        $tableHeaderPattern = '(\| Time \| Action \|\r?\n\|[-| ]+\|\r?\n)'
        $readme = [regex]::Replace($readme, $tableHeaderPattern, "`$1$rowText`n")
        Set-Content -Path $readmePath -Value $readme -Encoding UTF8 -NoNewline
    } else {
        # Update existing row for today
        $existingRowPattern = [regex]::Escape($rowMarker) + '[^\n]*'
        $readme = [regex]::Replace($readme, $existingRowPattern, $rowText)
        Set-Content -Path $readmePath -Value $readme -Encoding UTF8 -NoNewline
    }
}

Write-Output "Session log updated at $now"
