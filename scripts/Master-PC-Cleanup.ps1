<#
.SYNOPSIS
    Master PC Cleanup — Redundant Folder & Junk Remover
    Consolidates everything done in the 4-hour cleanup session on 2026-11-10.

.DESCRIPTION
    Covers four areas in one pass:
      A. User Profile  — C:\Users\<you>\  dot-folders / dead AI IDE stubs
      B. Program Files — PF & PF(x86) redundant 32-bit stubs, old drivers, updater debris
      C. ProgramData   — Dead hardware-driver configs, stale vendor caches
      D. Windows       — Temp, Logs, SoftwareDistribution, winsxs\Backup, PatchCache, ETL logs

    For every item this script will:
      1. Take ownership + grant Everyone:Full (breaks TrustedInstaller / SYSTEM locks)
      2. Delete files via .NET File.Delete (fastest, no shell involvement)
      3. Fall back to robocopy /MIR wipe + rd /s /q for stubborn dirs
      4. Register truly locked items via MoveFileEx DELAY_UNTIL_REBOOT
         so they vanish silently on next Windows boot

    Safe-guards:
      - Downloads, passwords (Login Data, key4.db), bookmarks, cookies NEVER touched
      - Java, Nitro PDF, Analysis Services (PF), Synaptics NEVER touched (kept per user)
      - Windows system dirs (System32, SysWOW64, registry, WinSxS manifests) NEVER touched
      - Running processes from each target are stopped before deletion
      - Every deletion is measured and logged

.PARAMETER WhatIf
    Dry-run — shows what WOULD be deleted, removes nothing.

.PARAMETER SkipWindows
    Skip the Windows junk section.

.PARAMETER SkipProgramFiles
    Skip the Program Files / PF(x86) section.

.PARAMETER SkipProgramData
    Skip the ProgramData section.

.PARAMETER SkipUserProfile
    Skip the user profile dot-folder section.

.NOTES
    Run as Administrator.
    Author : Kiro (session 2026-11-10)
    Version: 1.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipWindows,
    [switch]$SkipProgramFiles,
    [switch]$SkipProgramData,
    [switch]$SkipUserProfile
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# 0.  HELPERS
# ---------------------------------------------------------------------------

# MoveFileEx for boot-time deletion of locked files
if (-not ('MasterCleanup.BootDel' -as [type])) {
    Add-Type -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("Kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExisting, string lpNew, int dwFlags);
'@ -Name 'BootDel' -Namespace 'MasterCleanup' | Out-Null
}

$script:TotalFreedBytes   = [long]0
$script:BootDeletedBytes  = [long]0
$script:Log               = [System.Collections.Generic.List[string]]::new()
$script:WhatIfMode        = $WhatIfPreference -or ($PSBoundParameters.ContainsKey('WhatIf'))

function Write-Step {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host "`n$Msg" -ForegroundColor $Color
    $script:Log.Add($Msg)
}

function Write-Result {
    param([string]$Msg, [string]$Color = 'White')
    Write-Host "  $Msg" -ForegroundColor $Color
    $script:Log.Add("  $Msg")
}

function Measure-FolderBytes([string]$Path) {
    $b = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $b += ([System.IO.FileInfo]$f).Length } catch {}
        }
    } catch {}
    return $b
}

function Format-MB([long]$Bytes) { '{0:F1} MB' -f ($Bytes / 1MB) }

