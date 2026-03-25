# Workspace Layout Manager — Handoff Document

## What This Project Is

A CLI tool that **saves and restores multi-monitor window layouts** on macOS and Windows. The primary user (Shi Hao) is an Imperial College London student who constantly switches between different work contexts — NVIDIA Isaac Sim development (Project-Automaton), course revision (40005 Computer Architecture, calculus, assembly, Kotlin, etc.) — across multi-monitor setups (3 screens at the library, 4 screens at Sherfield). Every context switch means manually dragging windows back into place, which is the problem this tool solves.

The idea: run `layout save isaac-sim-3screen`, arrange your windows, and later run `layout restore isaac-sim-3screen` to snap everything back.

---

## Current State (as of 2026-03-25)

### What Works
- **Save**: Captures Finder, iTerm2, Brave Browser, VS Code, Preview window positions across multiple monitors
- **VS Code capture**: Now uses CoreGraphics (CGWindowListCopyWindowInfo via pyobjc) to get window bounds + reads VS Code's internal `storage.json` for workspace paths. Handles Remote SSH workspaces (`vscode-remote://` URIs). Falls back to System Events if Quartz unavailable.
- **Interactive mode**: Running `layout` with no args enters a REPL with numbered layouts, commands, and number-based selection
- **List/Info/Delete/Screens**: All working
- **Brave save**: Captures all tabs + URLs across multiple windows
- **Syntax**: All known parse errors fixed (the `doesn't` apostrophe bug, dead code removed, line 459 overwrite bug fixed)

### What Does NOT Work (restore bugs)

**Tested 2026-03-25 — restore is unreliable. These are the priority bugs:**

1. **Brave Browser restore opens wrong tabs / wrong window**: User had 4 Brave windows with tab groups. After closing one window (containing a "994" tab group with 4-5 tabs) and restoring, a new window opened but with a random AWS page instead of the correct tab group tabs. **Root cause**: The restore logic uses `brave.windows[0]` (frontmost) which shifts as windows are created. Tab-to-window assignment gets scrambled when some windows already exist. Also, Brave tab groups cannot be programmatically recreated (Chromium limitation) — individual tabs restore but lose their group membership.

2. **Preview restores in wrong position / not fullscreen**: User had a fullscreen Preview window showing `ros2_graph`. After closing and restoring, it opened but NOT fullscreen and in the wrong position. **Root cause**: The save captures `bounds` and `boundsRaw` but fullscreen state is not captured. macOS fullscreen is a separate window mode (not just large bounds). The restore uses `set bounds` which only works for normal windows, not fullscreen ones.

3. **Windows App (Microsoft Remote Desktop) does not restore at all**: After closing the RDP session and restoring, the Windows App didn't reopen. **Root cause**: The script captures RDP window positions but the restore likely fails because: (a) the app name changed from "Microsoft Remote Desktop" to "Windows App" at some point and the script may not handle both, (b) RDP connections require authentication/session state that can't be scripted via AppleScript.

4. **VS Code reopened unnecessarily**: VS Code windows that were already open got reopened/duplicated during restore. **Root cause**: Restore doesn't check if an app's windows are already open before creating new ones. Needs a `--clean` flag or smart diffing.

5. **iTerm window running the restore gets killed**: The terminal window executing `layout restore` gets repositioned/killed by the restore process since it's restoring iTerm windows. **Root cause**: The restore recreates/repositions all iTerm windows including the one running the restore. Fix: detect and skip the current terminal window.

---

## Architecture

### File Structure
```
Entrenchment/
├── .gitignore
├── LICENSE             # MIT
├── README.md
├── HANDOFF.md          # This file
├── layout              # macOS bash script (main tool)
├── install.sh          # macOS installer — copies to ~/.local/bin
└── windows/
    ├── layout.ps1      # Windows PowerShell — UNTESTED
    ├── layout.bat      # Batch launcher
    └── install.bat     # Windows installer
```

### Save Flow (macOS)
1. Creates temp directory for intermediate JSON files
2. Captures each app category separately:
   - **Finder**: JXA via `Application("Finder")` — direct scripting, no special permissions
   - **iTerm2**: JXA via `Application("iTerm2")` — direct scripting
   - **Brave**: JXA via `Application("Brave Browser")` — direct scripting for tabs/URLs
   - **VS Code**: Python with `Quartz.CGWindowListCopyWindowInfo` for bounds + `storage.json` for workspace paths. Falls back to System Events (needs Accessibility permission)
   - **Preview**: JXA via `Application("Preview")` — direct scripting
   - **RDP**: System Events (tries "Microsoft Remote Desktop" and "Windows App")
   - **Other apps**: System Events enumeration
3. Python assembler reads all temp files and writes final JSON to `~/.config/workspace-layouts/<name>.json`

### Restore Flow (macOS)
1. Reads saved JSON
2. Single Python heredoc handles all restore logic
3. For each app: launches it, uses `osascript` subprocess calls to position windows

### Permission Model
| App | Capture Method | Permission Needed |
|-----|---------------|-------------------|
| Finder, iTerm, Brave, Preview | Direct JXA (`Application("AppName")`) | Automation: iTerm → each app |
| VS Code | CoreGraphics (CGWindowListCopyWindowInfo) | None (bounds only). Screen Recording for window titles |
| RDP, Other apps | System Events | Accessibility for osascript/iTerm |

