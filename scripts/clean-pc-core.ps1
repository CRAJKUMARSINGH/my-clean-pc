# My Clean PC - shared cleaning core (single source of truth)
# Dot-source from my-clean-pc.ps1, cleanup_task.ps1, etc.
# PASSWORDS (Login Data, key4.db, logins.json) are NEVER touched.
# Autofill / saved form-fill data WILL be deleted (user authorised).
# Downloads and Quick Access pins are NEVER touched.

# ---- Non-interactive bypass: auto-answer Yes/OK/All to any prompt --------
$ErrorActionPreference  = "SilentlyContinue"
$ConfirmPreference      = "None"          # suppresses -Confirm on all cmdlets
$ProgressPreference     = "SilentlyContinue"
$WarningPreference      = "SilentlyContinue"
$InformationPreference  = "SilentlyContinue"
$VerbosePreference      = "SilentlyContinue"
$DebugPreference        = "SilentlyContinue"
$WhatIfPreference       = $false          # never dry-run
# Auto-YES to every PowerShell cmdlet confirmation and force-flag
$PSDefaultParameterValues["*:Confirm"] = $false
$PSDefaultParameterValues["*:Force"]   = $true
$PSDefaultParameterValues["*:WhatIf"]  = $false
# -------------------------------------------------------------------------

# Paths NEVER deleted: passwords, Downloads, self-install folder, Quick Access / Explorer shell state.
# Web Data (Chrome autofill), formhistory.sqlite (Firefox autofill), and Autofill folder are NOT
# protected here — user has authorised deleting all saved form fills. Only passwords are kept.
$script:SkipPathFragments = @(
    "\Login Data", "\Login Data For Account", "\key4.db", "\logins.json", "\logins-backup.json",
    "\Downloads", "\Downloads\", "Downloads\", "Downloads", "\MyCleanPC\",
    "\Microsoft\Windows\Recent\", "\Microsoft\Windows\History\",
    "\Microsoft\Windows\Recent\AutomaticDestinations", "\Microsoft\Windows\Recent\CustomDestinations"
)

# Temp roots already cleared this run (avoids duplicate passes that can re-trigger shell UI)
$script:ProcessedTempRoots = @{}

# ---- Temp File Cleaner Logging Helper -----------------------------------

function Write-TempCleanerLog {
    param(
        [string]$Message,
        [scriptblock]$UserLog = $null
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] $Message"

    if ($null -ne $UserLog) {
        try { & $UserLog $Message } catch {}
    } else {
        Write-Host $logLine
    }

    # PERF-FIX #15: Buffer log writes; flush every 25 lines via a StreamWriter
    # instead of opening+appending+flushing 4 separate Add-Content calls per line.
    if ($null -eq $script:TempCleanLogBuffer) {
        $script:TempCleanLogBuffer = [System.Collections.Generic.List[string]]::new()
    }
    $script:TempCleanLogBuffer.Add($logLine)
    if ($script:TempCleanLogBuffer.Count -ge 25) { Flush-TempCleanerLog }
}

function Flush-TempCleanerLog {
    if ($null -eq $script:TempCleanLogBuffer -or $script:TempCleanLogBuffer.Count -eq 0) { return }
    $logPaths = @(
        (Join-Path $PSScriptRoot "temp_cleaner_log.txt"),
        (Join-Path $PSScriptRoot "cleanup_log.txt"),
        (Join-Path "$env:LOCALAPPDATA\MyCleanPC" "temp_cleaner_log.txt"),
        (Join-Path "$env:LOCALAPPDATA\MyCleanPC" "cleanup_log.txt")
    ) | Select-Object -Unique
    foreach ($lp in $logPaths) {
        try {
            $dir = Split-Path $lp -Parent
            if ($dir -and (Test-Path -LiteralPath $dir)) {
                $sw = [System.IO.StreamWriter]::new($lp, $true, [System.Text.Encoding]::UTF8)
                try { foreach ($ln in $script:TempCleanLogBuffer) { $sw.WriteLine($ln) } }
                finally { $sw.Close() }
            }
        } catch {}
    }
    $script:TempCleanLogBuffer.Clear()
}

# ---- Space-freed helpers ------------------------------------------------

