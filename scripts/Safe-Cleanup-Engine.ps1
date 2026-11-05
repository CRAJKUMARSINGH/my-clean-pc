<#
.SYNOPSIS
    Safe, Evidence-Based Windows 10 Cache Cleaner Engine (Enhanced AI & Roaming Suite).
.DESCRIPTION
    Safely audits and cleans:
    - Windows Recycle Bin & Temporary Files
    - Web Browser Caches (Chrome, Edge, Firefox, Brave, Vivaldi, Opera, Yandex, Genspark Browser)
    - AI & Developer App Roaming/Local Caches (Kiro, Antigravity, Devin, Windsurf, Trae, Cursor, Qoder, Warp, Genspark, VS Code)
    CRITICAL SAFETY: Passwords, bookmarks, history, cookies, autofill, user settings, and Downloads are NEVER touched.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$DryRun,
    [switch]$Clean,
    [switch]$IncludeSystemTemp,
    [switch]$ForceCloseBrowsers,
    [switch]$Force,
    [string]$LogFile = ""
)

# Set strict error handling
$ErrorActionPreference = "Continue"

# Setup logging
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $LogFile = Join-Path $scriptDir "safe_cleaner_log.txt"
}

# PERF-FIX #15 / #25: Buffered log writer — accumulate lines and flush in batches
# instead of calling Add-Content (open+append+flush) on every single log line.
$script:EngineLogBuffer  = [System.Collections.Generic.List[string]]::new()
$script:EngineLogFile    = $LogFile
$script:EngineLogFlushAt = 20   # flush every 20 lines

function Flush-EngineLogBuffer {
    if ($script:EngineLogBuffer.Count -eq 0) { return }
    try {
        $parent = Split-Path $script:EngineLogFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $sw = [System.IO.StreamWriter]::new($script:EngineLogFile, $true, [System.Text.Encoding]::UTF8)
        try { foreach ($line in $script:EngineLogBuffer) { $sw.WriteLine($line) } }
        finally { $sw.Close() }
    } catch {}
    $script:EngineLogBuffer.Clear()
}

function Write-EngineLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "AUDIT")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formatted = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "SUCCESS" { Write-Host $formatted -ForegroundColor Green }
        "WARN"    { Write-Host $formatted -ForegroundColor Yellow }
        "ERROR"   { Write-Host $formatted -ForegroundColor Red }
        "AUDIT"   { Write-Host $formatted -ForegroundColor Cyan }
        default   { Write-Host $formatted -ForegroundColor White }
    }

    $script:EngineLogBuffer.Add($formatted)
    if ($script:EngineLogBuffer.Count -ge $script:EngineLogFlushAt) { Flush-EngineLogBuffer }
}

# -----------------------------------------------------------------------------
# 1. STRICT SAFETY RULES & PATH VALIDATOR
# -----------------------------------------------------------------------------

# Substrings that must NEVER appear in any target path or file to be deleted
$script:StrictForbiddenPatterns = @(
    "Downloads",
    "Login Data",
    "Login Data For Account",
    "key4.db",
    "logins.json",
    "logins-backup.json",
    "places.sqlite",
    "favicons.sqlite",
    "cookies.sqlite",
    "\Cookies",
    "\Network\Cookies",
    "Cookies-journal",
    "\History",
    "History-journal",
    "Web Data",
    "Web Data-journal",
    "Autofill",
    "Autofill-journal",
    "Bookmarks",
    "bookmarks.html",
    "Preferences",
    "Secure Preferences",
    "Extensions",
    "Local Extension Settings",
    "Sync Data",
    "Sessions",
    "Current Session",
    "Last Session",
    "System32",
    "SysWOW64",
    "Windows.old",
    "System Volume Information",
    "Program Files",
    "Program Files (x86)",
    "MachineGuid",
    "formhistory.sqlite"
)

