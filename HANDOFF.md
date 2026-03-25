# Workspace Layout Manager — Handoff Document

## What This Project Is

A CLI tool that **saves and restores multi-monitor window layouts** on macOS and Windows. The primary user (Shi Hao) is an Imperial College London student who constantly switches between different work contexts — NVIDIA Isaac Sim development (Project-Automaton), course revision (40005 Computer Architecture, calculus, assembly, Kotlin, etc.) — across multi-monitor setups (3 screens at the library, 4 screens at Sherfield). Every context switch means manually dragging windows back into place, which is the problem this tool solves.

The idea: run `layout save isaac-sim-3screen`, arrange your windows, and later run `layout restore isaac-sim-3screen` to snap everything back.

---

## Current State of the Code

### File Structure

```
workspace-layout-manager/
├── layout              # macOS bash script (main tool) — MOSTLY WORKING, has bugs
├── install.sh          # macOS installer — copies to ~/.local/bin, adds to PATH
├── README.md           # Documentation
├── push-to-github.sh   # Helper script to push to Ice-Citron/Entrenchment on GitHub
├── HANDOFF.md          # This file
└── windows/
    ├── layout.ps1      # Windows PowerShell script — UNTESTED, written but not run yet
    ├── layout.bat      # Windows batch launcher (calls layout.ps1)
    └── install.bat     # Windows installer
```

### GitHub Repo

- Repo: `https://github.com/Ice-Citron/Entrenchment` (public, MIT license)
- Currently only has `.gitignore`, `LICENSE`, and a stub `README.md` on `main`
- The workspace-layout-manager code has NOT been pushed yet
- The user started setting up git locally at `~/Black_Projects/Entrenchment` but didn't finish

### Where the files live on disk

- **macOS source**: `/Users/administrator/Black_Projects/Entrenchment/workspace-layout-manager/`
- **Layouts are saved to**: `~/.config/workspace-layouts/<name>.json`
- **Install location**: `~/.local/bin/layout`

---

## macOS Script (`layout`) — Detailed Technical Notes

### Architecture

The script is a single bash file that dispatches on subcommands: `save`, `restore`, `list`, `info`, `delete`, `screens`.

**Save flow:**
1. Creates a temp directory for intermediate JSON files (to avoid shell quoting issues)
2. Runs separate JXA (JavaScript for Automation) `osascript` calls to capture each app category
3. Each capture writes JSON to a temp file (e.g., `$tmp_dir/finder.json`)
4. A final Python script reads all temp files and assembles the full layout JSON
5. Saves to `~/.config/workspace-layouts/<name>.json`

**Restore flow:**
1. Reads the saved JSON
2. A single large Python heredoc handles all restore logic
3. For each app category, it launches the app and uses `osascript` subprocess calls to position windows

### What's captured per app

| App | What's saved | How |
|-----|-------------|-----|
| **Finder** | Window positions, folder path of active tab, tab count + tab names via System Events UI inspection | JXA: `Application("Finder").finderWindows()` + System Events `tabGroups` |
| **iTerm2** | Window positions + bounds, per-tab working directory (via `lsof` on the tty) | JXA: `Application("iTerm2")` scripting API |
| **Brave Browser** | Window positions + bounds, all tab URLs + titles, active tab index, tab group metadata from Preferences file | JXA: `Application("Brave Browser")` + Python reading `~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Preferences` |
| **VS Code** | Window positions, workspace name from title bar, enriched with actual folder path from VS Code's `storage.json` and `workspaceStorage/` | System Events for positions + Python reading `~/Library/Application Support/Code/storage.json` and `~/Library/Application Support/Code/User/workspaceStorage/*/workspace.json` |
| **Preview** | Window positions, document file path | JXA: `Application("Preview")` |
| **Microsoft Remote Desktop** | Window positions, window title (connection name) | System Events (tries both "Microsoft Remote Desktop" and "Windows App" process names) |
| **Other apps** | Window positions for any visible non-system app | System Events: enumerates all `backgroundOnly: false` processes, skips known system processes |