### Key Design Constraints
- **Single bash file, no package manager dependencies**: Just bash + osascript + python3 (+ pyobjc for VS Code via conda)
- **Temp files for JSON assembly**: Never inject JSON into Python heredocs via shell variables (quotes break it)
- **Best-effort capture**: Failed captures for optional apps should not crash the save
- **JXA over AppleScript**: JXA has native JSON support

---

## Known Bugs & Issues (Full List)

### Critical (Restore is Broken)

1. **Brave multi-window restore assigns tabs to wrong windows**: When restoring multiple Brave windows, the `windows[0]` (frontmost) index shifts as new windows are created. Tabs end up in the wrong window. Need to track windows by ID or use a more robust targeting strategy.

2. **Brave tab groups not recreatable**: Chromium has no API to programmatically create tab groups. We save group metadata (`braveTabGroups`) but can't use it during restore. Tabs lose their group membership.

3. **No fullscreen state capture/restore**: Preview (and any other app) in fullscreen can't be restored to fullscreen. `set bounds` only works for normal window mode. Need to detect fullscreen state during save and use `keystroke "f" using {control down, command down}` or similar during restore.

4. **RDP/Windows App doesn't restore**: App name may have changed. Also RDP sessions can't be reconnected via AppleScript — would need to use `open rdp://` URI or similar.

5. **Restore duplicates already-open windows**: If an app is already running with windows open, restore adds more on top instead of repositioning existing ones. Need either a `--clean` flag to close existing windows first, or smart matching to reuse existing windows.

6. **Restore kills the terminal running the command**: The iTerm window executing `layout restore` gets caught in the iTerm restore logic. Need to detect the current terminal PID/window and skip it.

### Medium

7. **`set -euo pipefail` can crash the whole save**: If any optional osascript call fails (e.g., Preview not running), the script exits. Each capture section should trap errors gracefully.

8. **iTerm bounds format inconsistency**: iTerm's `bounds()` returns `{x, y, right, bottom}` not `{x, y, width, height}`. The `boundsRaw` vs `bounds` handling during save/restore may have incorrect coordinate math.

9. **Finder tabs partially captured**: Only the active tab's folder path is captured. Other tabs' paths aren't accessible via the Finder scripting API.

10. **VS Code workspace matching is heuristic**: When CGWindowList returns windows without titles (no Screen Recording permission), we match windows to workspaces by count/order, which can be wrong if VS Code has utility windows.

### Low

11. **Windows script completely untested**: `layout.ps1` was written but never run on a real Windows machine.

12. **No `layout diff` command**: Can't compare current state to a saved layout.

13. **No `layout auto` mode**: Can't auto-detect screen count and restore the matching layout.

14. **No Safari support**: Some users might want Safari tab capture.

---

## What Needs To Be Done

### Priority 1: Fix Restore (it's the core feature)

- [ ] **Fix Brave multi-window restore**: After creating each window, immediately set its bounds before creating the next. Or use a different strategy: close all Brave windows first, then create them one by one with the correct tabs.
- [ ] **Add fullscreen detection to save and fullscreen restoration**: Check `AXFullScreen` attribute during save, use keyboard shortcut to toggle fullscreen during restore.
- [ ] **Fix restore duplication**: Add `--clean` flag that closes existing windows before restoring. Or implement smart matching (compare existing windows to saved state, reposition instead of recreate).
- [ ] **Skip the terminal running the restore**: Detect current iTerm window by PID or tty and exclude it from restore.
- [ ] **Fix RDP restore**: Check both "Microsoft Remote Desktop" and "Windows App" process names. For reconnecting, try `open rdp://` or just position existing windows.
- [ ] **Handle `set -euo pipefail` gracefully**: Wrap each app's capture in a subshell or use `|| true` for optional captures.

### Priority 2: Improve Save Accuracy

- [ ] **Grant Screen Recording permission** so CGWindowList returns VS Code window titles (better workspace matching)
- [ ] **Fix iTerm bounds coordinate math**: Verify and document the coordinate format
- [ ] **Capture all Finder tab paths** (not just active tab)

### Priority 3: Test Windows Script

- [ ] Run `layout.ps1` on a Windows machine via RDP
- [ ] Fix C# compilation/runtime errors
- [ ] Verify Explorer path matching, VS Code workspace detection, MoveWindow

### Priority 4: Features

- [ ] `--clean` flag for restore
- [ ] `layout diff <name>` command
- [ ] `layout auto` mode (detect screen count → auto-restore matching layout)

---

## End Goal

The tool should work like this:

1. **At the library (3 screens)**: Run `layout save isaac-sim-3screen`. All windows — VS Code with Project-Automaton, multiple Brave windows with research tabs grouped by topic, iTerm with dev sessions, Finder with project folders, Preview with lecture PDFs, RDP to StarForge-PC — are captured.

2. **Switch to revision mode**: Run `layout restore comp-arch-study`. All Isaac Sim windows close, and the revision layout opens: VS Code with course materials, Brave with lecture slides and reference docs, iTerm with assignment directories, Preview with past papers.

3. **Move to Sherfield (4 screens)**: Run `layout save comp-arch-4screen` to capture the 4-screen arrangement. Later, `layout restore comp-arch-4screen` puts everything back.

4. **On Windows (via RDP)**: Same workflow inside the RDP session using `layout.ps1`.

The key is **reliability** — restore must put windows back exactly where they were, handle edge cases (apps already open, fullscreen, missing apps), and not destroy the user's current state.

---

## GitHub

- Repo: `https://github.com/Ice-Citron/Entrenchment`
- Remote: `origin` pointing to above
- Branch: `main`
- Last push: 2026-03-25 (repo restructured, files at root)
