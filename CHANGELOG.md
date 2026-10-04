# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2026-10-04

### Changed
- **Local configuration file**: personal DNS servers, adapter name and the local DNS label now load from `%USERPROFILE%\.switchdns.config.json`, which lives outside the repository. Built-in defaults are public resolvers (Cloudflare and Quad9).

## [2.0.0] - 2026-01-02

### Added
- **Context Menu Integration**: New `Install-ContextMenu.ps1` and `Uninstall-ContextMenu.ps1` scripts to add a "SwitchDNS" option to the Windows desktop context menu.
- **Dynamic Context Menu Label**: The context menu option now dynamically updates to show the current DNS state (e.g., "Actual: Quad9" or "Actual: DHCP").
- **Smart Adapter Detection**: `SwitchDNS.ps1` now automatically detects the active network adapter with internet access (using Default Gateway logic), removing the need for hardcoded adapter names.
- **Headless Mode**: Added logic to `SwitchDNS.ps1` to handle DNS toggling without user interaction when called from the context menu, using system tray notifications ("Toast") for feedback.
- **Backup Logic**: The system now backs up the previous DNS configuration before applying changes, allowing for reliable restoration.

### Changed
- **Refactoring**: Completely refactored `SwitchDNS.ps1` for better modularity and readability.
- **Validation**: Replaced regex-based IP validation with robust .NET `[System.Net.IPAddress]::TryParse`.
- **Encoding**: Enforced UTF-8 encoding for all file operations to ensure compatibility with special characters.
- **Configuration**: moved global configuration (IPs, Backup paths) to the top of the script for easier customization.

### Fixed
- Fixed issues with hardcoded "Ethernet" adapter name not working on all machines.