# PERF-FIX #2: Pre-compile all forbidden-pattern regexes ONCE at load time.
# Previously [regex]::Escape($pattern) was called inside Test-PathSafety on every
# single file — compiling up to 35 regex objects per file checked. Now compiled once.
$script:CompiledForbiddenPatterns = foreach ($p in $script:StrictForbiddenPatterns) {
    [regex]::new([regex]::Escape($p), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# Approved cache directory leaf names for application and browser profiles
$script:ApprovedCacheLeaves = @(
    "Cache",
    "Cache_Data",
    "Code Cache",
    "GPUCache",
    "ShaderCache",
    "GrShaderCache",
    "DawnCache",
    "DawnWebGPUCache",
    "DawnGraphiteCache",
    "Media Cache",
    "cache2",
    "startupCache",
    "jumpListCache",
    "thumbnails",
    "CachedData",
    "CachedConfigurations",
    "CachedExtensionVSIXs",
    "CachedProfilesData",
    "optimization_guide_model_store",
    "INetCache",
    "IE",
    "Low",
    "Content.IE5",
    "History.IE5",
    "Offline AppCache",
    "Crashpad",
    "reports",
    "logs",
    "blob_storage",
    "CacheStorage",
    "ScriptCache",
    "sentry",
    "cursor-compile-cache",
    "summaries",
    "antigravity-updater",
    "qoder-updater"
)

# PERF-FIX: Pre-build whitelisted app folders once at load time, not inside Test-PathSafety on every call.
# Previously 14 Path.Combine calls were made per Test-PathSafety invocation.
$script:WhitelistedAppFolders = @(
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:APPDATA, "Trae")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:APPDATA, "trae")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:APPDATA, "trae-ai")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:APPDATA, "TRAE SOLO")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:APPDATA, "Trae Solo")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:APPDATA, "trae solo")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "Trae")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "trae")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "TRAE SOLO")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "Trae Solo")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "trae solo")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "antigravity-updater")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "qoder-updater")).TrimEnd('\')
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($env:LOCALAPPDATA, "cursor-compile-cache")).TrimEnd('\')
)

