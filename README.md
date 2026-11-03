# My Clean PC

[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)

Silent, prompt-free Windows cache, cookie, and AI tool cleaner — passwords, autofill, bookmarks, and Downloads are **never** touched.

---

## 📥 How to Download and Install

### Step 1: Download the Repository

Choose **Method A** or **Method B**:

#### Method A — Using Git (Recommended)
Open PowerShell or Command Prompt and run:
```powershell
git clone https://github.com/CRAJKUMARSINGH/my-clean-pc.git
cd my-clean-pc
```

#### Method B — Direct ZIP Download (Without Git)
1. Click the green **Code** button on GitHub and select **Download ZIP** (or download from the repository page).
2. Extract the ZIP archive to a folder on your computer (e.g., `E:\my-clean-pc` or `C:\my-clean-pc`).
3. Open PowerShell or Command Prompt in that extracted folder.

---

### Step 2: Choose Installation Option

**⚠️ IMPORTANT: Must be run with Administrator Privileges**

You can install **Both Cleaners**, the **7-Minute Cleaner ONLY**, the **24-Minute Cleaner ONLY**, or the **Weekly Cleaner ONLY**:

| Desired Setup | 1-Click Batch File | PowerShell Command (Run as Admin) |
|---|---|---|
| **Install BOTH Cleaners** | Double-click `Launch-Install-Both.bat` | `powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task Both` |
| **Install 7-Min Cleaner ONLY** | Double-click `Launch-Install-7Min-Only.bat` | `powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task 7Min` |
| **Install 24-Min Cleaner ONLY** | Double-click `Launch-Install-24Min-Only.bat` | `powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task 24Min` |
| **Install Weekly Cleaner ONLY** | Double-click `Launch-Install-Weekly-Only.bat` | `powershell -ExecutionPolicy Bypass -File Install-Cleaners-Admin.ps1 -Task Weekly` |

---

## ⚙️ Installed Cleaner Sets

- **`MyCleanPC-7Min`**
  - **Interval**: Repeats automatically **every 7 minutes** when PC is ON.
  - **Behavior**: Runs completely hidden, cleaning caches & temp files without closing any running browsers or AI tools.
- **`MyCleanPC-24Min`**
  - **Interval**: Repeats automatically **every 24 minutes** when PC is ON.
  - **Behavior**: Runs completely hidden without closing any running browsers or AI tools.
- **`MyCleanPC-Weekly`**
  - **Interval**: Repeats automatically **every Week (Monday at 9:00 AM)** when PC is ON.
  - **Behavior**: Runs background cleanup using the exact same shared engine.

---

## 📋 Cleaner Log Files

| Log File | Script / Source | Description |
|---|---|---|
| **`ai_cleaner_log.txt`** | `scripts/ai-cache-cleaner.ps1` | Logs AI tools & browser cache cleaning runs (runs on 7-min / 24-min schedule). |
| **`temp_cleaner_log.txt`** | `scripts/clean-pc-core.ps1` | Logs deep temporary files, AppData junk sweeps, Prefetch, Recycle Bin, and Disk Cleanup operations. |
| **`cleanup_log.txt`** | `scripts/cleanup_task.ps1` | Logs weekly scheduled full cleanup operations. |

