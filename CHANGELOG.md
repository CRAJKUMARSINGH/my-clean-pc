# Changelog

All notable changes to **My-Clean-PC** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **On-Demand Startup Guard** (`scripts/startup-guard.ps1`) - forces AnyDesk and the
  Bentley stack to start only when the user starts them, never at boot or logon.
  - Neutralises all four Windows autostart vectors: services (`StartMode` -> `Manual`),
    `HKLM`/`HKCU` `Run` + `RunOnce` values, Startup-folder shortcuts, and scheduled tasks.
  - Matching is by executable name and full path, so vendor renames don't break it.
  - JSON restore point at `%ProgramData%\My-Clean-PC\startup-guard.json`;
    `-Action Enable` restores the original state exactly.
  - `-Action Status` reports without changing anything; `-WhatIf` supported.
  - Managed executables:
    - `AnyDesk.exe`
    - `Bentley.Connect.Client.exe`
    - `Bentley.Licensing.Service.exe`
    - `Bentley.Structural.PropertyCatalog.Server.exe`
- **On-demand launcher** (`scripts/start-on-demand.ps1`) - brings up the required
  service and launches the app only if it isn't already running.
  - Scopes: `All`, `AnyDesk`, `Bentley`, `ConnectionClient`, `LicenseService`, `SPC`.
- **Re-assert task installer** (`scripts/create-startup-guard-task.ps1`) - scheduled
  task (weekly by default, `Daily`/`AtLogOn` optional) that re-applies the policy
  after vendor updates silently restore autostart entries.
- `Invoke-StartupGuard` helper hook in `scripts/clean-pc-core.ps1`.

### Changed

- `README.md` - new "On-Demand Startup Guard" section and updated repository tree.
- `Install-Cleaners-Admin.ps1` & `uninstall.ps1` - bundled startup-guard components and automated task management.

### Notes

- Bentley Licensing Service is set to `Manual` (not `Disabled`) by default so Bentley
  products can still trigger it on demand for licence checkout. Use `-Hard` to force
  `Disabled`.
