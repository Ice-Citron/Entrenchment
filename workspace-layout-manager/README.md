# Workspace Layout Manager

Save and restore your multi-monitor window layouts with a single command. Built for switching between project contexts without manually dragging windows around every time.

## Why?

If you work across multiple monitors and switch between different tasks (e.g. coding a robotics project vs. revising for exams), you know the pain of rearranging all your Finder windows, terminals, browser tabs, and editors every time you switch. This tool snapshots your entire window arrangement and replays it on demand.

## Supported Platforms

| Feature | macOS (`layout`) | Windows (`layout.ps1`) |
|---|---|---|
| Window positions & sizes | ✅ | ✅ |
| Multi-monitor support | ✅ | ✅ |
| Finder / Explorer folders | ✅ (with tabs) | ✅ |
| iTerm2 / Terminal dirs | ✅ (per-tab cwd) | ✅ (PowerShell, cmd, Windows Terminal) |
| Brave / Chrome tabs & URLs | ✅ | ✅ |
| Brave tab groups (metadata) | ✅ (best-effort) | ✅ (best-effort) |
| VS Code workspace paths | ✅ (reads internal state) | ✅ (reads internal state) |
| Preview / PDF viewers | ✅ | — |
| Microsoft Remote Desktop | ✅ (window positions) | N/A |
| Generic app windows | ✅ | ✅ |

## Quick Start

### macOS

```bash
cd workspace-layout-manager
bash install.sh

# Save your current layout
layout save isaac-sim-3screen --desc "Isaac Sim dev on library 3-screen setup"

# Switch contexts instantly
layout restore comp-arch-study
```

### Windows

```powershell
cd workspace-layout-manager\windows
.\install.bat

# Save your current layout
layout save rdp-dev -Description "VS Code + PowerShell + Browser on RDP"

# Restore it later
layout restore rdp-dev
```

## Commands

| Command | Description |
|---|---|
| `layout save <name>` | Snapshot all open windows, positions, paths, and tabs |
| `layout restore <name>` | Reopen everything and put it back where it was |
| `layout list` | Show all saved layouts |
| `layout info <name>` | Show detailed breakdown of a layout |
| `layout delete <name>` | Remove a saved layout |
| `layout screens` | Show current display configuration |

## How It Works

- **macOS**: Uses JXA (JavaScript for Automation) and AppleScript to query each app's scripting interface for window positions, open folders, tab URLs, and working directories. Saves as JSON to `~/.config/workspace-layouts/`.

- **Windows**: Uses Win32 API (`EnumWindows`, `GetWindowRect`, `MoveWindow`) via PowerShell Add-Type to capture and reposition windows. Reads Explorer folder paths via `Shell.Application` COM object and VS Code state from its internal storage files.

Both platforms store layouts in `~/.config/workspace-layouts/` as JSON, so they're human-readable and easy to back up.

## Requirements

- **macOS**: Accessibility permissions for iTerm/Terminal (System Settings → Privacy & Security → Accessibility)
- **Windows**: PowerShell 5.1+ (pre-installed on Windows 10/11). Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` if scripts are blocked.

## Notes

- Layouts are tied to your monitor arrangement. A layout saved on 3 screens will warn you if restored on a different number of screens.
- Save separate layouts for different monitor setups (e.g. `isaac-sim-3screen` for the library, `isaac-sim-4screen` for Sherfield).
- RDP internal state (what's running inside the remote session) can't be captured from macOS — use the Windows script inside the RDP session for that.
- Brave/Chrome tab groups are captured as metadata but can't be programmatically recreated on restore due to Chromium API limitations. Individual tabs are fully restored.

## License

MIT