*Note: Log files are automatically generated and saved in `%LOCALAPPDATA%\MyCleanPC\` (when installed) as well as the script folder.*

---

## 📂 Repository Script Breakdown & Functions

| File / Script Path | Type | Function & Description |
|---|---|---|
| **[`Install-Cleaners-Admin.ps1`](Install-Cleaners-Admin.ps1)** | PowerShell Universal Installer | **Universal Installer**: Auto-elevates to Administrator and registers `Both` tasks (7Min + Weekly), `7Min` task only, `24Min` task only, or `Weekly` task only based on `-Task` parameter. |
| **[`Install-Both-Cleaners-Admin.ps1`](Install-Both-Cleaners-Admin.ps1)** | PowerShell Wrapper | **Both Task Installer Wrapper**: Backward-compatible script executing `Install-Cleaners-Admin.ps1 -Task Both`. |
| **[`Launch-Install-Both.bat`](Launch-Install-Both.bat)** | Batch Launcher | **1-Click Launcher (Both)**: Triggers UAC elevation and installs both `MyCleanPC-7Min` and `MyCleanPC-Weekly`. |
| **[`Launch-Install-7Min-Only.bat`](Launch-Install-7Min-Only.bat)** | Batch Launcher | **1-Click Launcher (7Min Only)**: Triggers UAC elevation and installs only `MyCleanPC-7Min`. |
| **[`Launch-Install-24Min-Only.bat`](Launch-Install-24Min-Only.bat)** | Batch Launcher | **1-Click Launcher (24Min Only)**: Triggers UAC elevation and installs only `MyCleanPC-24Min`. |
| **[`Launch-Install-Weekly-Only.bat`](Launch-Install-Weekly-Only.bat)** | Batch Launcher | **1-Click Launcher (Weekly Only)**: Triggers UAC elevation and installs only `MyCleanPC-Weekly`. |
| File / Script Path | Type | Function & Description |
|---|---|---|
| **[`scripts/Safe-Cleanup-Engine.ps1`](scripts/Safe-Cleanup-Engine.ps1)** | Core Safety Engine | **Evidence-Based Safe Engine**: Implements strict path whitelist validation, dry-run auditing, running process detection, byte-accurate space accounting, and non-destructive cache cleaning. |
| **[`scripts/ai-cache-cleaner.ps1`](scripts/ai-cache-cleaner.ps1)** | Cleaner Wrapper | **Interval Cleaner**: Invokes `Safe-Cleanup-Engine.ps1` safely for user-session background tasks without touching cookies, passwords, history, or roaming configs. |
| **[`scripts/clean-pc-core.ps1`](scripts/clean-pc-core.ps1)** | Shared Core Utility | **Shared Core Engine**: Manages deep temporary file cleanup, sanitized CleanMgr presets (with Downloads and rollback protection), and DNS cache flushing. |
| **[`scripts/cleanup_task.ps1`](scripts/cleanup_task.ps1)** | Task Runner | **Weekly Task Runner**: Invoked by the weekly scheduled task to execute full safe cleaning. |
| **[`tests/Test-PathSafety.ps1`](tests/Test-PathSafety.ps1)** | Automated Test Suite | **Path Safety & Integrity Tests**: Verifies rejection of protected directories (Downloads, credentials, history, system roots) and approval of valid cache paths. |
| **[`uninstall.ps1`](uninstall.ps1)** | PowerShell Uninstaller | **Uninstaller Script**: Unregisters all `MyCleanPC` scheduled tasks and removes installation directories from `%LOCALAPPDATA%\MyCleanPC`. |
| **[`uninstall.bat`](uninstall.bat)** | Batch Uninstaller | **1-Click Batch Uninstaller**: Launches `uninstall.ps1` with Administrator privileges. |

---

## 🧹 What It Cleans

| Target Area | Scope & Details |
|---|---|
| **Modern Browser Caches** | Chrome (all profiles), Edge, Firefox, Brave, Vivaldi, Opera<br>• `Cache`, `Code Cache` (js/wasm), `GPUCache`, `ShaderCache`, `DawnCache`<br>• Firefox `cache2`, `startupCache`, `jumpListCache`, `thumbnails` |
| **AI Tools & Developer Caches** | Cursor, Windsurf, VS Code, Devin, Trae, Antigravity IDE<br>• Local `%LOCALAPPDATA%` cache subdirectories only |
| **Windows Temporary Files** | `%TEMP%`, `%LOCALAPPDATA%\Temp` (preserving files modified in the last 24h)<br>• `C:\Windows\Temp` (unlocked temp files with Admin rights) |
| **Windows System Caches** | Thumbnail Cache, Icon Cache, safe CleanMgr preset (sanitized) |

---

## 🛡️ What It Never Touches (Safeguards)

- **Downloads Folder** — `%USERPROFILE%\Downloads` is 100% PRESERVED with strict path barriers.
- **Passwords & Vaults** — `Login Data`, `key4.db`, `logins.json`, credential stores are NEVER touched.
- **Bookmarks & Favorites** — `Bookmarks`, `places.sqlite`, bookmarks HTML are NEVER touched.
- **Cookies & Sessions** — `Cookies`, `Network\Cookies`, `cookies.sqlite` are NEVER touched.
- **Browsing History** — `History`, `Visited Links`, `places.sqlite` are NEVER touched.
- **Autofill / Form Data** — `Web Data`, `formhistory.sqlite`, `Autofill` are NEVER touched.
- **Roaming Profiles & Settings** — `%APPDATA%\Cursor`, `%APPDATA%\Windsurf`, `%APPDATA%\Antigravity IDE` configurations and chats are NEVER touched.
- **Windows Prefetch & Event Logs** — Preserved intact to prevent performance degradation and maintain system diagnostic logs.
- **Registry MachineGuid** — Strictly off-limits to preserve Windows activation and licensing integrity.
- **Windows Update Rollback Files** — `Previous Installations` (`Windows.old`) and restore points are NEVER deleted.

---

## 🗑️ How to Uninstall

To remove scheduled tasks and delete installed files:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

*Or double-click `uninstall.bat` as Administrator.*

---

## 🗒️ Session Log

> Auto-updated every 12 minutes. Full log in [`creat.md`](creat.md).

### 2026-11-03

| Time | Action |
|------|--------|
| 10:00 | Read `DUE-TASKS.txt` — identified 6 AI IDE Roaming paths to clean (Antigravity IDE, Cursor, DEVIN, TRAE, WINDSURF, KIRO) |
| 10:05 | Updated `Safe-Cleanup-Engine.ps1` + `clean-pc-core.ps1` to cover all 6 paths; committed `9715629`; pushed to `origin/main`; installed to `%LOCALAPPDATA%\MyCleanPC` |
| 10:15 | Created `creat.md` session log; set up 12-min auto-update hook (`session-log-12min`); standing order: `creat.md` + `README.md §Session Log` stay in sync |

---

## 📄 License

MIT — see [LICENSE](LICENSE).