### Known Bugs & Issues

1. **JSON parsing crash on save (FIXED but verify)**: The original version injected captured JSON into Python via `'''$variable'''` triple-quote strings. Any single quotes in window titles or file paths broke it. Fixed by writing each capture to temp files instead. The user confirmed the original bug; the fix has been applied but may not have been re-tested.

2. **VS Code enrichment has dead code**: Lines ~390-411 in the `layout` script contain two Python heredocs (`VSCENRICH` and `VSCENRICH2`) that don't actually do anything useful — they were intermediate attempts. The actual working enrichment is the `ENRICH_PY` heredoc on line ~414. The dead code should be removed.

3. **Line 459 overwrites enriched data**: After the enrichment logic carefully writes `vscode_enriched.json` and copies it to `vscode.json`, line 459 does `echo "$vscode_windows" > "$tmp_dir/vscode.json"` which **overwrites the enriched version with the raw version**. This line should be deleted.

4. **Brave tab groups are metadata-only**: We read tab group names/colors from the Preferences file, but there's no way to know which tab belongs to which group via AppleScript. On restore, tabs reopen but aren't re-grouped. This is a Chromium API limitation. The `braveTabGroups` field is saved in the layout JSON but not used during restore.

5. **Finder tabs are partially captured**: We detect tab count and tab names via System Events UI elements, but we only get the **active tab's folder path**. The other tabs' paths aren't accessible via the Finder scripting API. On restore, only one tab (the active one) gets its correct path.

6. **iTerm bounds format inconsistency**: iTerm's `bounds()` returns `{x, y, width, height}` where width/height are actually `right` and `bottom` coordinates (not width/height). The save code tries to handle this with `boundsRaw` vs computed `bounds`, but the restore code's handling of this is fragile. Need to verify the coordinate math is correct.

7. **Restore doesn't close existing windows first** (except Finder): If you have windows already open when you restore, you'll get duplicates on top of the restored ones. Should probably add an option like `--clean` to close existing windows before restoring.