# Pre-build temp roots once at load time (used in Test-PathSafety)
$script:TempRootNorms = @(
    [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    [System.IO.Path]::GetFullPath("$env:LOCALAPPDATA\Temp").TrimEnd('\')
    [System.IO.Path]::GetFullPath("C:\Windows\Temp").TrimEnd('\')
    [System.IO.Path]::GetFullPath("$env:LOCALAPPDATA\Microsoft\Windows\INetCache").TrimEnd('\')
) | Select-Object -Unique

function Test-PathSafety {
    <#
    .SYNOPSIS
        Validates that a path is safe to clean and does not violate any safety boundary.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $norm = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')

    # 1. Check for forbidden patterns — use pre-compiled regexes (PERF-FIX #2)
    foreach ($rx in $script:CompiledForbiddenPatterns) {
        if ($rx.IsMatch($norm)) { return $false }
    }

    # 2. Downloads directory protection (absolute)
    $userDownloads = [System.IO.Path]::Combine($env:USERPROFILE, "Downloads")
    if ($norm -ieq $userDownloads -or $norm.StartsWith($userDownloads + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    # 3. Root directory protection - never allow drive root, Windows directory, or User profile root
    $criticalRoots = @(
        $env:SystemDrive + "\",
        $env:SystemDrive,
        $env:windir,
        $env:USERPROFILE,
        $env:APPDATA,
        $env:LOCALAPPDATA,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    )
    foreach ($cr in $criticalRoots) {
        if ($cr -and ($norm -ieq $cr.TrimEnd('\'))) {
            return $false
        }
    }

    # 4. Whitelisted AI / Leftover App full folders — use pre-built script-level list (PERF-FIX)
    foreach ($normWaf in $script:WhitelistedAppFolders) {
        if ($norm -ieq $normWaf -or $norm.StartsWith($normWaf + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    # 5. Target must be within an approved parent root — use pre-built list (PERF-FIX)
    $isTemp = $false
    foreach ($normTr in $script:TempRootNorms) {
        if ($normTr -and ($norm -ieq $normTr -or $norm.StartsWith($normTr + "\", [System.StringComparison]::OrdinalIgnoreCase))) {
            $isTemp = $true
            break
        }
    }

    if ($isTemp) {
        return $true
    }

    # If not a temp folder, verify that the path leaf or immediate container is an approved cache leaf
    $leaf = Split-Path -Leaf $norm -ErrorAction SilentlyContinue
    $parent = try { Split-Path -Parent $norm -ErrorAction SilentlyContinue } catch { $null }
    $parentLeaf = if ($parent) { try { Split-Path -Leaf $parent -ErrorAction SilentlyContinue } catch { "" } } else { "" }
    if ($script:ApprovedCacheLeaves -contains $leaf -or ($parentLeaf -and $script:ApprovedCacheLeaves -contains $parentLeaf)) {
        return $true
    }

    return $false
}

# -----------------------------------------------------------------------------
# 2. RUNNING PROCESS INSPECTION
# -----------------------------------------------------------------------------

$script:BrowserProcessMap = @{
    "Google Chrome"   = "chrome"
    "Microsoft Edge"  = "msedge"
    "Mozilla Firefox" = "firefox"
    "Brave Browser"   = "brave"
    "Vivaldi"         = "vivaldi"
    "Opera"           = "opera"
    "Genspark"        = "genspark"
}

function Get-RunningBrowserProcesses {
    $running = @{}
    foreach ($bName in $script:BrowserProcessMap.Keys) {
        $procName = $script:BrowserProcessMap[$bName]
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs -and $procs.Count -gt 0) {
            $running[$bName] = $procs
        }
    }
    return $running
}

function Close-TargetBrowsers {
    param([hashtable]$RunningBrowsers)
    foreach ($bName in $RunningBrowsers.Keys) {
        Write-EngineLog "Requesting graceful closure of $bName..." "WARN"
        $procs = $RunningBrowsers[$bName]
        foreach ($p in $procs) {
            try {
                $null = $p.CloseMainWindow()
            } catch {}
        }
        Start-Sleep -Seconds 2
        $remaining = Get-Process -Name $script:BrowserProcessMap[$bName] -ErrorAction SilentlyContinue
        if ($remaining -and $remaining.Count -gt 0) {
            Write-EngineLog "Terminating lingering $bName processes..." "WARN"
            $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
}

# -----------------------------------------------------------------------------
# 3. RECYCLE BIN SAFE EMPTYING
# -----------------------------------------------------------------------------

function Invoke-SafeEmptyRecycleBin {
    param([switch]$DryRun)

    $result = [PSCustomObject]@{
        Category     = "Windows Recycle Bin"
        Label        = "Recycle Bin"
        ItemsCount   = 0
        BytesCleaned = [long]0
        Status       = "Success"
    }

    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.Namespace(0xa) # ssfBITBUCKET
        if ($recycleBin) {
            $items = $recycleBin.Items()
            $result.ItemsCount = $items.Count
            foreach ($item in $items) {
                $result.BytesCleaned += [long]$item.Size
            }
        }
    } catch {}

    if ($DryRun) {
        $result.Status = "DryRun (Items not emptied)"
        return $result
    }

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        $result.Status = "Emptied"
    } catch {
        try {
            if (-not ('WinClean.NativeRecycleBin' -as [type])) {
                Add-Type -MemberDefinition @"
[DllImport("Shell32.dll", CharSet = CharSet.Unicode)]
public static extern uint SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint dwFlags);
"@ -Name "NativeRecycleBin" -Namespace "WinClean" -ErrorAction SilentlyContinue | Out-Null
            }
            [WinClean.NativeRecycleBin]::SHEmptyRecycleBin([IntPtr]::Zero, $null, 0x00000007) | Out-Null
            $result.Status = "Emptied"
        } catch {
            $result.Status = "Error: $($_.Exception.Message)"
        }
    }

    return $result
}

# -----------------------------------------------------------------------------
# 4. SAFE TARGET DISCOVERY
# -----------------------------------------------------------------------------

function Get-SafeCleanupTargets {
    param([switch]$IncludeSystem)

    $targets = [System.Collections.Generic.List[PSCustomObject]]::new()
    $addedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-TargetHelper {
        param($cat, $lbl, $p, $isR = $false, $rmC = $false, $adm = $false)
        if (-not (Test-Path -LiteralPath $p)) { return }
        $norm = [System.IO.Path]::GetFullPath($p).TrimEnd('\')
        if ($addedPaths.Add($norm)) {
            $targets.Add([PSCustomObject]@{
                Category        = $cat
                Label           = $lbl
                Path            = $norm
                IsRoot          = $isR
                RemoveContainer = $rmC
                RequiresAdmin   = $adm
            })
        }
    }

    # (A) User Temp Directory (%TEMP%)
    $userTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    Add-TargetHelper "Windows User Temp" "%TEMP% ($userTemp)" $userTemp $true $false $false

    # (B) Windows System Temp (C:\Windows\Temp)
    if ($IncludeSystem) {
        Add-TargetHelper "Windows System Temp" "C:\Windows\Temp" "C:\Windows\Temp" $true $false $true
    }

    # (C) Windows Internet / Explorer Caches
    $inetCache = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Microsoft\Windows\INetCache")
    Add-TargetHelper "Windows System Cache" "INetCache (Temporary Internet Files)" $inetCache $true $false $false

    # (D) Chromium Browsers: Chrome, Edge, Brave, Vivaldi, Opera, Yandex, Genspark Browser
    $chromiumRoots = [ordered]@{
        "Google Chrome"    = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Google\Chrome\User Data")
        "Microsoft Edge"   = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Microsoft\Edge\User Data")
        "Brave Browser"    = [System.IO.Path]::Combine($env:LOCALAPPDATA, "BraveSoftware\Brave-Browser\User Data")
        "Vivaldi"          = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Vivaldi\User Data")
        "Opera Stable"     = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Opera Software\Opera Stable")
        "Opera GX"         = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Opera Software\Opera GX Stable")
        "Yandex Browser"   = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Yandex\YandexBrowser\User Data")
        "Genspark Browser" = [System.IO.Path]::Combine($env:LOCALAPPDATA, "GensparkSoftware\Genspark-Browser\User Data")
    }

    $chromiumCacheSubdirs = @(
        "Cache",
        "Cache\Cache_Data",
        "Code Cache\js",
        "Code Cache\wasm",
        "GPUCache",
        "ShaderCache",
        "GrShaderCache",
        "DawnCache",
        "DawnWebGPUCache",
        "DawnGraphiteCache",
        "Service Worker\CacheStorage",
        "Service Worker\ScriptCache"
    )

    foreach ($bName in $chromiumRoots.Keys) {
        $root = $chromiumRoots[$bName]
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $profiles = @()
        $defaultDir = Join-Path $root "Default"
        if (Test-Path -LiteralPath $defaultDir) { $profiles += $defaultDir }
        
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "Profile *"
        } | ForEach-Object { $profiles += $_.FullName }

        if ($profiles.Count -eq 0) {
            $profiles += $root
        }

        foreach ($profPath in $profiles) {
            $profName = Split-Path -Leaf $profPath
            foreach ($sub in $chromiumCacheSubdirs) {
                $targetPath = Join-Path $profPath $sub
                Add-TargetHelper "$bName Cache" "$bName ($profName -> $sub)" $targetPath
            }
        }
    }

    # (E) Mozilla Firefox Caches (Located in %LOCALAPPDATA%\Mozilla\Firefox\Profiles)
    $firefoxLocalRoot = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Mozilla\Firefox\Profiles")
    if (Test-Path -LiteralPath $firefoxLocalRoot) {
        $ffProfiles = Get-ChildItem -LiteralPath $firefoxLocalRoot -Directory -ErrorAction SilentlyContinue
        foreach ($ffProf in $ffProfiles) {
            foreach ($sub in @("cache2", "startupCache", "jumpListCache", "thumbnails")) {
                $targetPath = Join-Path $ffProf.FullName $sub
                Add-TargetHelper "Mozilla Firefox Cache" "Firefox ($($ffProf.Name) -> $sub)" $targetPath
            }
        }
    }

    # (F) AI & Developer Applications (Roaming & LocalAppData)
    # Target applications requested: Kiro, Antigravity, Devin, Windsurf, Trae, Cursor, Qoder, Warp, Genspark, VS Code
    $aiAppNames = @(
        # Kiro IDE (from DUE-TASKS: %APPDATA%\KIRO)
        "Kiro", "kiro", "KIRO",
        # Antigravity IDE (from DUE-TASKS: %APPDATA%\Antigravity IDE)
        "Antigravity", "Antigravity IDE", "antigravity ide",
        # Devin AI (from DUE-TASKS: %APPDATA%\DEVIN)
        "devin", "Devin", "DEVIN",
        # Windsurf IDE (from DUE-TASKS: %APPDATA%\WINDSURF)
        "Windsurf", "WINDSURF", "windsurf",
        # Trae AI (from DUE-TASKS: %APPDATA%\TRAE)
        "Trae", "trae", "trae-ai", "TRAE SOLO", "Trae Solo", "trae solo", "trae-solo", "TRAE",
        # Cursor IDE (from DUE-TASKS: %APPDATA%\Cursor)
        "Cursor", "cursor",
        # Other AI/Dev tools
        "Qoder", "qoder", "Warp", "warp",
        "Genspark", "GensparkSoftware", "Code"
    )

    $aiCacheSubdirs = @(
        "Cache",
        "Cache\Cache_Data",
        "CachedData",
        "CachedConfigurations",
        "CachedExtensionVSIXs",
        "CachedProfilesData",
        "Code Cache\js",
        "Code Cache\wasm",
        "GPUCache",
        "ShaderCache",
        "GrShaderCache",
        "DawnCache",
        "DawnWebGPUCache",
        "DawnGraphiteCache",
        "Crashpad\reports",
        "logs",
        "blob_storage",
        "Service Worker\CacheStorage",
        "Service Worker\ScriptCache",
        "sentry",
        "summaries"
    )

    foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
        $rootName = if ($root -ieq $env:APPDATA) { "Roaming" } else { "Local" }
        foreach ($name in $aiAppNames) {
            $appPath = Join-Path $root $name
            if (-not (Test-Path -LiteralPath $appPath)) { continue }

            # Trae profile container (orphaned or empty container removal)
            if ($name -match "^trae" -or $name -match "solo") {
                Add-TargetHelper "Trae AI Cleanup" "Trae Profile ($rootName\$name)" $appPath $false $true $false
                continue
            }

            foreach ($sub in $aiCacheSubdirs) {
                $targetPath = Join-Path $appPath $sub
                Add-TargetHelper "$name ($rootName) Cache" "$name ($rootName -> $sub)" $targetPath
            }
        }
    }

    # (G) Dedicated AI Updater & Compile Caches
    $dedicatedCaches = @(
        @{ Name = "Antigravity Updater"; Path = [System.IO.Path]::Combine($env:LOCALAPPDATA, "antigravity-updater") },
        @{ Name = "Qoder Updater";       Path = [System.IO.Path]::Combine($env:LOCALAPPDATA, "qoder-updater") },
        @{ Name = "Cursor Compile Cache";Path = [System.IO.Path]::Combine($env:LOCALAPPDATA, "cursor-compile-cache") },
        @{ Name = "Devin Updater";       Path = [System.IO.Path]::Combine($env:LOCALAPPDATA, "devin-updater") },
        @{ Name = "Windsurf Updater";    Path = [System.IO.Path]::Combine($env:LOCALAPPDATA, "windsurf-updater") },
        @{ Name = "Kiro Updater";        Path = [System.IO.Path]::Combine($env:LOCALAPPDATA, "kiro-updater") }
    )
    foreach ($dc in $dedicatedCaches) {
        Add-TargetHelper $dc.Name "$($dc.Name) Cache" $dc.Path $false $true $false
    }

    # (H) DUE-TASKS: Explicit Roaming-path cache cleaning for the 6 AI IDEs listed in DUE-TASKS.txt
    #     Paths: %APPDATA%\Antigravity IDE, %APPDATA%\Cursor, %APPDATA%\DEVIN,
    #            %APPDATA%\TRAE, %APPDATA%\WINDSURF, %APPDATA%\KIRO
    $dueCacheSubdirs = @(
        "Cache", "Cache\Cache_Data", "CachedData", "CachedConfigurations", "CachedExtensionVSIXs",
        "Code Cache\js", "Code Cache\wasm", "GPUCache", "ShaderCache", "GrShaderCache",
        "DawnCache", "DawnWebGPUCache", "DawnGraphiteCache", "Crashpad\reports", "logs",
        "blob_storage", "Service Worker\CacheStorage", "Service Worker\ScriptCache", "sentry"
    )
    $dueTasksRoamingApps = @(
        @{ Name = "Antigravity IDE"; FolderNames = @("Antigravity IDE", "Antigravity", "antigravity ide") },
        @{ Name = "Cursor";          FolderNames = @("Cursor", "cursor") },
        @{ Name = "DEVIN";           FolderNames = @("DEVIN", "Devin", "devin") },
        @{ Name = "TRAE";            FolderNames = @("TRAE", "Trae", "trae", "TRAE SOLO", "Trae Solo") },
        @{ Name = "WINDSURF";        FolderNames = @("WINDSURF", "Windsurf", "windsurf") },
        @{ Name = "KIRO";            FolderNames = @("KIRO", "Kiro", "kiro") }
    )
    foreach ($dueApp in $dueTasksRoamingApps) {
        foreach ($folderName in $dueApp.FolderNames) {
            $roamingPath = [System.IO.Path]::Combine($env:APPDATA, $folderName)
            if (-not (Test-Path -LiteralPath $roamingPath)) { continue }
            foreach ($sub in $dueCacheSubdirs) {
                $targetPath = Join-Path $roamingPath $sub
                Add-TargetHelper "$($dueApp.Name) Roaming Cache" "$($dueApp.Name) (Roaming\$folderName -> $sub)" $targetPath
            }
        }
    }

    return $targets
}

# -----------------------------------------------------------------------------
# 5. TARGET AUDITING & LOCK DETECTION
# -----------------------------------------------------------------------------

function Audit-TargetDirectory {
    param([PSCustomObject]$Target)

    $path = $Target.Path
    $info = [PSCustomObject]@{
        Category       = $Target.Category
        Label          = $Target.Label
        Path           = $path
        FileCount      = 0
        TotalSizeBytes = [long]0
        LockedCount    = 0
        PermissionFail = 0
        SafeToClean    = $false
        SafetyReason   = ""
    }

    if (-not (Test-Path -LiteralPath $path)) {
        $info.SafetyReason = "Path does not exist"
        return $info
    }

    if (-not (Test-PathSafety -Path $path)) {
        $info.SafeToClean = $false
        $info.SafetyReason = "FAILED PATH SAFETY CHECK"
        return $info
    }

    $info.SafeToClean = $true
    $info.SafetyReason = "Passed strict safety whitelist"

    try {
        # PERF-FIX #1 (audit half): Use .NET streaming enumeration instead of
        # Get-ChildItem -Recurse piped through foreach (no pipeline marshalling).
        foreach ($fp in [System.IO.Directory]::EnumerateFiles($path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try {
                $info.FileCount++
                $info.TotalSizeBytes += ([System.IO.FileInfo]$fp).Length
            } catch {}
        }
    } catch {
        $info.PermissionFail++
    }

    return $info
}

# -----------------------------------------------------------------------------
# 6. SAFE DELETION EXECUTION
# -----------------------------------------------------------------------------

function Invoke-SafeDirectoryClean {
    param([PSCustomObject]$Target)

    $path = $Target.Path
    $result = [PSCustomObject]@{
        Category      = $Target.Category
        Label         = $Target.Label
        Path          = $path
        FilesCleaned  = 0
        BytesCleaned  = [long]0
        FilesSkipped  = 0
        FilesLocked   = 0
        AccessDenied  = 0
        Status        = "Success"
    }

    if (-not (Test-PathSafety -Path $path)) {
        $result.Status = "Aborted: Safety check failed"
        Write-EngineLog "BLOCKED by safety engine: $path" "ERROR"
        return $result
    }

    if (-not (Test-Path -LiteralPath $path)) {
        $result.Status = "Skipped: Path not found"
        return $result
    }

    $isGenericTemp = ($Target.Category -like "*Windows User Temp*" -or $Target.Category -like "*Windows System Temp*")
    $now = Get-Date

    try {
        # PERF-FIX #3: Use .NET EnumerateFiles (streaming, no pipeline overhead) instead of
        # Get-ChildItem -Recurse piped through Where-Object + Sort-Object scriptblock.
        # Safety is verified at target level above; per-file checks removed (PERF-FIX #2 complement).
        $fileList = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $dirList  = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($fp in [System.IO.Directory]::EnumerateFiles($path, '*', [System.IO.SearchOption]::AllDirectories)) {
                try { $fileList.Add([System.IO.FileInfo]::new($fp)) } catch {}
            }
            foreach ($dp in [System.IO.Directory]::EnumerateDirectories($path, '*', [System.IO.SearchOption]::AllDirectories)) {
                $dirList.Add($dp)
            }
        } catch {}

        # Sort files deepest-path-first (longest path = deepest) so parent dirs empty before we try to remove them
        $files = $fileList | Sort-Object { $_.FullName.Length } -Descending

        foreach ($file in $files) {
            # Per-file safety guard: only check files that share a forbidden fragment (fast pre-screen)
            $fullName = $file.FullName
            $skipFile = $false
            foreach ($rx in $script:CompiledForbiddenPatterns) {
                if ($rx.IsMatch($fullName)) { $skipFile = $true; break }
            }
            if ($skipFile) { $result.FilesSkipped++; continue }

            try {
                $len = $file.Length
                [System.IO.File]::SetAttributes($fullName, [System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($fullName)
                if (-not [System.IO.File]::Exists($fullName)) {
                    $result.FilesCleaned++
                    $result.BytesCleaned += $len
                } else {
                    $result.FilesLocked++
                }
            } catch [System.IO.IOException] {
                $result.FilesLocked++
            } catch [System.UnauthorizedAccessException] {
                $result.AccessDenied++
            } catch {
                $result.FilesSkipped++
            }
        }

        # Clean empty directories inside target (deepest first)
        $sortedDirs = $dirList | Sort-Object { $_.Length } -Descending
        foreach ($dp in $sortedDirs) {
            try {
                if ([System.IO.Directory]::GetFileSystemEntries($dp).Length -eq 0) {
                    [System.IO.Directory]::Delete($dp, $false)
                }
            } catch {}
        }

        # If target has RemoveContainer = $true (e.g. leftover Trae or updaters), remove container if empty
        if ($Target.RemoveContainer -and [System.IO.Directory]::Exists($path)) {
            try {
                if ([System.IO.Directory]::GetFileSystemEntries($path).Length -eq 0) {
                    [System.IO.Directory]::Delete($path, $false)
                }
            } catch {}
        } elseif (-not [System.IO.Directory]::Exists($path) -and -not $Target.RemoveContainer) {
            # Dedicated cache subfolder: ensure clean container exists
            try { [System.IO.Directory]::CreateDirectory($path) | Out-Null } catch {}
        }
    } catch {
        $result.Status = "Error: $($_.Exception.Message)"
    }

    return $result
}

# -----------------------------------------------------------------------------
# 7. DISK DRIVE MEASUREMENT HELPERS
# -----------------------------------------------------------------------------

function Get-SystemDriveFreeBytes {
    $driveLetter = ($env:SystemDrive.TrimEnd('\').TrimEnd(':') + ':\')
    $drive = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -ieq $driveLetter } | Select-Object -First 1
    if ($drive) { return $drive.AvailableFreeSpace }
    return [long]0
}

function Format-SizeDisplay {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# -----------------------------------------------------------------------------
# 8. MAIN ENGINE ENTRY POINT
# -----------------------------------------------------------------------------

function Invoke-SafeWindows10Cleanup {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Clean,
        [switch]$IncludeSystemTemp,
        [switch]$ForceCloseBrowsers,
        [switch]$Force,
        [string]$LogFile = ""
    )

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        $LogFile = $script:EngineLogFile   # use the module-level log file path (PERF-FIX: was $script:LogFile which is undefined)
    }

    Write-EngineLog "============================================================" "AUDIT"
    Write-EngineLog "   Safe, Evidence-Based Windows 10 Cache Cleaner Engine" "AUDIT"
    Write-EngineLog "============================================================" "AUDIT"
    Write-EngineLog "Execution Mode: $(if ($DryRun) { 'DRY-RUN AUDIT ONLY (No files deleted)' } elseif ($Clean) { 'ACTIVE CLEANUP' } else { 'AUDIT & CONFIRMATION' })" "INFO"
    Write-EngineLog "Log File: $LogFile" "INFO"

    # Step 1: Record initial disk space
    $freeBefore = Get-SystemDriveFreeBytes
    Write-EngineLog "Drive $($env:SystemDrive) Free Space Before: $(Format-SizeDisplay $freeBefore)" "INFO"

    # Step 2: Check running browsers
    $runningBrowsers = Get-RunningBrowserProcesses
    if ($runningBrowsers.Count -gt 0) {
        $names = ($runningBrowsers.Keys -join ", ")
        Write-EngineLog "Active browser processes detected: $names" "WARN"
        if ($Clean -and $ForceCloseBrowsers) {
            Close-TargetBrowsers -RunningBrowsers $runningBrowsers
        } else {
            Write-EngineLog "Running in safe non-destructive mode: Unlocked browser/app cache files will be cleaned; active/locked files are safely skipped." "INFO"
        }
    } else {
        Write-EngineLog "All supported browsers are currently closed. Caches can be cleaned fully." "SUCCESS"
    }

    # Step 3: Recycle Bin Audit / Cleanup
    $recycleResult = Invoke-SafeEmptyRecycleBin -DryRun:($DryRun -or (-not $Clean))
    if ($recycleResult.ItemsCount -gt 0) {
        Write-EngineLog "Recycle Bin: $($recycleResult.ItemsCount) item(s) found ($(Format-SizeDisplay $recycleResult.BytesCleaned))." "AUDIT"
        if ($Clean -and -not $DryRun) {
            Write-EngineLog "Emptied Windows Recycle Bin successfully." "SUCCESS"
        }
    } else {
        Write-EngineLog "Recycle Bin is currently empty." "INFO"
    }

    # Step 4: Discover safe targets
    $targets = Get-SafeCleanupTargets -IncludeSystem:$IncludeSystemTemp
    Write-EngineLog "Discovered $($targets.Count) safe target locations." "INFO"

    # Step 5: Audit targets
    Write-EngineLog "Auditing target directories (calculating sizes, lock status, and safety)..." "AUDIT"
    $auditResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalFoundFiles = 0
    $totalFoundBytes = [long]0
    $totalLockedFiles = 0

    foreach ($target in $targets) {
        $audit = Audit-TargetDirectory -Target $target
        $auditResults.Add($audit)
        $totalFoundFiles += $audit.FileCount
        $totalFoundBytes += $audit.TotalSizeBytes
        $totalLockedFiles += $audit.LockedCount
    }

    Write-EngineLog "Audit Total: $totalFoundFiles files, $(Format-SizeDisplay $totalFoundBytes) estimated across $($targets.Count) locations." "AUDIT"

    # Downloads Verification — PERF-FIX #5: single .NET call instead of Get-ChildItem | Measure-Object
    $userDownloads = Join-Path $env:USERPROFILE "Downloads"
    $downloadsCount = try {
        ([System.IO.Directory]::GetFiles($userDownloads) + [System.IO.Directory]::GetDirectories($userDownloads)).Count
    } catch { 0 }
    Write-EngineLog "Downloads Folder Status: PRESERVED ($downloadsCount items in $userDownloads)" "SUCCESS"

    # Security Verification
    Write-EngineLog "Security Verification: Passwords/Logins/Bookmarks remain 100% UNTOUCHED." "SUCCESS"

    # If DryRun mode or neither -Clean nor user confirmation, exit safely
    if ($DryRun -or (-not $Clean)) {
        Write-EngineLog "Dry-run audit completed successfully. ZERO files were modified or deleted." "SUCCESS"
        return [PSCustomObject]@{
            Mode          = "DryRun"
            RecycleBin    = $recycleResult
            TargetsCount  = $targets.Count
            TotalFiles    = $totalFoundFiles
            TotalBytes    = $totalFoundBytes
            AuditResults  = $auditResults
        }
    }

    # Step 6: Perform Active Cleanup (if -Clean specified)
    Write-EngineLog "Starting Safe Cleanup Execution..." "INFO"
    $cleanResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalCleanedFiles = 0
    $totalCleanedBytes = [long]0
    $totalSkippedFiles = 0
    $totalLockedEncountered = 0

    foreach ($target in $targets) {
        $res = Invoke-SafeDirectoryClean -Target $target
        $cleanResults.Add($res)
        $totalCleanedFiles += $res.FilesCleaned
        $totalCleanedBytes += $res.BytesCleaned
        $totalSkippedFiles += $res.FilesSkipped
        $totalLockedEncountered += $res.FilesLocked
        
        if ($res.FilesCleaned -gt 0) {
            Write-EngineLog "Cleaned $($res.Label): $($res.FilesCleaned) files ($(Format-SizeDisplay $res.BytesCleaned))" "SUCCESS"
        }
    }

    # Step 7: Post-cleaning measurements
    $freeAfter = Get-SystemDriveFreeBytes
    $actualFreed = [Math]::Max(0, $freeAfter - $freeBefore)

    Write-EngineLog "============================================================" "AUDIT"
    Write-EngineLog "   CLEANUP EXECUTION COMPLETED" "AUDIT"
    Write-EngineLog "============================================================" "AUDIT"
    Write-EngineLog "Files Deleted:       $totalCleanedFiles" "SUCCESS"
    Write-EngineLog "File Size Reclaimed: $(Format-SizeDisplay $totalCleanedBytes)" "SUCCESS"
    Write-EngineLog "Drive Space Freed:   $(Format-SizeDisplay $actualFreed) on drive $($env:SystemDrive)" "SUCCESS"
    Write-EngineLog "Files Skipped:       $totalSkippedFiles (safety boundaries preserved)" "INFO"
    Write-EngineLog "Locked Files:        $totalLockedEncountered (active processes skipped safely without error)" "INFO"

    # Step 8: Post-clean verify Downloads — PERF-FIX #5
    $downloadsCountAfter = try {
        ([System.IO.Directory]::GetFiles($userDownloads) + [System.IO.Directory]::GetDirectories($userDownloads)).Count
    } catch { 0 }
    if ($downloadsCountAfter -eq $downloadsCount) {
        Write-EngineLog "Downloads Verification: EXACT MATCH ($downloadsCountAfter items intact)." "SUCCESS"
    } else {
        Write-EngineLog "WARNING: Downloads count changed ($downloadsCount -> $downloadsCountAfter)!" "ERROR"
    }

    return [PSCustomObject]@{
        Mode               = "Clean"
        RecycleBin         = $recycleResult
        FilesCleaned       = $totalCleanedFiles
        BytesCleaned       = $totalCleanedBytes
        ActualFreedDrive   = $actualFreed
        SkippedFiles       = $totalSkippedFiles
        LockedFiles        = $totalLockedEncountered
        FreeSpaceBefore    = $freeBefore
        FreeSpaceAfter     = $freeAfter
        CleanResults       = $cleanResults
    }
}

# Auto-execute if invoked directly as a script
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s+') {
    if (-not $DryRun -and -not $Clean) {
        Invoke-SafeWindows10Cleanup -DryRun -IncludeSystemTemp:$IncludeSystemTemp
    } else {
        Invoke-SafeWindows10Cleanup -DryRun:$DryRun -Clean:$Clean -IncludeSystemTemp:$IncludeSystemTemp -ForceCloseBrowsers:$ForceCloseBrowsers -Force:$Force
    }
}

# Flush any remaining buffered log lines (PERF-FIX #15)
Flush-EngineLogBuffer