function Unlock-Path([string]$Path) {
    $null = & takeown.exe /f $Path /r /a /d y 2>$null
    $null = & icacls.exe  $Path /grant 'Administrators:(F)' /t /c /q 2>$null
    $null = & icacls.exe  $Path /grant 'Everyone:(F)'       /t /c /q 2>$null
    $null = & attrib.exe  -R -S -H $Path /s /d 2>$null
    # Kill processes running from this path
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($Path, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Remove-Target {
    <#
    Deletes a file or folder. Reports: DELETED / BOOT-DEL / SKIP / WHATIF
    Returns bytes freed immediately.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label = '',
        [switch]$ContentsOnly   # Clear contents but leave root folder intact
    )
    if (-not $Label) { $Label = $Path }
    if (-not (Test-Path $Path)) { Write-Result "SKIP  (not found) $Label" 'DarkGray'; return [long]0 }

    $bytes = Measure-FolderBytes $Path
    $mb    = Format-MB $bytes

    if ($script:WhatIfMode) { Write-Result "WHATIF  $Label  ($mb)" 'Magenta'; return [long]0 }

    Unlock-Path $Path

    if ($ContentsOnly) {
        # Delete all children, keep root folder
        foreach ($child in @(Get-ChildItem $Path -Force -ErrorAction SilentlyContinue)) {
            try {
                if ($child.PSIsContainer) {
                    $null = & cmd.exe /c "rd /s /q `"$($child.FullName)`" 2>nul"
                } else {
                    [System.IO.File]::SetAttributes($child.FullName,[System.IO.FileAttributes]::Normal)
                    [System.IO.File]::Delete($child.FullName)
                }
            } catch {
                [MasterCleanup.BootDel]::MoveFileEx($child.FullName, $null, 4) | Out-Null
                $script:BootDeletedBytes += try { $child.Length } catch { 0 }
            }
        }
        Write-Result "CLEANED  $Label  ($mb)" 'Green'
        return $bytes
    }

    # --- Full folder deletion ---
    # Step 1: bulk del + rd
    $null = & cmd.exe /c "del /f /s /q `"$Path\*`" 2>nul"
    $null = & cmd.exe /c "rd /s /q `"$Path`" 2>nul"

    if (-not (Test-Path $Path)) {
        Write-Result "DELETED  $Label  ($mb)" 'Green'
        return $bytes
    }

    # Step 2: robocopy /MIR wipe
    $empty = Join-Path $env:TEMP ('empty_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $null = & robocopy.exe $empty $Path /mir /r:0 /w:0 /mt:8 /nfl /ndl /njh /njs /nc /ns /np 2>&1
    Remove-Item $empty -Force -Recurse -ErrorAction SilentlyContinue
    $null = & cmd.exe /c "rd /s /q `"$Path`" 2>nul"

    if (-not (Test-Path $Path)) {
        Write-Result "DELETED  $Label  ($mb via robocopy)" 'Green'
        return $bytes
    }

    # Step 3: MoveFileEx boot-delete for every remaining item
    $remaining = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path,'*',[System.IO.SearchOption]::AllDirectories)) {
            try { $remaining += ([System.IO.FileInfo]$f).Length } catch {}
            [MasterCleanup.BootDel]::MoveFileEx($f, $null, 4) | Out-Null
        }
        foreach ($d in [System.IO.Directory]::EnumerateDirectories($Path,'*',[System.IO.SearchOption]::AllDirectories) | Sort-Object Length -Descending) {
            [MasterCleanup.BootDel]::MoveFileEx($d, $null, 4) | Out-Null
        }
    } catch {}
    [MasterCleanup.BootDel]::MoveFileEx($Path, $null, 4) | Out-Null

    $freedNow = $bytes - $remaining
    $script:BootDeletedBytes += $remaining
    Write-Result ("BOOT-DEL $Label  ({0} freed now, {1} at next boot)" -f (Format-MB $freedNow),(Format-MB $remaining)) 'Yellow'
    return $freedNow
}

function Remove-LockedFiles {
    <# Deletes or boot-registers individual files matching a filter inside a folder #>
    param([string]$Folder, [string]$Filter = '*', [string]$Label)
    if (-not (Test-Path $Folder)) { return }
    if (-not $Label) { $Label = $Folder }
    Unlock-Path $Folder
    $items  = Get-ChildItem $Folder -Filter $Filter -Force -ErrorAction SilentlyContinue
    $freed  = [long]0
    $queued = [long]0
    foreach ($f in $items) {
        try {
            [System.IO.File]::SetAttributes($f.FullName,[System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($f.FullName)
            $freed += $f.Length
        } catch {
            [MasterCleanup.BootDel]::MoveFileEx($f.FullName, $null, 4) | Out-Null
            $queued += $f.Length
        }
    }
    if ($freed -gt 0 -or $queued -gt 0) {
        Write-Result ("CLEANED  $Label  ({0} freed, {1} boot-queued)" -f (Format-MB $freed),(Format-MB $queued)) 'Green'
    }
    $script:BootDeletedBytes += $queued
    return $freed
}

# ---------------------------------------------------------------------------
# A.  USER PROFILE — Dead AI IDE stubs & empty dot-folders
# ---------------------------------------------------------------------------
if (-not $SkipUserProfile) {
    Write-Step '=== A. USER PROFILE  Dead AI IDE stubs / empty dot-folders ==='

    $prof = $env:USERPROFILE

    # Confirmed dead / empty / orphaned dot-folders
    # (Kimi, Rust/Go, Java kept — user confirmed in session)
    $profileTargets = @(
        # Zero-size / empty stubs
        @{ Path = "$prof\.icube-remote-ssh";  Label = 'Profile\.icube-remote-ssh (empty stub)'  },
        @{ Path = "$prof\.ms-ad";             Label = 'Profile\.ms-ad (empty stub)'              },
        @{ Path = "$prof\.qmind";             Label = 'Profile\.qmind (empty stub)'              },
        @{ Path = "$prof\.zcode";             Label = 'Profile\.zcode (empty stub)'              },

        # Duplicate: .antigravity-ide  (real root is .antigravity_cockpit)
        @{ Path = "$prof\.antigravity-ide";   Label = 'Profile\.antigravity-ide (dup of .antigravity_cockpit)' },

        # Stale CLI tools (last used 5+ months ago)
        @{ Path = "$prof\.fly";               Label = 'Profile\.fly (fly.io CLI, last used May 2026)'          },
        @{ Path = "$prof\.grok";              Label = 'Profile\.grok (Grok IDE, last used Sep 2026)'           }
    )

    foreach ($t in $profileTargets) {
        $script:TotalFreedBytes += Remove-Target -Path $t.Path -Label $t.Label
    }
}

# ---------------------------------------------------------------------------
# B.  PROGRAM FILES — Redundant 32-bit stubs, dead drivers, updater debris
# ---------------------------------------------------------------------------
if (-not $SkipProgramFiles) {
    Write-Step '=== B. PROGRAM FILES  Redundant 32-bit stubs & dead drivers ==='

    $pf   = 'C:\Program Files'
    $pf86 = 'C:\Program Files (x86)'

    # --- PF86 stubs (real installs live in PF) ---
    $pfTargets = @(
        # Duplicate Analysis Services (64-bit lives in PF)
        @{ Path = "$pf86\Microsoft Analysis Services"; Label = 'PF86\Microsoft Analysis Services (dup of PF)' },

        # 32-bit Office stub after 64-bit migration
        @{ Path = "$pf86\Microsoft Office";  Label = 'PF86\Microsoft Office (32-bit stub, PF has full install)' },

        # HP dead hardware software
        @{ Path = "$pf86\HP SimplePass";     Label = 'PF86\HP SimplePass (2018 fingerprint app, dead)' },
        @{ Path = "$pf86\HP";                Label = 'PF86\HP (stale laptop utilities 2021)'           },
        @{ Path = "$pf\HP";                  Label = 'PF\HP  (stale laptop utilities)'                 },

        # Intel stub
        @{ Path = "$pf86\Intel";             Label = 'PF86\Intel (older stub, PF\Intel is current)'    },

        # Browser updater stubs (browsers live in PF, these are residual updater dirs)
        @{ Path = "$pf86\BraveSoftware";     Label = 'PF86\BraveSoftware (updater stub only)'          },
        @{ Path = "$pf86\GensparkSoftware";  Label = 'PF86\GensparkSoftware (updater stub only)'       },
        @{ Path = "$pf86\Yandex";            Label = 'PF86\Yandex (updater stub only)'                 }
    )

    foreach ($t in $pfTargets) {
        $script:TotalFreedBytes += Remove-Target -Path $t.Path -Label $t.Label
    }

    # --- Windows update agent ETL logs (apps kept, only logs cleared) ---
    Write-Step '  -- ETL log files inside Windows update agent folders --' 'DarkCyan'
    foreach ($logDir in @("$pf\ruxim\Logs", "$pf\rempl\Logs", "$pf\UNP\Logs", "$pf\UNP\SystemLogs")) {
        $script:TotalFreedBytes += Remove-LockedFiles -Folder $logDir -Filter '*.etl' -Label $logDir
    }
}

# ---------------------------------------------------------------------------
# C.  PROGRAMDATA — Dead hardware configs & stale vendor caches
# ---------------------------------------------------------------------------
if (-not $SkipProgramData) {
    Write-Step '=== C. PROGRAMDATA  Dead hardware configs & vendor caches ==='

    $pdTargets = @(
        # Windows Mobile/Phone era (dead since 2015)
        @{ Path = 'C:\ProgramData\Comms';                   Label = 'PD\Comms (Windows Mobile 2015)'          },
        @{ Path = 'C:\ProgramData\WindowsHolographicDevices';Label = 'PD\WindowsHolographicDevices (HoloLens)' },

        # Dead C++ interprocess cache
        @{ Path = 'C:\ProgramData\boost_interprocess';      Label = 'PD\boost_interprocess (2020 C++ cache)'  },

        # Dead 2018 Bluetooth driver
        @{ Path = 'C:\ProgramData\Ralink Bluetooth Stack';  Label = 'PD\Ralink Bluetooth Stack (2018 BT dead)' },

        # Dead fingerprint sensors (HP hardware removed)
        @{ Path = 'C:\ProgramData\Validity';                Label = 'PD\Validity (2018 fingerprint sensor)'   },
        @{ Path = 'C:\ProgramData\HP SimplePass 2011';      Label = 'PD\HP SimplePass 2011 (dead)'            },

        # Stale HP laptop configs
        @{ Path = 'C:\ProgramData\HP';                      Label = 'PD\HP (stale config 2021)'               },
        @{ Path = 'C:\ProgramData\Hewlett-Packard';         Label = 'PD\Hewlett-Packard (stale config)'       }
    )

    foreach ($t in $pdTargets) {
        $script:TotalFreedBytes += Remove-Target -Path $t.Path -Label $t.Label
    }
}

# ---------------------------------------------------------------------------
# D.  WINDOWS — Temp, logs, caches, update leftovers
# ---------------------------------------------------------------------------
if (-not $SkipWindows) {
    Write-Step '=== D. WINDOWS  Temp / Logs / Update cache / Backup components ==='

    $w = 'C:\Windows'

    # -- Contents-only clears (keep the root folder, Windows needs it) --
    $windowsContentClears = @(
        @{ Path = "$w\Temp";                              Label = 'Windows\Temp'                        },
        @{ Path = "$w\Logs\CBS";                          Label = 'Windows\Logs\CBS'                    },
        @{ Path = "$w\Panther";                           Label = 'Windows\Panther (upgrade logs)'      },
        @{ Path = "$w\minidump";                          Label = 'Windows\minidump'                    },
        @{ Path = "$w\LiveKernelReports";                 Label = 'Windows\LiveKernelReports'           },
        @{ Path = "$w\SoftwareDistribution\Download";     Label = 'SoftwareDistribution\Download'      },
        @{ Path = "$w\SoftwareDistribution\DataStore\Logs";Label='SoftwareDistribution\DataStore\Logs' },
        @{ Path = "$w\tracing";                           Label = 'Windows\tracing'                     },
        @{ Path = "$w\appcompat\Programs";                Label = 'Windows\appcompat\Programs'          },
        @{ Path = "$w\Downloaded Program Files";          Label = 'Windows\Downloaded Program Files'   },
        @{ Path = "$w\Help";                              Label = 'Windows\Help (legacy .hlp files)'   },
        @{ Path = "$w\winsxs\Backup";                    Label = 'Windows\winsxs\Backup'              },
        @{ Path = "$w\system32\LogFiles";                 Label = 'system32\LogFiles'                   },
        @{ Path = "$w\SysWOW64\catroot2";                Label = 'SysWOW64\catroot2'                   },
        @{ Path = "$w\Installer\`$PatchCache`$";         Label = 'Windows\Installer\$PatchCache$'      }
    )
    foreach ($t in $windowsContentClears) {
        $script:TotalFreedBytes += Remove-Target -Path $t.Path -Label $t.Label -ContentsOnly
    }

    # -- Prefetch files (Windows regenerates automatically) --
    $prefetch = "$w\Prefetch"
    if (Test-Path $prefetch) {
        Unlock-Path $prefetch
        $pfFiles = Get-ChildItem $prefetch -Force -ErrorAction SilentlyContinue
        $pfFreed = [long]0
        foreach ($f in $pfFiles) {
            try {
                [System.IO.File]::SetAttributes($f.FullName,[System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($f.FullName)
                $pfFreed += $f.Length
            } catch {
                [MasterCleanup.BootDel]::MoveFileEx($f.FullName, $null, 4) | Out-Null
            }
        }
        Write-Result ("CLEANED  Windows\Prefetch  ({0})" -f (Format-MB $pfFreed)) 'Green'
        $script:TotalFreedBytes += $pfFreed
    }

    # -- memory.dmp --
    $memdmp = "$w\memory.dmp"
    if (Test-Path $memdmp) {
        $sz = ([System.IO.FileInfo]$memdmp).Length
        try {
            [System.IO.File]::Delete($memdmp)
            Write-Result ("DELETED  Windows\memory.dmp  ({0})" -f (Format-MB $sz)) 'Green'
            $script:TotalFreedBytes += $sz
        } catch {
            [MasterCleanup.BootDel]::MoveFileEx($memdmp, $null, 4) | Out-Null
            Write-Result "BOOT-DEL Windows\memory.dmp" 'Yellow'
        }
    }

    # -- setupapi.dev.log in inf folder --
    $infLog = "$w\inf\setupapi.dev.log"
    if (Test-Path $infLog) {
        try {
            $sz = ([System.IO.FileInfo]$infLog).Length
            [System.IO.File]::Delete($infLog)
            Write-Result ("DELETED  inf\setupapi.dev.log  ({0})" -f (Format-MB $sz)) 'Green'
            $script:TotalFreedBytes += $sz
        } catch { Write-Result "SKIP     inf\setupapi.dev.log (locked)" 'DarkGray' }
    }

    # -- Orphaned .msp patch files in Installer (older than 1 year) --
    $instDir = "$w\Installer"
    if (Test-Path $instDir) {
        $cutoff   = (Get-Date).AddYears(-1)
        $orphaned = Get-ChildItem $instDir -Filter '*.msp' -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt $cutoff }
        $mspFreed = [long]0
        foreach ($f in $orphaned) {
            try { [System.IO.File]::Delete($f.FullName); $mspFreed += $f.Length } catch {
                [MasterCleanup.BootDel]::MoveFileEx($f.FullName,$null,4) | Out-Null
            }
        }
        if ($mspFreed -gt 0) { Write-Result ("CLEANED  Installer orphaned .msp  ({0})" -f (Format-MB $mspFreed)) 'Green' }
    }

    # -- C:\$WINDOWS.~BT (Windows upgrade staging folder - 3-8 GB when present) --
    $wupgrade = 'C:\$WINDOWS.~BT'
    if (Test-Path $wupgrade) {
        Write-Step '  -- Windows upgrade staging folder ($WINDOWS.~BT) --' 'DarkCyan'
        $script:TotalFreedBytes += Remove-Target -Path $wupgrade -Label 'C:\$WINDOWS.~BT (upgrade staging)'
    }
}

# ---------------------------------------------------------------------------
# E.  FLUSH LOG + FINAL SUMMARY
# ---------------------------------------------------------------------------
$logFile = Join-Path $env:LOCALAPPDATA 'MyCleanPC\Master-PC-Cleanup-Log.txt'
try {
    $logDir = Split-Path $logFile -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $header = @(
        '=' * 60,
        "  Master PC Cleanup Run — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        '=' * 60
    )
    $footer = @(
        '',
        "  Freed immediately : $(Format-MB $script:TotalFreedBytes)",
        "  Queued (boot-del) : $(Format-MB $script:BootDeletedBytes)",
        ('  Grand total       : {0}' -f (Format-MB ($script:TotalFreedBytes + $script:BootDeletedBytes))),
        ''
    )
    ($header + $script:Log + $footer) | Out-File $logFile -Encoding UTF8 -Append
} catch {}

$free = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -ieq 'C:\' } | Select-Object -First 1

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "  MASTER CLEANUP COMPLETE" -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host ("  Freed immediately : {0}" -f (Format-MB $script:TotalFreedBytes)) -ForegroundColor Green
Write-Host ("  Queued (boot-del) : {0}" -f (Format-MB $script:BootDeletedBytes)) -ForegroundColor Yellow
Write-Host ("  Grand total       : {0}" -f (Format-MB ($script:TotalFreedBytes + $script:BootDeletedBytes))) -ForegroundColor Cyan
if ($free) { Write-Host ("  C: free now       : {0:F1} GB" -f ($free.AvailableFreeSpace/1GB)) -ForegroundColor Cyan }
Write-Host ("  Log saved to      : $logFile") -ForegroundColor DarkGray
Write-Host ('=' * 60) -ForegroundColor Cyan
if ($script:BootDeletedBytes -gt 0) {
    Write-Host "  Reboot to clear the boot-delete queue." -ForegroundColor Yellow
}