8. **`set -euo pipefail` may cause silent failures**: If any osascript call fails (e.g., an app isn't running), the whole script exits. The `set -e` is fine for the main flow but may need more careful error handling around optional captures (e.g., Preview might not be open).

### Layout JSON Schema

```json
{
  "name": "isaac-sim-3screen",
  "description": "Isaac Sim dev on library 3-screen setup",
  "savedAt": "2026-03-25T13:45:00.000000",
  "screenCount": 3,
  "screens": [
    {
      "index": 0,
      "x": 0, "y": 0,
      "width": 1440, "height": 900,
      "visibleX": 0, "visibleY": 25,
      "visibleWidth": 1440, "visibleHeight": 850
    }
  ],
  "windows": {
    "finder": [
      {
        "app": "Finder",
        "name": "Documents",
        "path": "/Users/administrator/Documents",
        "tabs": [{"path": "/Users/administrator/Documents", "name": "Documents", "tabCount": 3, "tabNames": ["Documents", "Downloads", "Desktop"]}],
        "bounds": {"x": 0, "y": 23, "width": 800, "height": 600}
      }
    ],
    "iterm": [
      {
        "app": "iTerm2",
        "name": "window title",
        "bounds": {"x": 0, "y": 0, "width": 800, "height": 400},
        "boundsRaw": {"x": 0, "y": 0, "width": 800, "height": 400},
        "tabs": [
          {
            "name": "tab name",
            "sessions": [
              {"name": "session", "profileName": "Default", "cwd": "/Users/administrator/Projects/isaac-sim"}
            ]
          }
        ]
      }
    ],
    "brave": [
      {
        "app": "Brave Browser",
        "name": "window name",
        "bounds": {"x": 0, "y": 0, "width": 1200, "height": 800},
        "boundsRaw": {"x": 0, "y": 0, "width": 1200, "height": 800},
        "tabs": [
          {"title": "Google", "url": "https://google.com", "index": 0}
        ],
        "activeTabIndex": 1
      }
    ],
    "vscode": [
      {
        "app": "Visual Studio Code",
        "name": "main.py — Project-Automaton — Visual Studio Code",
        "workspace": "Project-Automaton",
        "workspacePath": "/Users/administrator/Projects/Project-Automaton",
        "bounds": {"x": 100, "y": 50, "width": 1000, "height": 700}
      }
    ],
    "preview": [
      {
        "app": "Preview",
        "name": "lecture-notes.pdf",
        "path": "/Users/administrator/Documents/40005/lecture-notes.pdf",
        "bounds": {"x": 0, "y": 0, "width": 600, "height": 800},
        "boundsRaw": {"x": 0, "y": 0, "width": 600, "height": 800}
      }
    ],
    "rdp": [
      {
        "app": "Microsoft Remote Desktop",
        "name": "StarForge-PC",
        "bounds": {"x": 1440, "y": 0, "width": 1920, "height": 1080}
      }
    ],
    "other": [
      {
        "app": "Some App",
        "name": "window title",
        "bounds": {"x": 0, "y": 0, "width": 500, "height": 400}
      }
    ]
  },
  "vscodeRecentWorkspaces": ["/Users/administrator/Projects/Project-Automaton", "..."],
  "braveTabGroups": [{"id": "abc123", "title": "Research", "color": 1}]
}
```

---

## Windows Script (`layout.ps1`) — Detailed Technical Notes

### Architecture

PowerShell script with `Add-Type` inline C# for Win32 API access. Same subcommand pattern as macOS: `save`, `restore`, `list`, `info`, `delete`, `screens`.

**Key technical approach:**
- Uses `EnumWindows` + `GetWindowRect` + `GetWindowThreadProcessId` via P/Invoke to enumerate all visible windows
- Uses `Shell.Application` COM object to get Explorer folder paths (matched to windows by HWND)
- Reads VS Code workspace paths from `%APPDATA%\Code\storage.json` and `%APPDATA%\Code\User\workspaceStorage\`
- Reads Brave tab group metadata from `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Default\Preferences`
- Uses `MoveWindow` to reposition windows on restore

### What's captured

| App | What's saved |
|-----|-------------|
| **Explorer** | Window positions, folder paths (via Shell.Application COM) |
| **Brave/Chrome/Edge** | Window positions (tab URLs NOT captured yet — see TODO) |
| **VS Code** | Window positions, workspace name from title, actual folder path from internal state |
| **PowerShell/cmd/Terminal** | Window positions, process name |
| **Other apps** | Window positions, process name, executable path |

### Status: COMPLETELY UNTESTED

This script was written but has never been run. It will almost certainly have bugs. The C# interop code compiles fine in theory but needs real testing on Windows. The user's RDP machines would be the test environment.

### Known Gaps vs macOS Script

1. **Browser tabs not captured via scripting**: Unlike macOS where AppleScript can enumerate Brave tabs, on Windows there's no equivalent COM/API to get browser tab URLs. Would need to either:
   - Read from Brave's Session file (`%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Default\Sessions\`) — binary format, very fragile
   - Use Chrome DevTools Protocol (start Brave with `--remote-debugging-port=9222`) — more reliable but requires browser restart
   - Use a browser extension that exposes tab data

2. **Terminal working directories not captured**: The script captures terminal window positions but not which directory each PowerShell/cmd instance is `cd`'d into. Could potentially use `Get-CimInstance Win32_Process` to get the command line and infer the working directory.

3. **No equivalent of macOS Accessibility API**: Windows has UI Automation but it's more complex. The current approach (Win32 EnumWindows) gets positions but can't read internal app state the way macOS System Events can.

---

## What Needs To Be Done

### Priority 1: Fix macOS bugs

- [ ] Remove dead code (the two useless Python heredocs `VSCENRICH` and `VSCENRICH2` around lines 390-411)
- [ ] Delete line 459 that overwrites enriched VS Code data with raw data
- [ ] Verify the JSON parsing fix actually works (the temp-file approach replacing the triple-quote injection)
- [ ] Handle `set -euo pipefail` gracefully — apps that aren't running shouldn't crash the whole save
- [ ] Test and fix iTerm bounds coordinate math
- [ ] Test save + restore end-to-end on the user's actual multi-monitor setup

### Priority 2: Test and fix Windows script

- [ ] Run `layout.ps1` on a Windows machine (user has RDP access)
- [ ] Fix any C# compilation or runtime errors
- [ ] Verify Explorer path matching works
- [ ] Verify VS Code workspace detection works
- [ ] Test window repositioning with `MoveWindow`

### Priority 3: Feature improvements

- [ ] Add `--clean` flag to restore that closes existing windows first
- [ ] Capture browser tabs on Windows (Chrome DevTools Protocol or session file parsing)
- [ ] Capture terminal working directories on Windows
- [ ] Capture ALL Finder tab paths on macOS (not just the active tab)
- [ ] Add support for Safari (some users might use it)
- [ ] Consider adding a `layout diff <name>` command to see what changed
- [ ] Consider adding a `layout auto` mode that detects screen count and auto-restores the right layout

### Priority 4: Push to GitHub

- [ ] Init git repo at `~/Black_Projects/Entrenchment`
- [ ] Add `.gitignore` (include `.DS_Store`, `*.json` in the layouts config dir, etc.)
- [ ] Push to `https://github.com/Ice-Citron/Entrenchment.git` under `workspace-layout-manager/`
- [ ] Update root README

---

## User Context

- **Machine**: MacBook Pro (hostname: StarForge-MacBook-Pro), username: `administrator`
- **Shell**: zsh (with conda base environment active)
- **Key apps**: iTerm2, Brave Browser, VS Code, Finder, Preview, Microsoft Remote Desktop
- **Monitor setups**: 3 screens at Imperial College library, 4 screens at Sherfield building
- **Common contexts to save**:
  - `isaac-sim-3screen` / `isaac-sim-4screen` — NVIDIA Isaac Sim / Project-Automaton development
  - `comp-arch-study` — Module 40005 Computer Architecture revision
  - Various other courses: calculus, assembly, Kotlin
- **RDP**: User connects to Windows machines via Microsoft Remote Desktop. The Windows `layout.ps1` is meant to run INSIDE the RDP session to capture/restore the remote desktop's window layout.
- **GitHub**: Username `Ice-Citron`

---

## Key Design Decisions Made

1. **Single bash script, no dependencies**: The macOS tool is one file with no npm/pip/brew dependencies — just bash + osascript + python3 (which ships with macOS).

2. **JSON storage**: Layouts are human-readable JSON files in `~/.config/workspace-layouts/`. Easy to inspect, edit, back up, or sync across machines.

3. **Temp files for JSON assembly**: After hitting a bug where shell variable interpolation broke JSON parsing (quotes in window titles), we switched to writing each capture to a temp file and having Python read from files. This is the correct approach — do NOT go back to injecting JSON into heredocs.

4. **JXA over AppleScript**: Most capture code uses JavaScript for Automation (JXA) rather than AppleScript because JXA has native JSON support and is easier to work with programmatically.

5. **Best-effort capture**: The tool captures what it can and silently skips what it can't. A failed Preview capture shouldn't prevent Finder and iTerm from being saved.

6. **Cross-platform parity**: Both scripts save to the same `~/.config/workspace-layouts/` directory with compatible JSON schemas. A layout saved on macOS won't restore on Windows (different apps/coordinates), but the tooling is consistent.
