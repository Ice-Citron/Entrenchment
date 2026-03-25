# Workspace Layout Manager

Save and restore your multi-monitor window layouts with a single command. Stop dragging windows back into place every time you switch between project contexts.

## Why?

If you work across multiple monitors and switch between tasks (robotics dev on one setup, exam revision on another), you know the pain of rearranging Finder windows, terminals, browser tabs, and editors every time. This tool snapshots your entire window arrangement and replays it on demand.

## Status

- **macOS** (`layout`): Working, actively used. Has some known issues (see [HANDOFF.md](HANDOFF.md)).
- **Windows** (`layout.ps1`): Written but **untested**. Needs real-world testing on Windows.

## Supported Features

| Feature | macOS | Windows |
|---|---|---|
| Window positions & sizes | ✅ | ✅ |
| Multi-monitor support | ✅ | ✅ |
| Finder / Explorer folders | ✅ (with tabs) | ✅ |
| iTerm2 working directories | ✅ (per-tab cwd) | — |
| Terminal / PowerShell positions | — | ✅ |
| Brave / Chrome tab URLs | ✅ | planned |
| Brave tab groups (metadata) | ✅ (save only) | planned |
| VS Code workspace paths | ✅ | ✅ |
| Preview / PDF documents | ✅ | — |
| Microsoft Remote Desktop | ✅ (window positions) | N/A |
| Generic app windows | ✅ | ✅ |

## Quick Start

### macOS

```bash
git clone https://github.com/Ice-Citron/Entrenchment.git
cd Entrenchment
bash install.sh

# Save your current layout
layout save isaac-sim-3screen --desc "Isaac Sim dev on 3-screen setup"

# Restore it later
layout restore isaac-sim-3screen
```

### Windows

```powershell
git clone https://github.com/Ice-Citron/Entrenchment.git
cd Entrenchment\windows
.\install.bat

# Save your current layout
layout save rdp-dev -Description "VS Code + PowerShell + Browser"

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

- **macOS**: Uses JXA (JavaScript for Automation) via `osascript` to query each app's scripting interface for window positions, open folders, tab URLs, and working directories. A Python assembler merges per-app captures into a single layout JSON.

- **Windows**: Uses Win32 API (`EnumWindows`, `GetWindowRect`, `MoveWindow`) via PowerShell `Add-Type` C# interop. Reads Explorer folder paths via `Shell.Application` COM and VS Code state from internal storage files.

Layouts are stored as JSON in `~/.config/workspace-layouts/` — human-readable and easy to back up.

## Requirements

- **macOS**: Accessibility permissions for Terminal/iTerm (System Settings > Privacy & Security > Accessibility). Python 3 (ships with macOS).
- **Windows**: PowerShell 5.1+ (pre-installed on Windows 10/11). Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` if scripts are blocked.

## Notes

- Layouts are tied to your monitor arrangement. A layout saved on 3 screens will warn if restored on a different count.
- Save separate layouts per setup (e.g. `isaac-sim-3screen` for the library, `isaac-sim-4screen` for Sherfield).
- Brave/Chrome tab groups are captured as metadata but can't be programmatically recreated on restore (Chromium API limitation). Individual tabs are fully restored.
- For RDP windows: capture from macOS gets window positions only. Run the Windows script inside the RDP session to capture/restore the remote desktop's internal layout.

## License

MIT