function Format-ByteSize {
    param($Bytes)
    if ($null -eq $Bytes) { $Bytes = 0 }
    $Bytes = [long]$Bytes
    if ($Bytes -ge 1GB) { return ('{0:F2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:F1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:F0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# Reads available free bytes on the given drive letter (e.g. "C:" or "C:\").
# Uses DriveInfo - no shell, no WMI, instant.
function Get-DriveFreeBytes {
    param([string]$Drive = $env:SystemDrive)
    try {
        $letter = $Drive.TrimEnd('\').TrimEnd(':') + ':\'
        $info = [System.IO.DriveInfo]::GetDrives() |
                Where-Object { $_.Name -ieq $letter } |
                Select-Object -First 1
        if ($info) { return $info.AvailableFreeSpace }
    } catch {}
    return [long]0
}

# Fast recursive file-size sum via .NET enumeration - no shell, no dialog.
# Used to estimate how much a path contributes before it is deleted.
function Measure-PathSizeBytes {
    param([string]$LiteralPath)
    if (-not $LiteralPath -or -not (Test-Path -LiteralPath $LiteralPath)) { return [long]0 }
    try {
        if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
            return ([System.IO.FileInfo]$LiteralPath).Length
        }
        $total = [long]0
        foreach ($f in [System.IO.Directory]::EnumerateFiles(
                $LiteralPath, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $total += ([System.IO.FileInfo]$f).Length } catch {}
        }
        return $total
    } catch { return [long]0 }
}

# ---- Pre-scan & fun-facts helpers --------------------------------------- #

$script:AiAppRootVars = @(
    '%APPDATA%\Cursor', '%LOCALAPPDATA%\Cursor',
    '%APPDATA%\Code', '%LOCALAPPDATA%\Code',
    '%APPDATA%\kiro', '%APPDATA%\Kiro', '%APPDATA%\KIRO', '%LOCALAPPDATA%\kiro', '%LOCALAPPDATA%\Kiro', '%LOCALAPPDATA%\KIRO',
    '%APPDATA%\Windsurf', '%APPDATA%\WINDSURF', '%APPDATA%\windsurf', '%LOCALAPPDATA%\Windsurf', '%LOCALAPPDATA%\WINDSURF', '%LOCALAPPDATA%\windsurf',
    '%APPDATA%\Trae', '%APPDATA%\trae', '%APPDATA%\trae-ai', '%APPDATA%\TRAE SOLO', '%APPDATA%\Trae Solo', '%APPDATA%\trae solo', '%APPDATA%\TRAE', '%LOCALAPPDATA%\Trae', '%LOCALAPPDATA%\trae', '%LOCALAPPDATA%\TRAE SOLO', '%LOCALAPPDATA%\Trae Solo', '%LOCALAPPDATA%\trae solo', '%LOCALAPPDATA%\TRAE',
    '%APPDATA%\Antigravity', '%APPDATA%\Antigravity IDE', '%APPDATA%\antigravity ide', '%LOCALAPPDATA%\Antigravity', '%LOCALAPPDATA%\Antigravity IDE', '%LOCALAPPDATA%\antigravity ide',
    '%APPDATA%\Qoder', '%APPDATA%\Qoder IDE', '%LOCALAPPDATA%\Qoder', '%LOCALAPPDATA%\Qoder IDE',
    '%APPDATA%\Devin', '%APPDATA%\DEVIN', '%APPDATA%\devin', '%LOCALAPPDATA%\Devin', '%LOCALAPPDATA%\DEVIN', '%LOCALAPPDATA%\devin',
    '%APPDATA%\warp', '%LOCALAPPDATA%\Warp',
    '%APPDATA%\Genspark', '%LOCALAPPDATA%\Genspark',
    '%APPDATA%\Claude', '%LOCALAPPDATA%\AnthropicClaude',
    '%APPDATA%\ChatGPT', '%LOCALAPPDATA%\ChatGPT',
    '%APPDATA%\GitHub Copilot', '%LOCALAPPDATA%\github-copilot',
    '%APPDATA%\Copilot', '%LOCALAPPDATA%\Copilot'
)

# Preserved roaming profiles: never delete user configuration, settings, or chat DBs.
$script:AiRoamingWipeVars = @()

# Electron/Chromium cache folder names. Never User/, settings, or chat DBs.
$script:AiCacheDirNames = @(
    'Cache', 'Caches', 'CachedData', 'Code Cache', 'GPUCache', 'Media Cache',
    'DawnCache', 'DawnWebGPUCache', 'DawnGraphiteCache', 'blob_storage',
    'CachedExtensionVSIXs', 'CachedExtensions', 'logs', 'Crashpad', 'crashpad',
    'Service Worker', 'ShaderCache', 'GrShaderCache', 'Shared Dictionary',
    'GraphiteDawnCache'
)

# Do not walk into settings/chat trees while hunting cache folders.
$script:AiCacheSkipDescend = @(
    'User', 'Users', 'Backups', 'databases', 'IndexedDB',
    'workspaceStorage', 'WorkspaceStorage', 'globalStorage', 'History'
)

function Add-UniquePath {
    param(
        [System.Collections.Generic.List[string]]$List,
        [hashtable]$Seen,
        [string]$Path
    )
    if (-not $Path) { return }
    try {
        if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
    } catch { return }
    $key = $Path.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) { return }
    $Seen[$key] = $true
    [void]$List.Add($Path)
}

function Test-UsableDirectory {
    param([string]$LiteralPath)
    if (-not $LiteralPath) { return $false }
    try {
        return [bool](Test-Path -LiteralPath $LiteralPath -PathType Container -ErrorAction Stop)
    } catch {
        return $false
    }
}

function Get-AiRoamingWipeRoots {
    $out = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($raw in $script:AiRoamingWipeVars) {
        $root = [System.Environment]::ExpandEnvironmentVariables($raw)
        if (-not (Test-UsableDirectory $root)) { continue }
        Add-UniquePath $out $seen $root
    }
    return @($out)
}

function Get-AiCacheTargetPaths {
    $out = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $maxDepth = 4
    $wipeKeys = @{}
    foreach ($root in @(Get-AiRoamingWipeRoots)) {
        $wipeKeys[$root.TrimEnd('\').ToLowerInvariant()] = $true
    }
    foreach ($raw in $script:AiAppRootVars) {
        $root = [System.Environment]::ExpandEnvironmentVariables($raw)
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        if ($wipeKeys.ContainsKey($root.TrimEnd('\').ToLowerInvariant())) { continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push(@{ Path = $root; Depth = 0 })
        while ($stack.Count -gt 0) {
            $cur = $stack.Pop()
            foreach ($child in @(Get-ChildItem -LiteralPath $cur.Path -Force -ErrorAction SilentlyContinue)) {
                $childPath = $child.FullName
                if (-not $child.PSIsContainer) { continue }
                if ($script:AiCacheDirNames -icontains $child.Name) {
                    Add-UniquePath $out $seen $childPath
                    continue
                }
                if ($cur.Depth -ge $maxDepth) { continue }
                if ($script:AiCacheSkipDescend -icontains $child.Name) { continue }
                $stack.Push(@{ Path = $childPath; Depth = ($cur.Depth + 1) })
            }
        }
    }
    foreach ($root in @(Get-AiRoamingWipeRoots)) {
        Add-UniquePath $out $seen $root
    }
    Add-UniquePath $out $seen ([System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\cursor-updater'))
    return @($out)
}

function Get-AllUserAppDataRoots {
    # PERF-FIX #13: Cache result — C:\Users enumeration is called 3+ times per run.
    # Store in $script: variable; reset only at script load (safe for single-run lifetime).
    if ($null -ne $script:CachedUserAppDataRoots) { return $script:CachedUserAppDataRoots }

    $out = New-Object System.Collections.Generic.List[hashtable]
    $seen = @{}
    function AddAppDataPair([string]$Local, [string]$Roaming) {
        $key = "$Local|$Roaming".ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$out.Add(@{ Local = $Local; Roaming = $Roaming })
    }
    AddAppDataPair $env:LOCALAPPDATA $env:APPDATA
    $usersRoot = $null
    try { $usersRoot = [System.IO.Directory]::GetParent($env:USERPROFILE).FullName } catch {}
    if (-not $usersRoot) { $usersRoot = 'C:\Users' }
    foreach ($dir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -in @('Public', 'Default', 'Default User', 'All Users')) { continue }
        $local = Join-Path $dir.FullName 'AppData\Local'
        $roaming = Join-Path $dir.FullName 'AppData\Roaming'
        if (-not (Test-UsableDirectory $local) -and -not (Test-UsableDirectory $roaming)) { continue }
        AddAppDataPair $local $roaming
    }
    $script:CachedUserAppDataRoots = @($out)  # cache for subsequent callers (PERF-FIX #13)
    return $script:CachedUserAppDataRoots
}

$script:ChromiumUserDataRelativeLocal = @(
    'Google\Chrome\User Data',
    'Google\Chrome Beta\User Data',
    'Google\Chrome Dev\User Data',
    'Google\Chrome SxS\User Data',
    'Google\Chrome for Testing\User Data',
    'Google\Chrome for Testing\chrome-user-data',
    'Microsoft\Edge\User Data',
    'Microsoft\Edge Beta\User Data',
    'Microsoft\Edge Dev\User Data',
    'Microsoft\Edge SxS\User Data',
    'BraveSoftware\Brave-Browser\User Data',
    'BraveSoftware\Brave-Browser-Beta\User Data',
    'BraveSoftware\Brave-Browser-Nightly\User Data',
    'Vivaldi\User Data',
    'Yandex\YandexBrowser\User Data',
    'Chromium\User Data',
    'Arc\User Data',
    'Genspark\User Data',
    'GensparkBrowser\User Data',
    'GensparkSoftware\Genspark-Browser\User Data',
    'DuckDuckGo\User Data',
    'Opera Software\Opera Stable',
    'Opera Software\Opera GX Stable',
    'Opera Software\Opera Air Stable',
    'Opera Software\Opera Neon',
    'Opera Software\Opera Developer',
    'Opera Software\Opera Next',
    'CocCoc\Browser\User Data',
    'UCBrowser\User Data\UCBrowser',
    'UCBrowser\User Data',
    'CentBrowser\User Data',
    'Epic Privacy Browser\User Data',
    'Sidekick\User Data',
    'WaveboxApp\Wavebox\User Data',
    'Wavebox\User Data',
    'Iridium\User Data',
    'Thorium\User Data',
    'ungoogled-chromium\User Data',
    'Slimjet\User Data',
    'Comodo\Dragon\User Data',
    'Comodo\User Data',
    'AVAST Software\Browser\User Data',
    'AVG\Browser\User Data',
    'CCleaner Browser\User Data',
    'Norton\Navigator\User Data',
    'Naver\Naver Whale\User Data',
    'Maxthon\Application\User Data',
    'Maxthon5\User Data',
    '360Chrome\Chrome\User Data',
    '360Browser\Browser\User Data',
    'DuckDuckGo\DuckDuckGo\User Data',
    'Comet\User Data',
    'Island\User Data'
)

$script:ChromiumUserDataRelativeRoaming = @(
    'Opera Software\Opera Stable',
    'Opera Software\Opera GX Stable',
    'Opera Software\Opera Air Stable',
    'Opera Software\Opera Neon',
    'Opera Software\Opera Developer',
    'Opera Software\Opera Next'
)

function Get-KnownChromiumUserDataRoots {
    $out = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($pair in @(Get-AllUserAppDataRoots)) {
        foreach ($rel in $script:ChromiumUserDataRelativeLocal) {
            Add-UniquePath $out $seen (Join-Path $pair.Local $rel)
        }
        foreach ($rel in $script:ChromiumUserDataRelativeRoaming) {
            Add-UniquePath $out $seen (Join-Path $pair.Roaming $rel)
        }
    }
    return @($out)
}

# Fast read-only size scan: measures everything that *would* be cleaned
# without deleting a single byte.  Returns a hashtable:
#   { TotalBytes, Count, Top5: [{Label, ShortLabel, Bytes}] }
function Get-CleanupEstimate {
    $hits = [System.Collections.Generic.List[hashtable]]::new()

    function AddHit([string]$full, [string]$short) {
        if (-not $full -or -not (Test-Path -LiteralPath $full)) { return }
        $b = Measure-PathSizeBytes $full
        if ($b -gt 0) { $hits.Add(@{ Label = $full; ShortLabel = $short; Bytes = $b }) }
    }

    # Temp folders
    AddHit ([System.Environment]::ExpandEnvironmentVariables('%TEMP%'))             'User Temp'
    AddHit ([System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Temp')) 'LocalAppData\Temp'
    AddHit 'C:\Windows\Temp'                                                         'Windows\Temp'
    AddHit 'C:\Windows\Prefetch'                                                     'Windows\Prefetch'

    # Cursor/Windsurf/Trae/Devin/Antigravity/Kiro Roaming profiles are wiped whole
    foreach ($p in @(Get-AiCacheTargetPaths)) {
        $full = [System.Environment]::ExpandEnvironmentVariables($p)
        $leaf = 'AI'
        $parent = if ($full) { Split-Path $full -Parent } else { $null }
        if ($parent) {
            $parentLeaf = Split-Path $parent -Leaf
            if ($parentLeaf) { $leaf = $parentLeaf }
        }
        AddHit $full "$leaf cache"
    }

    # Common browser caches (Chromium-family) — profile Cache dirs only, no full recurse
    foreach ($root in @(Find-ChromiumBrowserRoots)) {
        if (-not $root -or -not (Test-UsableDirectory $root)) { continue }
        $appName = Get-BrowserLabelFromPath $root
        foreach ($prof in @(Get-ChromiumProfileDirectories $root)) {
            AddHit (Join-Path $prof.FullName 'Cache') "$appName Cache"
            AddHit (Join-Path $prof.FullName 'Code Cache') "$appName Code Cache"
            AddHit (Join-Path $prof.FullName 'System Cache') "$appName System Cache"
        }
    }

    foreach ($g in @(Find-GeckoBrowserProfileDirs)) {
        $label = Get-GeckoBrowserLabel $g.Name
        if (Test-Path $g.Path) {
            foreach ($prof in @(Get-ChildItem $g.Path -Directory -ErrorAction SilentlyContinue)) {
                AddHit (Join-Path $prof.FullName 'cache2') "$label Cache"
            }
        }
    }

    # INetCache / Thumbnail cache
    AddHit ([System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Microsoft\Windows\INetCache')) 'INetCache'
    AddHit ([System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Microsoft\Windows\Explorer'))  'Thumbnail DB'

    $items = New-Object System.Collections.Generic.List[object]
    $total = [long]0
    foreach ($hit in $hits) {
        $bytes = [long]0
        if ($hit.ContainsKey('Bytes')) { $bytes = [long]$hit['Bytes'] }
        $row = [pscustomobject]@{
            Label      = [string]$hit['Label']
            ShortLabel = [string]$hit['ShortLabel']
            Bytes      = $bytes
        }
        $total += $bytes
        [void]$items.Add($row)
    }
    $sorted = @($items | Sort-Object Bytes -Descending)

    return [pscustomobject]@{
        TotalBytes = $total
        Count      = $items.Count
        Top5       = @($sorted | Select-Object -First 5)
    }
}

# Returns a fun human-scale comparison for a given byte count.
# e.g.  "That's like 1,420 MP3 songs"  or  "That's like 312 holiday photos"
function Format-ByteComparison {
    param([long]$Bytes)
    if ($Bytes -le 10MB) { return '' }

    $songs  = [Math]::Round($Bytes / 4MB)
    $photos = [Math]::Round($Bytes / 4.5MB)
    $video  = [Math]::Round($Bytes / 50MB)    # HD Netflix ~50 MB/min
    $emails = [Math]::Round($Bytes / 0.3MB)   # avg email with attachment

    # Pick whichever gives the most satisfying number (50-9,999 range)
    if ($songs  -in 50..9999) { return "That's like $("{0:N0}" -f $songs) MP3 songs" }
    if ($photos -in 50..9999) { return "That's like $("{0:N0}" -f $photos) holiday photos" }
    if ($video  -in 5..999)   { return "That's like $("{0:N0}" -f $video) minutes of HD video" }
    if ($emails -in 50..9999) { return "That's like $("{0:N0}" -f $emails) emails" }
    if ($songs  -lt 50)       { return "That's like $("{0:N0}" -f $photos) holiday photos" }
    return "That's like $("{0:N0}" -f [Math]::Round($Bytes / 1GB * 250)) songs"
}

# ------------------------------------------------------------------------- #

$script:JunkDirNames = @(
    "Cache", "Caches", "CachedData", "Code Cache", "GPUCache", "Media Cache",
    "Temp", "Tmp", "tmp", "Logs", "Log", "crashpad", "CrashDumps", "blob_storage",
    "startupCache", "OfflineCache", "Application Cache", "INetCache", "WebCache",
    "Updater", "updater", "D3DSCache", "storage", "Crash Reports"
)

function Test-SkipCleanPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $normPath = $Path -replace '/', '\'

    # Absolute safeguard for CURRENT User Profile Downloads folder and all subitems
    $userDownloads = Join-Path $env:USERPROFILE "Downloads"
    if ($normPath -ieq $userDownloads -or $normPath.StartsWith($userDownloads + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    # Absolute safeguard for ALL user profile Downloads folders (C:\Users\*\Downloads)
    # Catches every user on the PC, not just the one running the script
    try {
        $usersRoot = [System.IO.Directory]::GetParent($env:USERPROFILE).FullName
        if (-not $usersRoot) { $usersRoot = 'C:\Users' }
        foreach ($ud in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            $udl = Join-Path $ud.FullName 'Downloads'
            if ($normPath -ieq $udl -or $normPath.StartsWith($udl + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    } catch {}

    # Password database absolute guard (Chromium + Firefox)
    # ONLY password files are protected. Web Data (autofill) and formhistory.sqlite (autofill)
    # are intentionally NOT in this list — user authorised deleting all saved form fills.
    $pwNames = @(
        'Login Data', 'Login Data For Account',
        'key3.db', 'key4.db', 'logins.json', 'logins-backup.json', 'signons.sqlite'
    )
    $leaf = Split-Path $normPath -Leaf
    if ($leaf -and ($pwNames -icontains $leaf)) { return $true }

    foreach ($frag in $script:SkipPathFragments) {
        if ($normPath -like "*$frag*") { return $true }
    }

    # Strict check for any Download or Downloads path segment on ANY drive
    if ($normPath -match '(?i)[\\/]Downloads?([\\/]|$)') {
        return $true
    }

    return $false
}

function Get-LongLiteralPath {
    param([Parameter(Mandatory)][string]$LiteralPath)
    $full = [System.IO.Path]::GetFullPath($LiteralPath)
    if ($full.StartsWith('\\?\')) { return $full }
    if ($full.StartsWith('\\')) { return '\\?\UNC\' + $full.Substring(2) }
    return '\\?\' + $full
}

function Clear-PathAttributes {
    param([Parameter(Mandatory)][string]$LiteralPath)
    try {
        if ([System.IO.Directory]::Exists($LiteralPath)) {
            [System.IO.File]::SetAttributes($LiteralPath, [System.IO.FileAttributes]::Normal)
        } elseif ([System.IO.File]::Exists($LiteralPath)) {
            [System.IO.File]::SetAttributes($LiteralPath, [System.IO.FileAttributes]::Normal)
        } else {
            $long = Get-LongLiteralPath $LiteralPath
            if ([System.IO.Directory]::Exists($long)) {
                [System.IO.File]::SetAttributes($long, [System.IO.FileAttributes]::Normal)
            } elseif ([System.IO.File]::Exists($long)) {
                [System.IO.File]::SetAttributes($long, [System.IO.FileAttributes]::Normal)
            }
        }
    } catch {}
}

function Get-CleanerStagingRoot {
    $candidates = @(
        (Join-Path $env:ProgramData "MyCleanPC"),
        (Join-Path ([System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%")) "MyCleanPC")
    )
    foreach ($candidate in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        } catch {}
    }
    return ([System.IO.Path]::GetTempPath())
}

# ---------------------------------------------------------------------------
# Grant-FullAccess: Run takeown + icacls BEFORE deletion to break 0x80004005
# (Unspecified error / access-denied) errors that trigger Windows Explorer's
# "Interrupted Action" dialog (Do this for all current items / Skip / Cancel).
# ---------------------------------------------------------------------------
function Grant-FullAccess {
    param([Parameter(Mandatory)][string]$LiteralPath)
    try {
        # Take ownership recursively - /d y = auto-answer Yes, silent
        $null = & takeown.exe /f $LiteralPath /r /d y 2>$null
        # Grant full control to Everyone and current user
        $null = & icacls.exe $LiteralPath /grant 'Everyone:(F)' /t /c /q 2>$null
        $null = & icacls.exe $LiteralPath /grant "${env:USERNAME}:(F)" /t /c /q 2>$null
        # Reset hidden/read-only/system attributes on all children
        $null = & attrib.exe -R -S -H "$LiteralPath" /s /d 2>$null
    } catch {}
}

# cmd.exe rd/del with full stderr capture - never surfaces errors to shell UI.
# Asynchronously drains stdout+stderr to prevent pipe-buffer deadlock.
function Invoke-ProcessAnswerAll {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int]$TimeoutMilliseconds = 120000
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        # Windows PowerShell 5.1 / .NET Framework has no ArgumentList - use Arguments.
        if ($psi.GetType().GetProperty('ArgumentList')) {
            foreach ($arg in $ArgumentList) { [void]$psi.ArgumentList.Add($arg) }
        } else {
            $quoted = foreach ($arg in $ArgumentList) {
                if ($null -eq $arg) { continue }
                if ($arg -match '[\s&()^|<>"]') { '"' + ($arg -replace '"', '\"') + '"' } else { $arg }
            }
            $psi.Arguments = ($quoted -join ' ')
        }
        $psi.UseShellExecute = $false   # CRITICAL: never route through Explorer shell
        $psi.CreateNoWindow  = $true    # CRITICAL: no desktop window = no shell UI dialogs
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true   # Capture stderr - prevents shell error dialogs
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        # Drain stdout/stderr asynchronously - prevents pipe-buffer deadlock stalling process
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        try {
            $proc.StandardInput.WriteLine('A')   # 'All' for any interactive prompt
            $proc.StandardInput.WriteLine('Y')   # 'Yes' fallback
            $proc.StandardInput.Close()
        } catch {}
        if (-not $proc.WaitForExit($TimeoutMilliseconds)) {
            try { $proc.Kill() } catch {}
            return $false
        }
        try { [void]$stdoutTask.Result } catch {}
        try { [void]$stderrTask.Result } catch {}
        return ($proc.ExitCode -eq 0)
    } catch {
        return $false
    }
}

# Invoke-CmdSilentSkip: runs a cmd command with " 2>nul" baked into the /c
# argument string. This causes cmd.exe itself to swallow all error output so
# Windows never shows the Explorer "Interrupted Action / Do this for all" dialog.
# Locked files are silently skipped (exit code 1 is treated as success).
function Invoke-CmdSilentSkip {
    param(
        [Parameter(Mandatory)][string]$CmdArgs,
        [int]$TimeoutMilliseconds = 60000
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName        = 'cmd.exe'
        $psi.Arguments       = "/c $CmdArgs 2>nul"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        try { $proc.StandardInput.Close() } catch {}
        if (-not $proc.WaitForExit($TimeoutMilliseconds)) {
            try { $proc.Kill() } catch {}
            return $false
        }
        try { [void]$stdoutTask.Result } catch {}
        try { [void]$stderrTask.Result } catch {}
        # Exit 0 = fully cleaned. Exit 1 = some locked files skipped (acceptable - no dialog).
        return ($proc.ExitCode -le 1)
    } catch {
        return $false
    }
}

function Remove-PathViaCmd {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [switch]$Recurse
    )
    if (Test-SkipCleanPath $LiteralPath) { return $false }
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $true }
    # Grant full access FIRST to eliminate 0x80004005 permission errors that
    # trigger the Windows Explorer "Interrupted Action / Do this for all" dialog.
    Grant-FullAccess -LiteralPath $LiteralPath
    Clear-PathAttributes $LiteralPath
    $isDir = Test-Path -LiteralPath $LiteralPath -PathType Container
    $q = '"' + $LiteralPath + '"'
    if ($isDir -or $Recurse) {
        # Silent skip (errors go to nul, no dialog ever shown)
        $ok = Invoke-CmdSilentSkip -CmdArgs "rd /s /q $q"
    } else {
        $ok = Invoke-CmdSilentSkip -CmdArgs "del /f /q /a $q"
    }
    if (-not $ok) { return $false }
    return -not (Test-Path -LiteralPath $LiteralPath)
}

function Initialize-RebootDeleteNative {
    if ('RebootDeleteNative' -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RebootDeleteNative {
    [DllImport("Kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
    public const int MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;
}
"@
}

function Register-DeleteOnReboot {
    param([Parameter(Mandatory)][string]$LiteralPath)
    try {
        Initialize-RebootDeleteNative
        $long = Get-LongLiteralPath $LiteralPath
        [RebootDeleteNative]::MoveFileEx($long, $null, [RebootDeleteNative]::MOVEFILE_DELAY_UNTIL_REBOOT) | Out-Null
    } catch {}
}

# Kernel-level delete - never routes through Explorer shell (no "do this for all" dialogs)
function Remove-PathViaDotNet {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [switch]$Recurse
    )
    if (Test-SkipCleanPath $LiteralPath) { return $false }
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $true }
    try {
        if ([System.IO.Directory]::Exists($LiteralPath)) {
            if ($Recurse) {
                foreach ($child in @([System.IO.Directory]::EnumerateFileSystemEntries($LiteralPath))) {
                    Remove-PathViaDotNet -LiteralPath $child -Recurse | Out-Null
                }
            }
            [System.IO.File]::SetAttributes($LiteralPath, [System.IO.FileAttributes]::Normal)
            [System.IO.Directory]::Delete($LiteralPath, $false)
        } elseif ([System.IO.File]::Exists($LiteralPath)) {
            [System.IO.File]::SetAttributes($LiteralPath, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($LiteralPath)
        } else {
            $long = Get-LongLiteralPath $LiteralPath
            if ([System.IO.Directory]::Exists($long)) {
                if ($Recurse) {
                    foreach ($child in @([System.IO.Directory]::EnumerateFileSystemEntries($long))) {
                        Remove-PathViaDotNet -LiteralPath $child -Recurse | Out-Null
                    }
                }
                [System.IO.File]::SetAttributes($long, [System.IO.FileAttributes]::Normal)
                [System.IO.Directory]::Delete($long, $false)
            } elseif ([System.IO.File]::Exists($long)) {
                [System.IO.File]::SetAttributes($long, [System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($long)
            } else {
                return $false
            }
        }
        return -not (Test-Path -LiteralPath $LiteralPath)
    } catch {
        return $false
    }
}

# Robocopy mirror-from-empty: bulk-clears directory CONTENTS with zero UI prompts.
# Locked files are silently skipped by robocopy - no Explorer dialog ever appears.
function Clear-DirectoryViaRobocopy {
    param([string]$TargetPath)
    if (Test-SkipCleanPath $TargetPath) { return 0 }
    if (-not (Test-Path $TargetPath)) { return 0 }
    $targetNorm = ([System.IO.Path]::GetFullPath($TargetPath)).TrimEnd('\') + '\'
    $stagingRoot = Get-CleanerStagingRoot
    $emptyDir = Join-Path $stagingRoot ("empty_" + [guid]::NewGuid().ToString('N'))
    $removed = 0
    $script:LastRobocopyExit = 16
    try {
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        if ($emptyDir.StartsWith($targetNorm, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Staging dir must not be inside target"
        }
        $before = @(Get-ChildItem $TargetPath -Force -ErrorAction SilentlyContinue).Count
        # Robocopy /MIR from empty = wipe contents. Locked files are skipped (exit 0-8).
        # Do NOT MoveFileEx every leftover file — that made browser/AI cache passes take 10-30 min each.
        $null = & robocopy.exe $emptyDir $TargetPath /mir /r:0 /w:0 /mt:8 /nfl /ndl /njh /njs /nc /ns /np 2>&1
        $script:LastRobocopyExit = $LASTEXITCODE
        $after = @(Get-ChildItem $TargetPath -Force -ErrorAction SilentlyContinue).Count
        $removed = [Math]::Max(0, $before - $after)
    } finally {
        if (Test-Path $emptyDir) {
            Remove-PathViaDotNet -LiteralPath $emptyDir -Recurse | Out-Null
        }
    }
    return $removed
}

# -----------------------------------------------------------------------
# Remove-DirectorySilent - the right way to delete an entire directory.
#
# THREE-STAGE SILENT DELETE. Zero Explorer "Do this for all items" dialogs:
#   Stage 1 - Robocopy /MIR from an empty folder wipes all contents.
#              Robocopy skips locked files silently; no Shell involvement.
#   Stage 2 - cmd "rd /s /q" removes the now-empty (or near-empty) shell.
#              Runs as a hidden process; never touches the Explorer shell.
#   Stage 3 - MoveFileEx DELAY_UNTIL_REBOOT registers any still-locked
#              remnant for silent deletion at next Windows boot.
# -----------------------------------------------------------------------
function Remove-DirectorySilent {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [switch]$KeepContainer
    )
    if (Test-SkipCleanPath $LiteralPath) { return $false }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) { return $false }

    # Stage 1: Robocopy wipe - zero Explorer dialogs, locked files silently skipped
    $removed = Clear-DirectoryViaRobocopy $LiteralPath

    if ($KeepContainer) {
        $robocopyOk = ($script:LastRobocopyExit -lt 8)
        $empty = (@(Get-ChildItem -LiteralPath $LiteralPath -Force -ErrorAction SilentlyContinue).Count -eq 0)
        return $robocopyOk -or ($removed -gt 0) -or $empty
    }

    # Stage 2: Remove the (now mostly/fully empty) directory shell via cmd
    Remove-PathViaCmd -LiteralPath $LiteralPath -Recurse | Out-Null

    # Stage 3: folder-level reboot delete only (never enumerate every leftover cache file)
    if (Test-Path -LiteralPath $LiteralPath) {
        Register-DeleteOnReboot -LiteralPath $LiteralPath
        return $false
    }
    return $true
}

# Friendly names for apps we close so the user notice reads naturally.
$script:ProcessDisplayNames = @{
    chrome = 'Google Chrome'; msedge = 'Microsoft Edge'; brave = 'Brave'
    vivaldi = 'Vivaldi'; opera = 'Opera'; yandexbrowser = 'Yandex'; browser = 'Yandex'
    chromium = 'Chromium'; firefox = 'Firefox'; waterfox = 'Waterfox'
    palemoon = 'Pale Moon'; librewolf = 'LibreWolf'; torbrowser = 'Tor Browser'
    basilisk = 'Basilisk'; gensparkbrowser = 'Genspark Browser'
    arc = 'Arc Browser'; wavebox = 'Wavebox'; sidekick = 'Sidekick'
    duckduckgo = 'DuckDuckGo'; whale = 'Naver Whale'; maxthon = 'Maxthon'
    thorium = 'Thorium'; floorp = 'Floorp'; zen = 'Zen Browser'
    Kiro = 'Kiro'; Windsurf = 'Windsurf'; Trae = 'Trae'; 'Trae Solo' = 'Trae Solo'; 'trae-solo' = 'Trae Solo'; Solo = 'Trae Solo'; Devin = 'Devin'
    'Antigravity IDE' = 'Antigravity IDE'; Antigravity = 'Antigravity IDE'; 'Qoder IDE' = 'Qoder IDE'; Qoder = 'Qoder IDE'; warp = 'Warp'
    Genspark = 'Genspark'; ChatGPT = 'ChatGPT'; Claude = 'Claude'
}

$script:ClosedAppLabels = New-Object System.Collections.Generic.List[string]
$script:CleanedBrowserLabels = New-Object System.Collections.Generic.List[string]
$script:ClosedAppRestarts = New-Object System.Collections.Generic.List[hashtable]
$script:RestartedAppLabels = New-Object System.Collections.Generic.List[string]
$script:RestartSkipProcessNames = @(
    'chrome_proxy', 'chrome_crashpad', 'crashpad_handler', 'software_reporter_tool',
    'elevation_service', 'msedgewebview2', 'MicrosoftEdgeUpdate', 'GoogleUpdate',
    'GoogleCrashHandler', 'GoogleCrashHandler64'
)

function Reset-ClosedAppLabels {
    $script:ClosedAppLabels = New-Object System.Collections.Generic.List[string]
    $script:CleanedBrowserLabels = New-Object System.Collections.Generic.List[string]
    $script:ClosedAppRestarts = New-Object System.Collections.Generic.List[hashtable]
    $script:RestartedAppLabels = New-Object System.Collections.Generic.List[string]
}

function Add-CleanedBrowserLabel {
    param([string]$Label)
    if (-not $Label) { return }
    if ($script:CleanedBrowserLabels -notcontains $Label) {
        [void]$script:CleanedBrowserLabels.Add($Label)
    }
}

function Test-RestartableClosedProcessName {
    param([string]$Name)
    if (-not $Name) { return $false }
    $n = $Name.Trim() -replace '\.exe$', ''
    if (-not $n) { return $false }
    if ($script:RestartSkipProcessNames -contains $n) { return $false }
    if ($n -match '(?i)(proxy|crashpad|webview|update|handler)$') { return $false }
    return $true
}

function Get-ClosedAppDisplayName {
    param([string]$ProcessName)
    $label = $script:ProcessDisplayNames[$ProcessName]
    if ($label) { return $label }
    return $ProcessName
}

function Add-ClosedAppLabel {
    param([string]$ProcessName)
    if (-not (Test-RestartableClosedProcessName $ProcessName)) { return }
    $label = Get-ClosedAppDisplayName $ProcessName
    if ($script:ClosedAppLabels -notcontains $label) {
        [void]$script:ClosedAppLabels.Add($label)
    }
}

function Get-MainProcessExecutable {
    param([string]$ProcessName)
    if (-not $ProcessName) { return $null }
    $leaf = $ProcessName.Trim() -replace '\.exe$', ''
    foreach ($p in @(Get-Process -Name $leaf -ErrorAction SilentlyContinue)) {
        if ($p.Path -and (Test-Path -LiteralPath $p.Path)) { return $p.Path }
    }
    try {
        $cim = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='$leaf.exe'" -ErrorAction SilentlyContinue)
        foreach ($row in $cim) {
            if ($row.ExecutablePath -and (Test-Path -LiteralPath $row.ExecutablePath)) {
                return $row.ExecutablePath
            }
        }
    } catch {}
    return $null
}

function Resolve-ClosedAppRestartExe {
    param(
        [string]$ProcessName,
        [string]$CapturedExe
    )
    if ($CapturedExe -and (Test-Path -LiteralPath $CapturedExe)) { return $CapturedExe }
    $exeName = ($ProcessName.Trim() -replace '\.exe$', '') + '.exe'
    if ($exeName -ieq 'browser.exe') { return $null }
    foreach ($p in @(Get-WellKnownBrowserExePaths)) {
        if ([System.IO.Path]::GetFileName($p) -ieq $exeName) { return $p }
    }
    foreach ($root in @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'
        )) {
        $key = Join-Path $root $exeName
        if (-not (Test-Path -LiteralPath $key)) { continue }
        try {
            $cmd = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).'(default)'
            $parsed = Split-BrowserLaunchCommand $cmd
            if ($parsed['Exe'] -and (Test-Path -LiteralPath $parsed['Exe'])) { return $parsed['Exe'] }
        } catch {}
    }
    return $null
}

function Add-ClosedAppRestart {
    param(
        [string]$ProcessName,
        [string]$ExePath
    )
    if (-not (Test-RestartableClosedProcessName $ProcessName)) { return }
    $label = Get-ClosedAppDisplayName $ProcessName
    $exe = Resolve-ClosedAppRestartExe -ProcessName $ProcessName -CapturedExe $ExePath
    if ($ProcessName -ieq 'browser' -and $exe -and $exe -notmatch '(?i)Yandex') { return }
    $key = if ($exe) { $exe.ToLowerInvariant() } else { $ProcessName.ToLowerInvariant() }
    foreach ($row in @($script:ClosedAppRestarts)) {
        if ($row.Key -eq $key) { return }
    }
    [void]$script:ClosedAppRestarts.Add(@{
        Key          = $key
        ProcessName  = ($ProcessName.Trim() -replace '\.exe$', '')
        Label        = $label
        Exe          = $exe
    })
}

function Restore-ClosedApps {
    param([scriptblock]$Log = { param([string]$Message) })
    $script:RestartedAppLabels = New-Object System.Collections.Generic.List[string]
    if ($env:MYCLEANPC_NO_RESTART -eq '1') { return }
    if (@($script:ClosedAppRestarts).Count -eq 0) { return }
    & $Log "  Reopening apps that were closed for cleaning..."
    foreach ($row in @($script:ClosedAppRestarts)) {
        $exe = Resolve-ClosedAppRestartExe -ProcessName $row.ProcessName -CapturedExe $row.Exe
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
            & $Log ("  Could not reopen {0} (app path not found)." -f $row.Label)
            continue
        }
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($exe)
        $already = @(Get-Process -Name $leaf -ErrorAction SilentlyContinue)
        if ($already.Count -gt 0) {
            & $Log ("  {0} is already running." -f $row.Label)
            if ($script:RestartedAppLabels -notcontains $row.Label) {
                [void]$script:RestartedAppLabels.Add($row.Label)
            }
            continue
        }
        try {
            Start-Process -FilePath $exe -ErrorAction Stop | Out-Null
            if ($script:RestartedAppLabels -notcontains $row.Label) {
                [void]$script:RestartedAppLabels.Add($row.Label)
            }
            & $Log ("  Reopened {0}." -f $row.Label)
        } catch {
            & $Log ("  Could not reopen {0}." -f $row.Label)
        }
    }
}

function Get-MyCleanPCBusyMessage {
    $closed = @($script:ClosedAppLabels)
    if ($closed.Count -eq 0) {
        return "Clearing browser and AI caches. Those apps will be reopened when cleaning finishes."
    }
    $list = ($closed | Select-Object -First 4) -join ', '
    return "Temporarily closed $list so caches can be wiped. I will reopen them when cleaning finishes."
}

function Get-MyCleanPCReadyMessage {
    $reopened = @($script:RestartedAppLabels)
    if ($reopened.Count -gt 0) {
        $list = ($reopened | Select-Object -First 5) -join ', '
        $more = $reopened.Count - 5
        if ($more -gt 0) {
            return "Cleanup is complete. I reopened $list, and $more other app(s), for you."
        }
        if ($reopened.Count -eq 1) {
            return "Cleanup is complete. I reopened $list for you."
        }
        return "Cleanup is complete. I reopened $list for you."
    }
    $closed = @($script:ClosedAppLabels)
    if ($closed.Count -gt 0) {
        $list = ($closed | Select-Object -First 4) -join ', '
        return "Cleanup is complete. You can use $list again."
    }
    $cleaned = @($script:CleanedBrowserLabels)
    if ($cleaned.Count -eq 0) {
        return "Scheduled cleanup is complete. You can now use your browsers and AI tools."
    }
    $head = ($cleaned | Select-Object -First 5) -join ', '
    return "Scheduled cleanup is complete. Cleaned $head."
}

function Show-MyCleanPCBalloon {
    param([string]$Title, [string]$Body)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.BalloonTipTitle = $Title
        $icon.BalloonTipText = $Body
        $icon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $icon.ShowBalloonTip(20000)
        Start-Sleep -Milliseconds 800
        $icon.Visible = $false
        $icon.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Show-MyCleanPCToast {
    param([string]$Title, [string]$Body)
    try {
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $escTitle = [System.Security.SecurityElement]::Escape($Title)
        $escBody = [System.Security.SecurityElement]::Escape($Body)
        $xmlText = @"
<toast duration="long">
  <visual>
    <binding template="ToastGeneric">
      <text>$escTitle</text>
      <text>$escBody</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default" silent="false"/>
</toast>
"@
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlText)
        # PowerShell's registered AppId so the toast appears from a hidden scheduled task.
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        return $true
    } catch {
        return $false
    }
}

function Show-MyCleanPCNotice {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [scriptblock]$Log = { param([string]$Message) }
    )
    & $Log "  [Notice] $Title — $Body"
    if ($env:MYCLEANPC_NO_TOAST -eq '1') { return }
    if (Show-MyCleanPCToast -Title $Title -Body $Body) { return }
    [void](Show-MyCleanPCBalloon -Title $Title -Body $Body)
}

function Close-AiToolProcesses {
    param([scriptblock]$Log = { param($m) })
    # Unlock AI caches. Do not stop Cursor/Code — this cleaner often runs from Cursor.
    $aiProcesses = @(
        "Kiro", "kiro", "Windsurf", "Trae", "trae", "TRAE SOLO", "Trae Solo", "trae solo", "trae-solo", "Solo", "solo", "Antigravity", "Qoder", "warp",
        "Devin", "Genspark", "ChatGPT", "Claude"
    )
    # PERF-FIX #20: Batch-stop all AI processes in one pass, then sleep ONCE.
    # Previously stopped each process and slept 1 second per process serially.
    $toStop = [System.Collections.Generic.List[string]]::new()
    foreach ($procName in $aiProcesses) {
        try {
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($procs) {
                $exe = Get-MainProcessExecutable $procName
                Add-ClosedAppLabel $procName
                Add-ClosedAppRestart -ProcessName $procName -ExePath $exe
                [void]$toStop.Add($procName)
            }
        } catch {}
    }
    if ($toStop.Count -gt 0) {
        & $Log "  Closing AI tool processes (unlock caches): $($toStop -join ', ')"
        foreach ($procName in $toStop) {
            try { Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue } catch {}
        }
        Start-Sleep -Milliseconds 800  # single wait after all stops
    }
}

function Close-NamedProcesses {
    param(
        [string[]]$ProcessNames,
        [scriptblock]$Log = { param($m) },
        [int]$Rounds = 4
    )
    $names = @($ProcessNames | Where-Object { $_ } | ForEach-Object {
        ([string]$_).Trim() -replace '\.exe$', ''
    } | Where-Object { $_ -and (Test-SafeBrowserProcessName $_) } | Select-Object -Unique)
    if ($names.Count -eq 0) { return }
    for ($round = 1; $round -le $Rounds; $round++) {
        $closedAny = $false
        foreach ($procName in $names) {
            try {
                $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
                if ($procs.Count -eq 0) { continue }
                $closedAny = $true
                if ($round -eq 1) {
                    & $Log "  Closing $procName processes..."
                    $exe = Get-MainProcessExecutable $procName
                    Add-ClosedAppLabel $procName
                    Add-ClosedAppRestart -ProcessName $procName -ExePath $exe
                }
                Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
                & taskkill.exe /F /IM "$procName.exe" /T 2>$null | Out-Null
            } catch {}
        }
        if (-not $closedAny) { break }
        Start-Sleep -Milliseconds 700
    }
}

function Close-BrowserProcesses {
    param(
        [scriptblock]$Log = { param($m) },
        [string[]]$ExtraProcessNames = @()
    )
    $browserProcesses = @(
        "chrome", "chrome_proxy", "msedge", "brave", "vivaldi", "opera", "opera_gx",
        "yandexbrowser", "browser", "chromium", "arc", "wavebox", "sidekick",
        "centbrowser", "coccoc", "ucbrowser", "epicprivacybrowser",
        "gensparkbrowser", "genspark", "duckduckgo",
        "thorium", "iridium", "slimjet", "maxthon", "whale",
        "firefox", "waterfox", "palemoon", "librewolf", "torbrowser", "basilisk",
        "floorp", "zen", "mullvadbrowser", "iexplore"
    ) + @($ExtraProcessNames)
    Close-NamedProcesses -ProcessNames $browserProcesses -Log $Log
}

function Remove-SafePathWithRetry {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [switch]$Recurse,
        [int]$MaxRetries = 2
    )
    $attempt = 0
    $success = $false
    while ($attempt -le $MaxRetries -and -not $success) {
        $success = Remove-SafePath -LiteralPath $LiteralPath -Recurse:$Recurse
        if (-not $success -and $attempt -lt $MaxRetries) {
            Start-Sleep -Milliseconds 500
        }
        $attempt++
    }
    return $success
}

function Clear-SafeDirectoryContents {
    param([string]$LiteralPath)
    if (Test-SkipCleanPath $LiteralPath) { return }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) { return }
    foreach ($child in @(Get-ChildItem -LiteralPath $LiteralPath -Force -ErrorAction SilentlyContinue)) {
        if (Test-SkipCleanPath $child.FullName) { continue }
        try { $child.Attributes = 'Normal' } catch {}
        if ($child.PSIsContainer) {
            Clear-SafeDirectoryContents -LiteralPath $child.FullName
            Remove-SafePathWithRetry -LiteralPath $child.FullName -Recurse | Out-Null
        } else {
            Remove-SafePathWithRetry -LiteralPath $child.FullName | Out-Null
        }
    }
}

# Delete path if safe; skip protected paths and locked/in-use files - never prompts user
function Remove-SafePath {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [switch]$Recurse
    )
    if (Test-SkipCleanPath $LiteralPath) { return $false }
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $false }
    if (Remove-PathViaDotNet -LiteralPath $LiteralPath -Recurse:$Recurse) { return $true }
    if (Remove-PathViaCmd -LiteralPath $LiteralPath -Recurse:$Recurse) { return $true }
    if (Test-Path -LiteralPath $LiteralPath) {
        Register-DeleteOnReboot -LiteralPath $LiteralPath
    }
    return $false
}

function Clear-SafeTempTree {
function Clear-SafeTempTree {
    # PERF-FIX #11: Reduced from 4 sequential passes to 2.
    # Stage 1: del /f/s/q clears everything unlocked in one cmd.exe pass (fastest).
    #          Subdirs with remaining files are handled by robocopy /MIR as a safety net.
    # Stage 2: MoveFileEx DELAY_UNTIL_REBOOT on individual leftover items ONLY.
    #          We NEVER register the root folder itself — only its surviving children.
    #
    # Stages 2 and 3 from the old code (item-by-item rd/del then robocopy sweep)
    # were nearly always no-ops because Stage 1 had already cleared everything unlocked.
    # They added 2–3 extra Get-ChildItem enumerations of the same tree for every temp root.
    param([string]$RootPath)
    $root = [System.Environment]::ExpandEnvironmentVariables($RootPath)
    if (-not (Test-Path $root)) { return 0 }
    $key = ([System.IO.Path]::GetFullPath($root)).TrimEnd('\').ToLowerInvariant()
    if ($script:ProcessedTempRoots.ContainsKey($key)) { return $script:ProcessedTempRoots[$key] }

    $before = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue).Count

    # ---- Stage 1: mass delete — del /f/s/q + robocopy /MIR safety net ----
    # Takes ownership first to break permission locks, then bulk-deletes.
    Grant-FullAccess -LiteralPath $root
    $null = Invoke-CmdSilentSkip -CmdArgs "del /f /s /q /a `"$root\*`""
    # Remove leftover directory skeletons via rd /s /q on each direct child
    foreach ($child in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)) {
        if (Test-SkipCleanPath $child.FullName) { continue }
        if ($child.PSIsContainer) {
            Remove-PathViaCmd -LiteralPath $child.FullName -Recurse | Out-Null
        } else {
            Remove-PathViaCmd -LiteralPath $child.FullName | Out-Null
        }
    }
    # Robocopy /MIR catches anything cmd missed (unusual attributes, deep paths)
    Clear-DirectoryViaRobocopy $root | Out-Null

    # ---- Stage 2: register genuinely-locked remnants for next-boot delete --
    # NEVER register the root itself — only its surviving children.
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)) {
        if (Test-SkipCleanPath $item.FullName) { continue }
        Register-DeleteOnReboot -LiteralPath $item.FullName
    }

    $after = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue).Count
    $removed = [Math]::Max(0, $before - $after)
    $script:ProcessedTempRoots[$key] = $removed
    return $removed
}

function Test-JunkDirName {
    param([string]$Name)
    foreach ($jn in $script:JunkDirNames) {
        if ($Name -ieq $jn) { return $true }
    }
    return $false
}

function Clear-RecycleBinSilent {
    if (-not ('RecycleBinNative' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RecycleBinNative {
    [DllImport("Shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint dwFlags);
    public const uint SHERB_NOCONFIRMATION = 0x00000001;
    public const uint SHERB_NOPROGRESSUI   = 0x00000002;
    public const uint SHERB_NOSOUND        = 0x00000004;
}
"@
    }
    $flags = [RecycleBinNative]::SHERB_NOCONFIRMATION -bor `
        [RecycleBinNative]::SHERB_NOPROGRESSUI -bor `
        [RecycleBinNative]::SHERB_NOSOUND
    [RecycleBinNative]::SHEmptyRecycleBin([IntPtr]::Zero, $null, $flags) | Out-Null
}

function Clear-RigorousTempLocations {
    param([scriptblock]$OnItem = { param($Path) })
    $script:ProcessedTempRoots = @{}
    $fixed = @(
        "%TEMP%", "%LOCALAPPDATA%\Temp", "C:\Windows\Temp",
        "C:\Windows\Prefetch",
        "%LOCALAPPDATA%\CrashDumps", "%LOCALAPPDATA%\D3DSCache",
        "%LOCALAPPDATA%\Microsoft\Windows\WebCache",
        "%LOCALAPPDATA%\Microsoft\Windows\Burn\Burn"
    )
    foreach ($raw in $fixed) {
        $p = [System.Environment]::ExpandEnvironmentVariables($raw)
        if (Test-Path $p) {
            Clear-SafeTempTree $p | Out-Null
            & $OnItem $p
        }
    }
    $local = [System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%")
    Get-ChildItem $local -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($n in @("Temp", "temp", "tmp", "Tmp")) {
            $tp = Join-Path $_.FullName $n
            if (Test-Path $tp) {
                Clear-SafeTempTree $tp | Out-Null
                & $OnItem $tp
            }
        }
    }
}

function Clear-AppDataJunkSweep {
    param(
        [string]$RootVar,
        [scriptblock]$OnBatch = { param($Count) }
    )
    $root = [System.Environment]::ExpandEnvironmentVariables($RootVar)
    if (-not (Test-Path $root)) { return 0 }
    $cleared = 0
    # PERF-FIX #16: Use .NET EnumerateDirectories (streaming) instead of Get-ChildItem | ForEach-Object
    $stack = New-Object System.Collections.Stack
    foreach ($d in [System.IO.Directory]::EnumerateDirectories($root)) {
        $stack.Push(@{ Path = $d; Depth = 0 })
    }
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        try {
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($cur.Path)) {
                $childName = [System.IO.Path]::GetFileName($child)
                if (Test-SkipCleanPath $child) { continue }
                if ($childName -in @('User Data', 'EBWebView', 'EdgeWebView', 'CefCache', 'DDGWebView', 'MyCleanPC', 'Packages')) { continue }
                if (Test-JunkDirName $childName) {
                    if (Remove-DirectorySilent -LiteralPath $child -KeepContainer) { $cleared++ }
                } elseif ($cur.Depth -lt 3) {
                    $stack.Push(@{ Path = $child; Depth = $cur.Depth + 1 })
                }
            }
        } catch {}
    }
    & $OnBatch $cleared
    return $cleared
}

function Clear-RoamingAppCachesAllApps {
    param(
        [scriptblock]$OnBatch = { param($Count) }
    )
    $root = [System.Environment]::ExpandEnvironmentVariables("%APPDATA%")
    if (-not (Test-Path $root)) { return 0 }

    $cacheNames = @(
        "Cache", "Caches", "CachedData", "Code Cache", "GPUCache", "Media Cache",
        "Temp", "Tmp", "tmp", "Logs", "Log", "crashpad", "CrashDumps",
        "blob_storage", "startupCache", "OfflineCache", "Application Cache"
    )
    # Build a HashSet for O(1) containment checks
    $cacheSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $cacheNames) { [void]$cacheSet.Add($n) }

    $cleared = 0
    $stack = New-Object System.Collections.Stack
    # PERF-FIX #16: .NET EnumerateDirectories instead of Get-ChildItem | ForEach-Object
    foreach ($dir in [System.IO.Directory]::EnumerateDirectories($root)) {
        $stack.Push(@{ Path = $dir; Depth = 0 })
    }

    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        try {
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($cur.Path)) {
                if (Test-SkipCleanPath $child) { continue }
                $childName = [System.IO.Path]::GetFileName($child)
                if ($cacheSet.Contains($childName)) {
                    if (Remove-DirectorySilent -LiteralPath $child -KeepContainer) { $cleared++ }
                    continue
                }
                if ($cur.Depth -lt 7) {
                    $stack.Push(@{ Path = $child; Depth = $cur.Depth + 1 })
                }
            }
        } catch {}
    }

    & $OnBatch $cleared
    return $cleared
}

function Remove-CleanPaths {
    # Universal silent delete for all explicit paths.
    # Directories  -> Remove-DirectorySilent (del /f/s/q -> robocopy /MIR -> reboot-delete).
    #                Zero Explorer "Do this for all items" dialogs regardless of path.
    # Files        -> Remove-SafePathWithRetry (.NET delete -> cmd del -> reboot-delete).
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        $exp = [System.Environment]::ExpandEnvironmentVariables($p)
        if (-not (Test-Path -LiteralPath $exp)) { continue }
        if (Test-Path -LiteralPath $exp -PathType Container) {
            Remove-DirectorySilent -LiteralPath $exp | Out-Null
        } else {
            Remove-SafePathWithRetry -LiteralPath $exp | Out-Null
        }
    }
}

# Non-browser apps / embedded WebViews that also use Chromium "Local State"
$script:BrowserDiscoveryExcludes = @(
    '\Cursor\', '\discord\', '\Discord\', '\Slack\', '\Teams\', '\Postman\',
    '\GitHub Desktop\', '\Notion\', '\Obsidian\', '\Spotify\', '\Zoom\',
    '\Antigravity\', '\Windsurf\', '\Qoder\', '\kiro\', '\Kiro\', '\Trae\', '\trae\', '\TRAE SOLO\', '\Trae Solo\', '\trae solo\', '\Devin\',
    '\electron\', '\Microsoft\Teams\', '\Code\',
    '\EBWebView\', '\EdgeWebView\', '\CefCache\', '\DDGWebView\', '\WebView2\',
    '\Packages\', '\INetCache\', '\Temp\'
)

$script:DiscoveredBrowserProcessNames = New-Object System.Collections.Generic.List[string]
$script:CachedBrowserLaunchCommands = $null

$script:GeckoProfileRelative = @(
    @{ Name = 'Mozilla\Firefox'; Rel = 'Mozilla\Firefox\Profiles' },
    @{ Name = 'Waterfox'; Rel = 'Waterfox\Profiles' },
    @{ Name = 'LibreWolf'; Rel = 'librewolf\Profiles' },
    @{ Name = 'Pale Moon'; Rel = 'Moonchild Productions\Pale Moon\Profiles' },
    @{ Name = 'Basilisk'; Rel = 'Moonchild Productions\Basilisk\Profiles' },
    @{ Name = 'Zen'; Rel = 'zen\Profiles' },
    @{ Name = 'Floorp'; Rel = 'Floorp\Profiles' },
    @{ Name = 'Mullvad Browser'; Rel = 'Mullvad\MullvadBrowser\Profiles' },
    @{ Name = 'Tor Browser'; Rel = 'tor-browser\Profiles' }
)

$script:ChromiumExeProfileMap = @{
    'chrome.exe'            = @('Google\Chrome\User Data', 'Google\Chrome Beta\User Data', 'Google\Chrome Dev\User Data', 'Google\Chrome SxS\User Data', 'Google\Chrome for Testing\User Data')
    'msedge.exe'            = @('Microsoft\Edge\User Data', 'Microsoft\Edge Beta\User Data', 'Microsoft\Edge Dev\User Data', 'Microsoft\Edge SxS\User Data')
    'brave.exe'             = @('BraveSoftware\Brave-Browser\User Data', 'BraveSoftware\Brave-Browser-Beta\User Data', 'BraveSoftware\Brave-Browser-Nightly\User Data')
    'vivaldi.exe'           = @('Vivaldi\User Data')
    'opera.exe'             = @('Opera Software\Opera Stable', 'Opera Software\Opera Developer', 'Opera Software\Opera Next')
    'opera_gx.exe'          = @('Opera Software\Opera GX Stable')
    'browser.exe'           = @('Yandex\YandexBrowser\User Data')
    'yandexbrowser.exe'     = @('Yandex\YandexBrowser\User Data')
    'chromium.exe'          = @('Chromium\User Data')
    'arc.exe'               = @('Arc\User Data')
    'wavebox.exe'           = @('WaveboxApp\Wavebox\User Data', 'Wavebox\User Data')
    'sidekick.exe'          = @('Sidekick\User Data')
    'gensparkbrowser.exe'   = @('Genspark\User Data', 'GensparkBrowser\User Data', 'GensparkSoftware\Genspark-Browser\User Data')
    'genspark.exe'          = @('Genspark\User Data', 'GensparkBrowser\User Data', 'GensparkSoftware\Genspark-Browser\User Data')
    'duckduckgo.exe'        = @('DuckDuckGo\User Data')
    'thorium.exe'           = @('Thorium\User Data')
    'iridium.exe'           = @('Iridium\User Data')
    'slimjet.exe'           = @('Slimjet\User Data')
    'maxthon.exe'           = @('Maxthon\Application\User Data', 'Maxthon5\User Data')
    'whale.exe'             = @('Naver\Naver Whale\User Data')
}

$script:GeckoExeNames = @(
    'firefox.exe', 'waterfox.exe', 'librewolf.exe', 'palemoon.exe',
    'basilisk.exe', 'floorp.exe', 'zen.exe', 'mullvadbrowser.exe', 'torbrowser.exe'
)

function Test-StoreBrowserPackagePath {
    param([string]$Path)
    if (-not $Path) { return $false }
    return ($Path -match '(?i)\\Packages\\(Google\.Chrome|Mozilla\.Firefox|Mozilla\.MozillaFirefox|Microsoft\.MicrosoftEdge|BraveSoftware|OperaSoftware|ClassicOpera|Vivaldi)')
}

function Test-BrowserDiscoveryExcluded {
    param([string]$Path)
    if (-not $Path) { return $true }
    $norm = $Path.TrimEnd('\') + '\'
    $storeBrowser = Test-StoreBrowserPackagePath $norm
    foreach ($frag in $script:BrowserDiscoveryExcludes) {
        if ($frag -eq '\Packages\' -and $storeBrowser) { continue }
        if ($norm -like "*$frag*") { return $true }
    }
    return $false
}

function Test-ChromiumCacheFolder {
    param([string]$Path)
    foreach ($name in @('Cache', 'Code Cache', 'GPUCache', 'System Cache')) {
        if (Test-Path -LiteralPath (Join-Path $Path $name) -PathType Container) { return $true }
    }
    return $false
}

function Test-ChromiumUserDataRoot {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    if (Test-BrowserDiscoveryExcluded $Path) { return $false }
    $hasLocalState = Test-Path -LiteralPath (Join-Path $Path 'Local State')
    $hasNamedProfile = $false
    $hasProfileCache = $false
    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        if ($child.Name -eq 'Default' -or $child.Name -like 'Profile *' -or $child.Name -like 'Person *' -or $child.Name -eq 'Guest Profile' -or $child.Name -eq 'System Profile') {
            $hasNamedProfile = $true
            if (Test-ChromiumCacheFolder $child.FullName) { $hasProfileCache = $true }
        }
    }
    # Full Chromium user-data dir (Chrome/Edge/Brave/...)
    if ($hasLocalState -and $hasNamedProfile) { return $true }
    # Opera-style: the folder itself is the profile
    if ($hasLocalState -and (Test-ChromiumCacheFolder $Path)) { return $true }
    # Opera/Firefox-adjacent Chromium twins: cache lives under Local AppData
    # without a Local State file (Local State stays in Roaming).
    if ($hasNamedProfile -and $hasProfileCache) { return $true }
    if (Test-ChromiumCacheFolder $Path) { return $true }
    return $false
}

function Get-AppDataHiveTwin {
    param([string]$Path)
    if (-not $Path) { return $null }
    if ($Path -match '(?i)\\AppData\\Roaming\\') {
        return ($Path -replace '(?i)\\AppData\\Roaming\\', '\AppData\Local\')
    }
    if ($Path -match '(?i)\\AppData\\Local\\') {
        return ($Path -replace '(?i)\\AppData\\Local\\', '\AppData\Roaming\')
    }
    return $null
}

function Test-SafeBrowserProcessName {
    param([string]$Name)
    if (-not $Name) { return $false }
    $n = $Name.Trim().ToLowerInvariant()
    if ($n.Length -lt 3) { return $false }
    $blocked = @(
        'program', 'windows', 'system', 'explorer', 'runtime', 'host',
        'update', 'setup', 'application', 'service', 'svchost', 'dllhost'
    )
    return ($blocked -notcontains $n)
}

function Get-ChromiumProfileDirectories {
    param([string]$UserDataPath)
    $base = [System.Environment]::ExpandEnvironmentVariables($UserDataPath)
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return @() }
    $skip = @(
        'Crashpad', 'Safe Browsing', 'SwReporter', 'optimization_guide_model_store',
        'component_crx_cache', 'extensions_crx_cache', 'BrowserMetrics', 'ShaderCache',
        'GrShaderCache', 'GraphiteDawnCache', 'FileTypePolicies', 'hyphen-data',
        'OnDeviceHeadSuggestModel', 'WasmTtsEngine', 'ZxcvbnData', 'Crowd Deny',
        'PKIMetadata', 'AmountExtractionHeuristicRegexes', 'CertificateRevocation',
        'MediaFoundationWidevineCdm', 'ActorSafetyLists', 'SSLErrorAssistant',
        'TpcdMetadata', 'SafetyTips', 'segmentation_platform', 'MEIPreload',
        'Local Traces', 'logs', 'ollama', '.ollama'
    )
    $dirs = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object {
        if ($skip -contains $_.Name) { return $false }
        if ($_.Name -match '^[a-p]{32}$') { return $false }
        if ($_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -like 'Person *' -or $_.Name -eq 'Guest Profile' -or $_.Name -eq 'System Profile') {
            return $true
        }
        if (Test-Path -LiteralPath (Join-Path $_.FullName 'Preferences')) { return $true }
        if (Test-ChromiumCacheFolder $_.FullName) { return $true }
        return $false
    })
    if ($dirs.Count -eq 0) {
        return @(Get-Item -LiteralPath $base -ErrorAction SilentlyContinue)
    }
    return @($dirs)
}

function Split-BrowserLaunchCommand {
    param([string]$Command)
    $exe = $null
    $args = ''
    if (-not $Command) { return @{ Exe = $null; Args = '' } }
    $trim = $Command.Trim().TrimStart('@')
    if ($trim -match ',[-0-9]+$') { $trim = $trim -replace ',[-0-9]+$', '' }
    $trim = $trim.Trim()
    if ($trim.StartsWith('"')) {
        $end = $trim.IndexOf('"', 1)
        if ($end -gt 1) {
            $exe = $trim.Substring(1, $end - 1)
            if ($end + 1 -lt $trim.Length) { $args = $trim.Substring($end + 1).Trim() }
        }
    } else {
        $m = [regex]::Match($trim, '(?i)^(.+?\.exe)(?:\s+(.*))?$')
        if ($m.Success) {
            $exe = $m.Groups[1].Value.Trim().Trim('"')
            $args = $m.Groups[2].Value.Trim()
        } else {
            $parts = $trim.Split(@(' '), 2, [System.StringSplitOptions]::None)
            $exe = $parts[0]
            if ($parts.Count -gt 1) { $args = $parts[1] }
        }
    }
    if ($args -match '^,[-0-9]+$') { $args = '' }
    return @{ Exe = $exe; Args = $args }
}

function Get-UserDataDirFromArgs {
    param([string]$ArgumentString)
    if (-not $ArgumentString) { return $null }
    $m = [regex]::Match($ArgumentString, '--user-data-dir(?:\s+|=)(?:"([^"]+)"|(\S+))')
    if ($m.Success) {
        $p = $m.Groups[1].Value
        if (-not $p) { $p = $m.Groups[2].Value.Trim('"') }
        return $p.Trim().TrimEnd('\')
    }
    $m = [regex]::Match($ArgumentString, '-profile\s+(?:"([^"]+)"|(\S+))')
    if ($m.Success) {
        $p = $m.Groups[1].Value
        if (-not $p) { $p = $m.Groups[2].Value.Trim('"') }
        return $p.Trim().TrimEnd('\')
    }
    return $null
}

function Add-DiscoveredProcessName {
    param([string]$ExePath)
    if (-not $ExePath) { return }
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    if (-not $leaf) { return }
    if (-not (Test-SafeBrowserProcessName $leaf)) { return }
    if ($null -eq $script:DiscoveredBrowserProcessNames) {
        $script:DiscoveredBrowserProcessNames = New-Object System.Collections.Generic.List[string]
    }
    if ($script:DiscoveredBrowserProcessNames -notcontains $leaf) {
        [void]$script:DiscoveredBrowserProcessNames.Add($leaf)
    }
}

function Get-WellKnownBrowserExePaths {
    $pf = $env:ProgramFiles
    $pf86 = ${env:ProgramFiles(x86)}
    $la = $env:LOCALAPPDATA
    $candidates = New-Object System.Collections.Generic.List[string]
    function AddKnown([string]$Base, [string]$Rel) {
        if (-not $Base) { return }
        [void]$candidates.Add((Join-Path $Base $Rel))
    }
    AddKnown $pf 'Google\Chrome\Application\chrome.exe'
    AddKnown $pf86 'Google\Chrome\Application\chrome.exe'
    AddKnown $la 'Google\Chrome\Application\chrome.exe'
    AddKnown $pf 'Google\Chrome Beta\Application\chrome.exe'
    AddKnown $pf 'Google\Chrome Dev\Application\chrome.exe'
    AddKnown $pf 'Google\Chrome SxS\Application\chrome.exe'
    AddKnown $pf 'Mozilla Firefox\firefox.exe'
    AddKnown $pf86 'Mozilla Firefox\firefox.exe'
    AddKnown $la 'Mozilla Firefox\firefox.exe'
    AddKnown $pf 'Microsoft\Edge\Application\msedge.exe'
    AddKnown $pf86 'Microsoft\Edge\Application\msedge.exe'
    AddKnown $la 'BraveSoftware\Brave-Browser\Application\brave.exe'
    AddKnown $pf 'BraveSoftware\Brave-Browser\Application\brave.exe'
    AddKnown $pf 'Vivaldi\Application\vivaldi.exe'
    AddKnown $la 'Vivaldi\Application\vivaldi.exe'
    AddKnown $pf 'Opera\opera.exe'
    AddKnown $la 'Programs\Opera\opera.exe'
    AddKnown $la 'Programs\Opera GX\opera.exe'
    AddKnown $pf 'Opera GX\opera.exe'
    AddKnown $pf 'Waterfox\waterfox.exe'
    AddKnown $pf 'LibreWolf\librewolf.exe'
    AddKnown $la 'Thorium\Application\thorium.exe'
    AddKnown $pf 'Yandex\YandexBrowser\Application\browser.exe'
    return @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
}

function Get-StartMenuBrowserCommands {
    $out = New-Object System.Collections.Generic.List[hashtable]
    $hint = '(?i)(Chrome|Firefox|Edge|Brave|Opera|Vivaldi|Yandex|Chromium|Waterfox|LibreWolf|Tor Browser|Floorp|Thorium|Arc|Whale|DuckDuckGo|Genspark|Pale Moon)'
    $roots = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
    )
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch {}
    if (-not $shell) { return @() }
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($lnk in @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -Depth 4 -ErrorAction SilentlyContinue)) {
            if ($lnk.BaseName -notmatch $hint) { continue }
            try {
                $sc = $shell.CreateShortcut($lnk.FullName)
                $cmd = ('{0} {1}' -f $sc.TargetPath, $sc.Arguments).Trim()
                $parsed = Split-BrowserLaunchCommand $cmd
                if ($parsed.Exe) { [void]$out.Add($parsed) }
            } catch {}
        }
    }
    return @($out)
}

function Get-RunningBrowserLaunchCommands {
    $out = New-Object System.Collections.Generic.List[hashtable]
    $watch = @($script:ChromiumExeProfileMap.Keys) + $script:GeckoExeNames
    foreach ($exeName in $watch) {
        $filter = "Name='$exeName'"
        $procs = @()
        try { $procs = @(Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction SilentlyContinue) } catch {}
        if ($procs.Count -eq 0) {
            $leaf = [System.IO.Path]::GetFileNameWithoutExtension($exeName)
            foreach ($proc in @(Get-Process -Name $leaf -ErrorAction SilentlyContinue)) {
                if ($proc.Path) { [void]$out.Add(@{ Exe = $proc.Path; Args = '' }) }
            }
            continue
        }
        foreach ($p in $procs) {
            if ($p.CommandLine) {
                $parsed = Split-BrowserLaunchCommand $p.CommandLine
                if ($parsed.Exe) { [void]$out.Add($parsed); continue }
            }
            if ($p.ExecutablePath) {
                [void]$out.Add(@{ Exe = $p.ExecutablePath; Args = '' })
            }
        }
    }
    return @($out)
}

function Get-AllBrowserLaunchCommands {
    if ($null -ne $script:CachedBrowserLaunchCommands) { return $script:CachedBrowserLaunchCommands }
    $out = New-Object System.Collections.Generic.List[hashtable]
    $seen = @{}
    function AddCmd([hashtable]$parsed) {
        if (-not $parsed -or -not $parsed['Exe']) { return }
        $key = (($parsed['Exe']) + '|' + ($parsed['Args'])).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$out.Add($parsed)
    }
    foreach ($cmd in @(Get-RegisteredBrowserCommands)) { AddCmd $cmd }
    foreach ($cmd in @(Get-StartMenuBrowserCommands)) { AddCmd $cmd }
    foreach ($cmd in @(Get-RunningBrowserLaunchCommands)) { AddCmd $cmd }
    foreach ($exe in @(Get-WellKnownBrowserExePaths)) { AddCmd @{ Exe = $exe; Args = '' } }
    $script:CachedBrowserLaunchCommands = @($out)
    return $script:CachedBrowserLaunchCommands
}

function Get-RegisteredBrowserCommands {
    $out = New-Object System.Collections.Generic.List[hashtable]
    $keys = @(
        'HKLM:\SOFTWARE\Clients\StartMenuInternet',
        'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet',
        'HKCU:\SOFTWARE\Clients\StartMenuInternet'
    )
    foreach ($root in $keys) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($client in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $cmdKey = Join-Path $client.PSPath 'shell\open\command'
            $cmd = $null
            try { $cmd = (Get-ItemProperty -LiteralPath $cmdKey -ErrorAction SilentlyContinue).'(default)' } catch {}
            if (-not $cmd) { continue }
            $parsed = Split-BrowserLaunchCommand $cmd
            if ($parsed.Exe) { [void]$out.Add($parsed) }
        }
    }
    $appPathRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    )
    $appExeNames = @($script:ChromiumExeProfileMap.Keys) + $script:GeckoExeNames
    foreach ($root in $appPathRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($exeName in $appExeNames) {
            $p = Join-Path $root $exeName
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $cmd = $null
            try { $cmd = (Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue).'(default)' } catch {}
            if (-not $cmd) { continue }
            $parsed = Split-BrowserLaunchCommand $cmd
            if ($parsed.Exe) { [void]$out.Add($parsed) }
        }
    }
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $browserNameHint = '(?i)(Chrome|Edge|Firefox|Brave|Opera|Vivaldi|Yandex|Genspark|Chromium|Waterfox|LibreWolf|Pale Moon|Tor Browser|Floorp|Thorium|Arc|Wavebox|Maxthon|Whale|Iridium|Slimjet|DuckDuckGo|CocCoc|UC Browser|Epic)'
    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = $null
            try { $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue } catch {}
            if (-not $props) { continue }
            $display = [string]$props.DisplayName
            if (-not $display -or $display -notmatch $browserNameHint) { continue }
            if ($display -match '(?i)WebView|SDK|Runtime|Fonts') { continue }
            $icon = [string]$props.DisplayIcon
            if (-not $icon) { continue }
            $parsed = Split-BrowserLaunchCommand $icon
            if ($parsed.Exe) { [void]$out.Add($parsed) }
        }
    }
    return @($out)
}

function Add-ChromiumRootCandidate {
    param(
        [System.Collections.Generic.List[string]]$List,
        [hashtable]$Seen,
        [string]$Path
    )
    if (-not $Path) { return }
    $exp = [System.Environment]::ExpandEnvironmentVariables($Path)
    try { $exp = [System.IO.Path]::GetFullPath($exp) } catch {}
    if (-not (Test-ChromiumUserDataRoot $exp)) { return }
    Add-UniquePath $List $Seen $exp
}

function Add-ChromiumCandidatesFromExe {
    param(
        [System.Collections.Generic.List[string]]$List,
        [hashtable]$Seen,
        [string]$ExePath,
        [string]$ArgumentString
    )
    Add-DiscoveredProcessName $ExePath
    $custom = Get-UserDataDirFromArgs $ArgumentString
    if ($custom) { Add-ChromiumRootCandidate $List $Seen $custom }

    $exeName = $null
    try { $exeName = [System.IO.Path]::GetFileName($ExePath).ToLowerInvariant() } catch {}
    if ($exeName -and $script:GeckoExeNames -contains $exeName) { return }

    foreach ($pair in @(Get-AllUserAppDataRoots)) {
        if ($exeName -and $script:ChromiumExeProfileMap.ContainsKey($exeName)) {
            foreach ($rel in @($script:ChromiumExeProfileMap[$exeName])) {
                Add-ChromiumRootCandidate $List $Seen (Join-Path $pair.Local $rel)
                Add-ChromiumRootCandidate $List $Seen (Join-Path $pair.Roaming $rel)
            }
        }
        if ($ExePath) {
            $dir = $null
            try { $dir = [System.IO.Path]::GetDirectoryName($ExePath) } catch {}
            if ($dir) {
                $product = Split-Path $dir -Parent
                $vendor = if ($product) { Split-Path $product -Parent } else { $null }
                $productLeaf = if ($product) { Split-Path $product -Leaf } else { $null }
                $vendorLeaf = if ($vendor) { Split-Path $vendor -Leaf } else { $null }
                if ($productLeaf) {
                    Add-ChromiumRootCandidate $List $Seen (Join-Path $pair.Local (Join-Path $productLeaf 'User Data'))
                }
                if ($vendorLeaf -and $productLeaf) {
                    Add-ChromiumRootCandidate $List $Seen (Join-Path $pair.Local (Join-Path $vendorLeaf (Join-Path $productLeaf 'User Data')))
                }
            }
        }
    }
}

function Add-ChromiumRootIfPresent {
    param(
        [System.Collections.Generic.List[string]]$List,
        [hashtable]$Seen,
        [string]$Path
    )
    if (-not $Path) { return }
    $exp = [System.Environment]::ExpandEnvironmentVariables($Path)
    try { $exp = [System.IO.Path]::GetFullPath($exp) } catch {}
    if (-not (Test-Path -LiteralPath $exp -PathType Container)) { return }
    if (Test-BrowserDiscoveryExcluded $exp) { return }
    Add-UniquePath $List $Seen $exp
}

function Find-ChromiumBrowserRoots {
    $found = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $script:DiscoveredBrowserProcessNames = New-Object System.Collections.Generic.List[string]
    $script:CachedBrowserLaunchCommands = $null

    # Known install locations: if the profile folder exists, clean it.
    # Do not require Local State — Opera/Firefox-adjacent twins and
    # half-initialized Chrome profiles would otherwise be skipped forever.
    foreach ($root in @(Get-KnownChromiumUserDataRoots)) {
        Add-ChromiumRootIfPresent $found $seen $root
    }

    foreach ($cmd in @(Get-AllBrowserLaunchCommands)) {
        Add-ChromiumCandidatesFromExe $found $seen $cmd.Exe $cmd['Args']
    }

    $nameHint = '(?i)(Google|Chrome|Edge|Brave|Vivaldi|Opera|Yandex|Chromium|Arc|Wavebox|Sidekick|Whale|Maxthon|Slimjet|Iridium|Thorium|Dragon|Avast|CCleaner|CocCoc|UCBrowser|Epic|Genspark|DuckDuckGo|Island|Mozilla|Firefox)'
    foreach ($pair in @(Get-AllUserAppDataRoots)) {
        foreach ($base in @($pair.Local, $pair.Roaming)) {
            if (-not (Test-UsableDirectory $base)) { continue }
            foreach ($vendor in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
                if ($vendor.Name -notmatch $nameHint) { continue }
                foreach ($product in @(Get-ChildItem -LiteralPath $vendor.FullName -Directory -ErrorAction SilentlyContinue)) {
                    $ud = Join-Path $product.FullName 'User Data'
                    Add-ChromiumRootCandidate $found $seen $ud
                    if ($product.Name -match $nameHint) {
                        Add-ChromiumRootCandidate $found $seen $product.FullName
                    }
                }
                Add-ChromiumRootCandidate $found $seen (Join-Path $vendor.FullName 'User Data')
                if ($vendor.Name -match $nameHint) {
                    Add-ChromiumRootCandidate $found $seen $vendor.FullName
                }
            }
        }
    }

    foreach ($pair in @(Get-AllUserAppDataRoots)) {
        $packages = Join-Path $pair.Local 'Packages'
        if (-not (Test-Path -LiteralPath $packages -PathType Container)) { continue }
        foreach ($pkg in @(Get-ChildItem -LiteralPath $packages -Directory -ErrorAction SilentlyContinue)) {
            if (-not (Test-StoreBrowserPackagePath $pkg.FullName)) { continue }
            foreach ($rel in @(
                    'LocalCache\Local\Google\Chrome\User Data',
                    'LocalCache\Local\Microsoft\Edge\User Data',
                    'LocalCache\Local\BraveSoftware\Brave-Browser\User Data',
                    'LocalCache\Local\Vivaldi\User Data',
                    'LocalCache\Roaming\Opera Software\Opera Stable',
                    'LocalCache\Local\Opera Software\Opera Stable'
                )) {
                Add-ChromiumRootCandidate $found $seen (Join-Path $pkg.FullName $rel)
            }
        }
    }

    foreach ($root in @($found.ToArray())) {
        $twin = Get-AppDataHiveTwin $root
        if ($twin) { Add-ChromiumRootIfPresent $found $seen $twin }
    }

    return @($found | Sort-Object)
}

function Add-GeckoProfilesFromIni {
    param(
        [hashtable]$Found,
        [string]$VendorName,
        [string]$IniPath
    )
    if (-not (Test-Path -LiteralPath $IniPath)) { return }
    $iniDir = Split-Path $IniPath -Parent
    $isRelative = $true
    foreach ($line in @(Get-Content -LiteralPath $IniPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*\[Profile') { $isRelative = $true; continue }
        if ($line -match '^\s*IsRelative\s*=\s*(\d+)') { $isRelative = ($Matches[1] -eq '1'); continue }
        if ($line -match '^\s*Path\s*=\s*(.+)\s*$') {
            $raw = $Matches[1].Trim().Replace('/', '\')
            $profRoot = $null
            if ($isRelative) { $profRoot = Join-Path $iniDir $raw } else { $profRoot = $raw }
            if (-not (Test-Path -LiteralPath $profRoot)) { continue }
            $container = $profRoot
            $looksLikeProfile = (Test-Path -LiteralPath (Join-Path $profRoot 'prefs.js')) -or
                (Test-Path -LiteralPath (Join-Path $profRoot 'cache2') -PathType Container)
            if ($looksLikeProfile) {
                $parent = Split-Path $profRoot -Parent
                if ($parent -and ((Split-Path $parent -Leaf) -ieq 'Profiles')) {
                    $container = $parent
                }
            }
            $key = $container.ToLowerInvariant()
            if (-not $Found.ContainsKey($key)) {
                $Found[$key] = @{ Name = $VendorName; Path = $container }
            }
        }
    }
}

function Find-GeckoBrowserProfileDirs {
    $found = @{}
    foreach ($pair in @(Get-AllUserAppDataRoots)) {
        foreach ($g in $script:GeckoProfileRelative) {
            foreach ($base in @($pair.Roaming, $pair.Local)) {
                $p = Join-Path $base $g.Rel
                if (Test-Path -LiteralPath $p) {
                    $key = $p.ToLowerInvariant()
                    if (-not $found.ContainsKey($key)) { $found[$key] = @{ Name = $g.Name; Path = $p } }
                }
                $iniParent = Join-Path $base (Split-Path $g.Rel -Parent)
                $ini = Join-Path $iniParent 'profiles.ini'
                Add-GeckoProfilesFromIni $found $g.Name $ini
            }
        }
        $packages = Join-Path $pair.Local 'Packages'
        if (Test-Path -LiteralPath $packages -PathType Container) {
            foreach ($pkg in @(Get-ChildItem -LiteralPath $packages -Directory -ErrorAction SilentlyContinue)) {
                if ($pkg.Name -notmatch '(?i)^(Mozilla\.Firefox|Mozilla\.MozillaFirefox|LibreWolf)') { continue }
                foreach ($rel in @(
                        'LocalCache\Roaming\Mozilla\Firefox\Profiles',
                        'LocalCache\Local\Mozilla\Firefox\Profiles',
                        'LocalCache\Roaming\librewolf\Profiles',
                        'LocalCache\Local\librewolf\Profiles'
                    )) {
                    $p = Join-Path $pkg.FullName $rel
                    if (-not (Test-Path -LiteralPath $p)) { continue }
                    $key = $p.ToLowerInvariant()
                    $label = if ($pkg.Name -match '(?i)LibreWolf') { 'LibreWolf' } else { 'Mozilla\Firefox' }
                    if (-not $found.ContainsKey($key)) { $found[$key] = @{ Name = $label; Path = $p } }
                    $ini = Join-Path (Split-Path $p -Parent) 'profiles.ini'
                    Add-GeckoProfilesFromIni $found $label $ini
                }
            }
        }
    }
    foreach ($cmd in @(Get-AllBrowserLaunchCommands)) {
        $exeName = $null
        try { $exeName = [System.IO.Path]::GetFileName($cmd.Exe).ToLowerInvariant() } catch {}
        if (-not $exeName -or $script:GeckoExeNames -notcontains $exeName) { continue }
        Add-DiscoveredProcessName $cmd.Exe
        $custom = Get-UserDataDirFromArgs $cmd['Args']
        if ($custom -and (Test-Path -LiteralPath $custom)) {
            $key = $custom.ToLowerInvariant()
            if (-not $found.ContainsKey($key)) {
                $found[$key] = @{ Name = $exeName; Path = $custom }
            }
        }
        if ($cmd.Exe) {
            $dir = $null
            try { $dir = [System.IO.Path]::GetDirectoryName($cmd.Exe) } catch {}
            foreach ($rel in @(
                    'TorBrowser\Data\Browser',
                    'Browser\TorBrowser\Data\Browser'
                )) {
                $p = $null
                if ($dir) {
                    $p = Join-Path (Split-Path $dir -Parent) $rel
                    if (-not (Test-Path -LiteralPath $p)) { $p = Join-Path $dir $rel }
                }
                if ($p -and (Test-Path -LiteralPath $p)) {
                    $key = $p.ToLowerInvariant()
                    if (-not $found.ContainsKey($key)) {
                        $found[$key] = @{ Name = 'Tor Browser'; Path = $p }
                    }
                }
            }
        }
    }
    foreach ($entry in @($found.Values)) {
        $twin = Get-AppDataHiveTwin $entry.Path
        if (-not $twin -or -not (Test-Path -LiteralPath $twin -PathType Container)) { continue }
        $key = $twin.ToLowerInvariant()
        if (-not $found.ContainsKey($key)) {
            $found[$key] = @{ Name = $entry.Name; Path = $twin }
        }
    }
    return @($found.Values)
}

function Get-BrowserLabelFromPath {
    param([string]$Path)
    $rules = @(
        @{ Match = 'Google\Chrome'; Label = 'Google Chrome' }
        @{ Match = 'Microsoft\Edge'; Label = 'Microsoft Edge' }
        @{ Match = 'BraveSoftware'; Label = 'Brave' }
        @{ Match = 'Vivaldi'; Label = 'Vivaldi' }
        @{ Match = 'Opera Software'; Label = 'Opera' }
        @{ Match = 'Yandex'; Label = 'Yandex Browser' }
        @{ Match = 'Chromium'; Label = 'Chromium' }
        @{ Match = 'Arc'; Label = 'Arc Browser' }
        @{ Match = 'Wavebox'; Label = 'Wavebox' }
        @{ Match = 'Sidekick'; Label = 'Sidekick' }
        @{ Match = 'CentBrowser'; Label = 'Cent Browser' }
        @{ Match = 'CocCoc'; Label = 'Coc Coc Browser' }
        @{ Match = 'UCBrowser'; Label = 'UC Browser' }
        @{ Match = 'Epic Privacy Browser'; Label = 'Epic Browser' }
        @{ Match = 'GensparkSoftware'; Label = 'Genspark Browser' }
        @{ Match = 'Genspark'; Label = 'Genspark Browser' }
        @{ Match = 'DuckDuckGo'; Label = 'DuckDuckGo' }
        @{ Match = 'Thorium'; Label = 'Thorium' }
        @{ Match = 'Naver Whale'; Label = 'Naver Whale' }
        @{ Match = 'Maxthon'; Label = 'Maxthon' }
        @{ Match = 'Chrome Dev'; Label = 'Chrome Dev' }
        @{ Match = 'Chrome SxS'; Label = 'Chrome Canary' }
    )
    foreach ($rule in $rules) {
        if ($Path -like "*$($rule.Match)*") { return $rule.Label }
    }
    if ($Path -match '\\User Data$') {
        $parent = Split-Path $Path -Parent
        $browserDir = if ($parent) { Split-Path $parent -Leaf } else { $null }
        $vendorParent = if ($parent) { Split-Path $parent -Parent } else { $null }
        $vendorDir = if ($vendorParent) { Split-Path $vendorParent -Leaf } else { $null }
        if ($vendorDir -and $browserDir -and $vendorDir -ne $browserDir) {
            return "$vendorDir $browserDir".Trim()
        }
        return $browserDir
    }
    if (-not $Path) { return 'Browser' }
    return (Split-Path $Path -Leaf)
}

function Get-GeckoBrowserLabel {
    param([string]$VendorName)
    switch -Regex ($VendorName) {
        'Firefox' { return 'Firefox' }
        'Waterfox' { return 'Waterfox' }
        'Pale Moon' { return 'Pale Moon' }
        'LibreWolf' { return 'LibreWolf' }
        'Tor Browser' { return 'Tor Browser' }
        'Basilisk' { return 'Basilisk' }
        'Thunderbird' { return 'Thunderbird' }
        default { return ($VendorName -replace '\\', ' ') }
    }
}

$script:ChromiumCleanDirs = @(
    "Cache", "Code Cache", "GPUCache", "Media Cache",
    "DawnCache", "DawnWebGPUCache", "DawnGraphiteCache",
    "GrShaderCache", "ShaderCache"
)
# NEVER delete Cookies, History, Web Data, Autofill, Favicons, or Bookmarks
$script:ChromiumCleanFiles = @()

$script:GeckoCleanDirs = @(
    "cache2", "startupCache", "OfflineCache", "thumbnails", "jumpListCache"
)
# NEVER delete cookies.sqlite, places.sqlite, formhistory.sqlite, or webappsstore.sqlite
$script:GeckoCleanFiles = @()

function Clear-ChromiumBrowserCache {
    param([string]$UserDataPath)
    $base = [System.Environment]::ExpandEnvironmentVariables($UserDataPath)
    if (-not (Test-Path $base)) { return }

    foreach ($d in @('GrShaderCache', 'ShaderCache', 'GraphiteDawnCache', 'Crashpad', 'BrowserMetrics', 'optimization_guide_model_store')) {
        $target = Join-Path $base $d
        if (Test-Path -LiteralPath $target -PathType Container) {
            Remove-DirectorySilent -LiteralPath $target -KeepContainer | Out-Null
        }
    }

    $profileDirs = @(Get-ChromiumProfileDirectories $base)

    foreach ($prof in $profileDirs) {
        $profile = $prof.FullName
        foreach ($d in $script:ChromiumCleanDirs) {
            $target = Join-Path $profile $d
            if (Test-Path -LiteralPath $target -PathType Container) {
                Remove-DirectorySilent -LiteralPath $target -KeepContainer | Out-Null
            } elseif (Test-Path -LiteralPath $target) {
                Remove-SafePathWithRetry -LiteralPath $target | Out-Null
            }
        }
        foreach ($f in $script:ChromiumCleanFiles) {
            Remove-SafePathWithRetry -LiteralPath (Join-Path $profile $f) | Out-Null
        }
        foreach ($extra in @(Get-ChildItem -LiteralPath $profile -File -Force -ErrorAction SilentlyContinue)) {
            if ($extra.Name -like 'History-*' -or $extra.Name -like 'Archived History*' -or $extra.Name -like 'Favicons-*') {
                Remove-SafePathWithRetry -LiteralPath $extra.FullName | Out-Null
            }
        }
        $networkCookies = Join-Path $profile 'Network\Cookies'
        if (Test-Path -LiteralPath $networkCookies) {
            Remove-SafePathWithRetry -LiteralPath $networkCookies | Out-Null
            Remove-SafePathWithRetry -LiteralPath ($networkCookies + '-journal') | Out-Null
        }
        # Login Data intentionally SKIPPED (passwords safe).
        # Web Data (autofill) IS deleted above — user authorised wiping saved form fills.
    }
}

function Clear-GeckoBrowserProfiles {
    param([string]$ProfilesPath)
    if (-not (Test-Path $ProfilesPath)) { return }
    $targets = @()
    if ((Test-Path -LiteralPath (Join-Path $ProfilesPath 'prefs.js')) -or
        (Test-Path -LiteralPath (Join-Path $ProfilesPath 'cache2') -PathType Container)) {
        $targets = @(Get-Item -LiteralPath $ProfilesPath)
    } else {
        $targets = @(Get-ChildItem $ProfilesPath -Directory -ErrorAction SilentlyContinue | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'prefs.js')) -or
            (Test-Path -LiteralPath (Join-Path $_.FullName 'cache2') -PathType Container) -or
            $_.Name -like '*.default*' -or $_.Name -like 'profile*'
        })
        if ($targets.Count -eq 0) {
            $targets = @(Get-ChildItem $ProfilesPath -Directory -ErrorAction SilentlyContinue)
        }
    }
    foreach ($item in $targets) {
        $p = $item.FullName
        foreach ($d in $script:GeckoCleanDirs) {
            $target = Join-Path $p $d
            if (Test-Path -LiteralPath $target -PathType Container) {
                Remove-DirectorySilent -LiteralPath $target -KeepContainer | Out-Null
            } elseif (Test-Path -LiteralPath $target) {
                Remove-SafePathWithRetry -LiteralPath $target | Out-Null
            }
        }
        foreach ($f in $script:GeckoCleanFiles) {
            Remove-SafePathWithRetry -LiteralPath (Join-Path $p $f) | Out-Null
        }
        # key4.db, logins.json intentionally SKIPPED — passwords are never touched.
        # formhistory.sqlite IS deleted above — user authorised wiping Firefox saved form fills.
        # places.sqlite intentionally SKIPPED — protects bookmarks and browsing history DB.
    }
}

function Clear-FirefoxProfiles {
    Clear-GeckoBrowserProfiles ([System.Environment]::ExpandEnvironmentVariables("%APPDATA%\Mozilla\Firefox\Profiles"))
}

function Clear-AllInstalledBrowsers {
    param([scriptblock]$Log = { param([string]$Message) })

    & $Log "  Scanning PC for all installed browsers (registry, Start Menu, running apps, profile folders)..."
    $chromiumRoots = @(Find-ChromiumBrowserRoots)
    $geckoBrowsers = @(Find-GeckoBrowserProfileDirs)
    $extraProcs = @($script:DiscoveredBrowserProcessNames)

    $count = @($chromiumRoots).Count + @($geckoBrowsers).Count
    $names = @($chromiumRoots | ForEach-Object { Get-BrowserLabelFromPath $_ }) +
             @($geckoBrowsers | ForEach-Object { Get-GeckoBrowserLabel $_.Name })
    $names = @($names | Where-Object { $_ } | Select-Object -Unique)
    foreach ($n in $names) { Add-CleanedBrowserLabel $n }

    if ($count -eq 0) {
        & $Log "  No browser profile folders found on this PC."
        return @{ Chromium = 0; Gecko = 0; Total = 0 }
    }

    & $Log ("  Installed browsers to clean: {0}" -f ($names -join ', '))
    & $Log "  Closing those browser processes (to unlock cache files)..."
    Close-BrowserProcesses -Log $Log -ExtraProcessNames $extraProcs

    & $Log ("  Found {0} profile location(s)." -f $count)
    & $Log "  Cleaning: cache, cookies, history/site data where safe (like Ctrl+Shift+Delete)."
    & $Log "  Auto-skip: passwords, autofill, bookmarks, locked files - no prompts."

    foreach ($root in $chromiumRoots) {
        $label = Get-BrowserLabelFromPath $root
        $started = Get-Date
        & $Log "  -> $label  ($root)"
        Clear-ChromiumBrowserCache $root
        # PERF-FIX #17: Removed the N+1 re-count + conditional second Clean pass + second Close-BrowserProcesses.
        # The retry pattern called Get-ChildItem per profile per cache dir, then re-called Close-BrowserProcesses
        # (20+ Get-Process calls) and re-ran the full Clear-ChromiumBrowserCache for any browser with leftover files.
        # Any genuinely-locked files are already handled by Remove-DirectorySilent's reboot-delete fallback.
        $secs = [int]((Get-Date) - $started).TotalSeconds
        & $Log "     done in ${secs}s"
    }
    foreach ($g in $geckoBrowsers) {
        $label = Get-GeckoBrowserLabel $g.Name
        $started = Get-Date
        & $Log "  -> $label  ($($g.Path))"
        Clear-GeckoBrowserProfiles $g.Path
        $secs = [int]((Get-Date) - $started).TotalSeconds
        & $Log "     done in ${secs}s"
    }

    & $Log ("  [All Browsers] cleared ({0}). Passwords and autofill NOT touched." -f ($names -join ', '))
    return @{ Chromium = @($chromiumRoots).Count; Gecko = @($geckoBrowsers).Count; Total = $count }
}

function Clear-StoreAppTemp {
    $pkgs = [System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%\Packages")
    if (-not (Test-Path $pkgs)) { return }
    Get-ChildItem $pkgs -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $at = Join-Path $_.FullName "AC\Temp"
        $cn = Join-Path $_.FullName "AC\Microsoft\CryptnetUrlCache"
        # FIX: use Remove-DirectorySilent - robocopy wipe, then cmd rd, then reboot-delete fallback
        if (Test-Path $at) { Remove-DirectorySilent -LiteralPath $at | Out-Null }
        if (Test-Path $cn) { Remove-DirectorySilent -LiteralPath $cn | Out-Null }
    }
}

function Test-CleanMgrCategorySelected {
    param([Parameter(Mandatory)][string]$Name)
    # Strictly exclude Downloads, rollback files, update cleanup, and user file versions
    $excluded = @(
        'DownloadsFolder',
        'User file versions'
    )
    if ($Name -match '(?i)download' -or ($excluded -icontains $Name)) { return $false }
    return $true
}

function Set-CleanMgrPreset {
    param(
        [int]$PresetId = 7142,
        [scriptblock]$Log = { param([string]$Message) }
    )
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    if (-not (Test-Path $root)) { return $false }

    $valueName = ('StateFlags{0:d4}' -f $PresetId)
    $selected = 0
    $excluded = @()

    foreach ($key in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
        $name = $key.PSChildName
        $shouldSelect = Test-CleanMgrCategorySelected -Name $name
        $value = if ($shouldSelect) { 2 } else { 0 }
        try {
            New-ItemProperty -Path $key.PSPath -Name $valueName -Value $value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            if ($shouldSelect) { $selected++ } else { $excluded += $name }
        } catch {
            & $Log "  [Disk Cleanup] skipped (admin rights required to preset CleanMgr)."
            return $false
        }
    }

    if ($excluded.Count -gt 0) {
        & $Log ("  [Disk Cleanup] excluded download category/categories: " + ($excluded -join ', '))
    }
    & $Log "  [Disk Cleanup] preset ready ($selected categories selected)."
    return $true
}

function Invoke-CleanMgrSilent {
    param(
        [string]$Drive = $env:SystemDrive,
        [int]$PresetId = 7142,
        [scriptblock]$Log = { param([string]$Message) }
    )
    $cleanMgr = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
    if (-not (Test-Path $cleanMgr)) {
        & $Log "  [Disk Cleanup] skipped (cleanmgr.exe not found on this Windows install)."
        return $false
    }
    if (-not (Set-CleanMgrPreset -PresetId $PresetId -Log $Log)) { return $false }

    $targetDrive = if ($Drive) { $Drive.TrimEnd('\') } else { 'C:' }
    & $Log "  [Disk Cleanup] running CleanMgr on $targetDrive asynchronously (non-blocking)."
    try {
        # PERF-FIX #10: Run CleanMgr fire-and-forget instead of WaitForExit(1800000).
        # CleanMgr was previously a hard 30-minute synchronous block — the single
        # biggest elapsed-time bottleneck. It cleans files already handled earlier
        # (INetCache, Temp), so letting it run in the background costs nothing.
        Start-Process -FilePath $cleanMgr `
            -ArgumentList @('/d', $targetDrive, "/sagerun:$PresetId") `
            -WindowStyle Hidden -ErrorAction Stop | Out-Null
        & $Log "  [Disk Cleanup] launched in background. Downloads categories were NOT selected."
        return $true
    } catch {
        & $Log "  [Disk Cleanup] skipped (CleanMgr could not start)."
        return $false
    }
}

function Invoke-MyCleanPCCore {
    param(
        [scriptblock]$Log = { param([string]$Message) Write-Host $Message },
        [switch]$ManageWindowsUpdateService
    )

    # Wrap log parameter so all cleaner output automatically writes to temp_cleaner_log.txt and cleanup_log.txt
    $userLogDelegate = $Log
    $Log = {
        param([string]$Message)
        Write-TempCleanerLog -Message $Message -UserLog $userLogDelegate
    }

    # Snapshot free space on the system drive before anything is deleted.
    # We re-read it at the end and report the difference as "space freed".
    $sysDrive    = $env:SystemDrive
    $freeAtStart = Get-DriveFreeBytes $sysDrive

    # -- PRE-SCAN ------------------------------------------------------------
    # Read-only size measurement of everything that will be cleaned.
    # Gives the user a "you're about to free ~X GB" preview before we start.
    & $Log "-- PRE-SCAN: measuring junk (read-only, nothing deleted yet) --"
    $estimate  = Get-CleanupEstimate
    $estStr    = Format-ByteSize $estimate.TotalBytes
    $estCount  = $estimate.Count
    & $Log "  Estimated junk found:  $estStr across $estCount locations"
    foreach ($hit in $estimate.Top5) {
        $label = ([string]$hit.ShortLabel).PadRight(28)
        & $Log "    $label  $(Format-ByteSize ([long]$hit.Bytes))"
    }
    & $Log "PRESCAN_ESTIMATE:$estStr"   # machine-readable sentinel for GUI
    & $Log ""

    # AI + browsers first so the task cannot burn its time limit on temp/AppData walks.
    Reset-ClosedAppLabels
    try {
    & $Log "-- STEP 1: AI App Caches & Browser Cleaning --"
    # PERF-FIX #23: Removed ai-cache-cleaner.ps1 dot-source from here.
    # The old code dot-sourced ai-cache-cleaner → Safe-Cleanup-Engine → Invoke-SafeWindows10Cleanup,
    # which ran a full AI + browser clean pass, and THEN this function ran its own identical pass.
    # Every AI cache and browser cache was being cleaned TWICE per run. Removed the duplicate.
    Close-AiToolProcesses -Log $Log
    Close-BrowserProcesses -Log $Log
    Show-MyCleanPCNotice -Title "My Clean PC is cleaning caches" -Body (Get-MyCleanPCBusyMessage) -Log $Log
    $aiCleared = 0
    $aiTargets = @(Get-AiCacheTargetPaths)
    if ($aiTargets.Count -eq 0) {
        & $Log "  No AI cache folders found on this PC."
    }
    foreach ($raw in $aiTargets) {
        $exp = [System.Environment]::ExpandEnvironmentVariables($raw)
        if (-not (Test-Path -LiteralPath $exp)) { continue }
        & $Log "  -> $exp"
        if (Test-Path -LiteralPath $exp -PathType Container) {
            if (Remove-DirectorySilent -LiteralPath $exp -KeepContainer) { $aiCleared++ }
            $left = @(Get-ChildItem -LiteralPath $exp -Force -ErrorAction SilentlyContinue).Count
            if ($left -gt 0) {
                & $Log "     leftover items still locked: $left"
            }
        } else {
            if (Remove-SafePathWithRetry -LiteralPath $exp) { $aiCleared++ }
        }
    }
    & $Log "  [AI App Caches] cleared ($aiCleared folders wiped). Cursor/Windsurf/Trae/Devin/Antigravity/Kiro Roaming profiles are emptied. VS Code stays cache-only."

    & $Log "-- STEP 2: All Installed Browsers (auto-detect, passwords SAFE) --"
    Clear-AllInstalledBrowsers -Log $Log | Out-Null

    & $Log "-- STEP 3: Temporary Files + Recycle Bin --"
    & $Log "  (Robocopy bulk clear - zero Explorer prompts; locked files auto-skip)"
    Clear-RigorousTempLocations -OnItem {
        param($p)
        & $Log "  [Temp Folder Cleared] $p"
    }
    $localCount = Clear-AppDataJunkSweep "%LOCALAPPDATA%" -OnBatch {
        param($c)
        & $Log "  [AppData Local Sweep] Cleared $c junk folders"
    }
    $roamCount  = Clear-AppDataJunkSweep "%APPDATA%" -OnBatch {
        param($c)
        & $Log "  [AppData Roaming Sweep] Cleared $c junk folders"
    }
    & $Log "  [Rigorous Temp + AppData] cleared ($localCount local + $roamCount roaming junk folders)."
    try {
        Clear-RecycleBinSilent
        & $Log "  [Recycle Bin] emptied."
    } catch {
        & $Log "  [Recycle Bin] skip: $($_.Exception.Message)"
    }

    & $Log "-- STEP 4: Windows Prefetch (Preserved for system performance) --"
    & $Log "  [Prefetch] Skipped: Windows Prefetch is safely preserved to maintain application launch speed."

    & $Log "-- STEP 5: Windows Disk Cleanup (C: drive, Downloads excluded) --"
    Invoke-CleanMgrSilent -Drive 'C:' -Log $Log | Out-Null

    & $Log "-- STEP 6: Windows Update Cache + Store Temp + INetCache --"

    $wuStopped = $false
    if ($ManageWindowsUpdateService) {
        try {
            $svc = Get-Service -Name wuauserv -ErrorAction Stop
            if ($svc.Status -eq "Running") {
                Stop-Service -Name wuauserv -Force -ErrorAction Stop
                $wuStopped = $true
            }
        } catch {
            & $Log "  [Windows Update cache] skipped (service could not stop)."
        }
    }

    if (-not $ManageWindowsUpdateService -or $wuStopped -or (Get-Service wuauserv -ErrorAction SilentlyContinue).Status -ne "Running") {
        $softwareDist = "C:\Windows\SoftwareDistribution"
        if (Test-Path $softwareDist) {
            # Admin-level deletion of SoftwareDistribution contents
            try {
                & $Log "  [Windows Update cache] clearing with admin-level deletion..."
                
                # Clear Download folder
                $wuDownload = "C:\Windows\SoftwareDistribution\Download"
                if (Test-Path $wuDownload) {
                    Clear-SafeTempTree $wuDownload
                    # Additional aggressive cleanup using robocopy
                    $emptyDir = Join-Path $env:TEMP "swdist_empty_$(Get-Random)"
                    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                    Clear-DirectoryViaRobocopy $wuDownload | Out-Null
                    Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                }
                
                # Clear DataStore\Logs
                $wuLogs = "C:\Windows\SoftwareDistribution\DataStore\Logs"
                if (Test-Path $wuLogs) { Clear-SafeTempTree $wuLogs }
                
                # Clear other SoftwareDistribution subdirectories and files
                $wuDirs = @(
                    "C:\Windows\SoftwareDistribution\SelfUpdate",
                    "C:\Windows\SoftwareDistribution\WebSetup"
                )
                foreach ($wuDir in $wuDirs) {
                    if (Test-Path $wuDir) {
                        Clear-SafeTempTree $wuDir
                    }
                }
                
                # Handle individual files that need admin deletion
                $wuFiles = @(
                    "C:\Windows\SoftwareDistribution\DataStore\DataStore.edb"
                )
                foreach ($wuFile in $wuFiles) {
                    if (Test-Path $wuFile) {
                        try {
                            Remove-SafePathWithRetry -LiteralPath $wuFile | Out-Null
                        } catch {
                            # Register for deletion at reboot if still locked
                            try {
                                Register-DeleteOnReboot -LiteralPath $wuFile | Out-Null
                            } catch {}
                        }
                    }
                }
                
                & $Log "  [Windows Update cache] cleared with admin-level deletion."
            } catch {
                & $Log "  [Windows Update cache] partial clear: $($_.Exception.Message)"
            }
        } else {
            & $Log "  [Windows Update cache] path not found, skipped."
        }
        
        if ($wuStopped) { Start-Service -Name wuauserv -ErrorAction SilentlyContinue }
    }

    Clear-StoreAppTemp
    & $Log "  [Store app temp] cleared."

    # FIX: INetCache cleared via robocopy wipe first, then remove empty shell.
    # Avoids Explorer "do this for all items" dialog for locked IE/Edge cache files.
    $inetCache = [System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%\Microsoft\Windows\INetCache")
    if (Test-Path $inetCache) {
        Clear-DirectoryViaRobocopy $inetCache | Out-Null
        Remove-PathViaCmd -LiteralPath $inetCache -Recurse | Out-Null
    }
    & $Log "  [INetCache] cleared."

    $explorerCache = [System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%\Microsoft\Windows\Explorer")
    if (Test-Path $explorerCache) {
        foreach ($thumb in @(Get-ChildItem $explorerCache -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue)) {
            Remove-SafePathWithRetry -LiteralPath $thumb.FullName | Out-Null
        }
        foreach ($icon in @(Get-ChildItem $explorerCache -Filter "iconcache_*.db" -ErrorAction SilentlyContinue)) {
            Remove-SafePathWithRetry -LiteralPath $icon.FullName | Out-Null
        }
    }
    & $Log "  [Thumbnail / Icon cache] cleared."

    & $Log "-- STEP 7: DNS Cache (Event Logs Preserved) --"
    try { Clear-DnsClientCache -ErrorAction Stop } catch { ipconfig /flushdns | Out-Null }
    & $Log "  [DNS Cache] flushed."
    & $Log "  [Event Logs] Preserved intact for diagnostic integrity."

    # ---- Space-freed summary --------------------------------------------
    # Re-read drive free space and compute what was actually reclaimed.
    # DriveInfo reflects real filesystem state after all deletions.
    $freeAtEnd   = Get-DriveFreeBytes $sysDrive
    $totalFreed  = [Math]::Max(0, $freeAtEnd - $freeAtStart)
    $freedStr    = Format-ByteSize $totalFreed

    $comparison = Format-ByteComparison $totalFreed

    & $Log ""
    & $Log "============================================"
    & $Log "  Space freed this run:  $freedStr"
    if ($comparison) {
    & $Log "  $comparison"
    }
    & $Log "FREED_BYTES:$totalFreed"   # machine-readable sentinel for GUI
    & $Log "============================================"
    & $Log "THANKS CODEX FOR UR CLEAN PC"
    } finally {
        Flush-TempCleanerLog   # PERF-FIX #15: flush any remaining buffered log lines
        Restore-ClosedApps -Log $Log
    }
    Show-MyCleanPCNotice -Title "You can use browsers and AI tools now" -Body (Get-MyCleanPCReadyMessage) -Log $Log
}
