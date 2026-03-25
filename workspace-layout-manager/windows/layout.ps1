<#
.SYNOPSIS
    Workspace Layout Manager for Windows
    Save and restore window layouts across your desktop(s).

.DESCRIPTION
    Captures positions and state of: Explorer windows, PowerShell/Terminal windows,
    Brave/Chrome/Edge browser windows (with tabs), VS Code windows (with workspace paths),
    and any other visible application windows.

.USAGE
    .\layout.ps1 save <name> [-Description "..."]
    .\layout.ps1 restore <name>
    .\layout.ps1 list
    .\layout.ps1 info <name>
    .\layout.ps1 delete <name>
    .\layout.ps1 screens
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("save", "restore", "list", "info", "delete", "screens", "help")]
    [string]$Command = "help",

    [Parameter(Position=1)]
    [string]$Name,

    [string]$Description = ""
)

# ============================================================================
# Configuration
# ============================================================================
$LayoutDir = Join-Path $env:USERPROFILE ".config\workspace-layouts"
if (-not (Test-Path $LayoutDir)) {
    New-Item -ItemType Directory -Path $LayoutDir -Force | Out-Null
}

# ============================================================================
# Win32 API for window enumeration
# ============================================================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
using System.Diagnostics;

public class WindowHelper {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern IntPtr GetShellWindow();

    public const int GWL_STYLE = -16;
    public const int GWL_EXSTYLE = -20;
    public const long WS_VISIBLE = 0x10000000L;
    public const long WS_CAPTION = 0x00C00000L;
    public const long WS_EX_TOOLWINDOW = 0x00000080L;
    public const long WS_EX_APPWINDOW = 0x00040000L;
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static List<WindowInfo> GetAllWindows() {
        var windows = new List<WindowInfo>();
        IntPtr shellWindow = GetShellWindow();

        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            if (hWnd == shellWindow) return true;
            if (!IsWindowVisible(hWnd)) return true;

            int length = GetWindowTextLength(hWnd);
            if (length == 0) return true;

            // Check window styles
            long style = GetWindowLong(hWnd, GWL_STYLE);
            long exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);

            // Skip tool windows without app window style
            if ((exStyle & WS_EX_TOOLWINDOW) != 0 && (exStyle & WS_EX_APPWINDOW) == 0)
                return true;

            StringBuilder builder = new StringBuilder(length + 1);
            GetWindowText(hWnd, builder, builder.Capacity);

            RECT rect;
            GetWindowRect(hWnd, out rect);

            // Skip minimized/offscreen windows with zero or negative size
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0) return true;

            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);

            string processName = "";
            string processPath = "";
            try {
                var proc = Process.GetProcessById((int)processId);
                processName = proc.ProcessName;
                try { processPath = proc.MainModule.FileName; } catch {}
            } catch {}

            windows.Add(new WindowInfo {
                Handle = hWnd,
                Title = builder.ToString(),
                ProcessName = processName,
                ProcessPath = processPath,
                ProcessId = processId,
                X = rect.Left,
                Y = rect.Top,
                Width = width,
                Height = height
            });

            return true;
        }, IntPtr.Zero);

        return windows;
    }
}

public class WindowInfo {
    public IntPtr Handle { get; set; }
    public string Title { get; set; }
    public string ProcessName { get; set; }
    public string ProcessPath { get; set; }
    public uint ProcessId { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
}
"@ -ErrorAction SilentlyContinue

# ============================================================================
# Helper functions
# ============================================================================

function Get-ExplorerPaths {
    <# Get folder paths from all open Explorer windows #>
    $paths = @()
    try {
        $shell = New-Object -ComObject Shell.Application
        $windows = $shell.Windows()
        foreach ($window in $windows) {
            try {
                $path = $window.Document.Folder.Self.Path
                $hwnd = $window.HWND
                $paths += @{
                    path = $path
                    hwnd = $hwnd
                    locationURL = $window.LocationURL
                }
            } catch {}
        }
    } catch {}
    return $paths
}

function Get-BraveTabs {
    <# Read tabs from Brave Browser session/preferences #>
    param([string]$BrowserName = "Brave-Browser")

    $tabs = @()
    $profilePaths = @(
        "$env:LOCALAPPDATA\BraveSoftware\$BrowserName\Default"
        "$env:LOCALAPPDATA\BraveSoftware\$BrowserName\Profile 1"
        "$env:LOCALAPPDATA\Google\Chrome\Default"
        "$env:LOCALAPPDATA\Google\Chrome\Profile 1"
    )

    foreach ($profilePath in $profilePaths) {
        $prefsFile = Join-Path $profilePath "Preferences"
        if (Test-Path $prefsFile) {
            try {
                $prefs = Get-Content $prefsFile -Raw | ConvertFrom-Json
                # Tab groups
                $groups = @{}
                if ($prefs.tab_group_metadata -and $prefs.tab_group_metadata.groups) {
                    $prefs.tab_group_metadata.groups.PSObject.Properties | ForEach-Object {
                        $groups[$_.Name] = @{
                            title = $_.Value.title
                            color = $_.Value.color
                        }
                    }
                }
                return @{ groups = $groups; profilePath = $profilePath }
            } catch {}
        }
    }
    return @{ groups = @{}; profilePath = "" }
}

function Get-VSCodeWorkspaces {
    <# Get VS Code open workspace/folder paths #>
    $workspaces = @()

    # Check VS Code storage.json for recently opened windows
    $storagePaths = @(
        "$env:APPDATA\Code\storage.json",
        "$env:APPDATA\Code - Insiders\storage.json"
    )

    foreach ($storagePath in $storagePaths) {
        if (Test-Path $storagePath) {
            try {
                $data = Get-Content $storagePath -Raw | ConvertFrom-Json

                # openedWindows has current window state
                if ($data.openedWindows) {
                    foreach ($win in $data.openedWindows) {
                        if ($win.folderUri -and $win.folderUri.StartsWith("file:///")) {
                            $folderPath = [System.Uri]::UnescapeDataString($win.folderUri.Replace("file:///", ""))
                            $workspaces += $folderPath
                        }
                    }
                }

                # lastActiveWindow
                if ($data.lastActiveWindow -and $data.lastActiveWindow.folderUri) {
                    $uri = $data.lastActiveWindow.folderUri
                    if ($uri.StartsWith("file:///")) {
                        $folderPath = [System.Uri]::UnescapeDataString($uri.Replace("file:///", ""))
                        if ($folderPath -notin $workspaces) {
                            $workspaces += $folderPath
                        }
                    }
                }
            } catch {}
        }
    }

    # Also scan workspaceStorage
    $wsStorage = "$env:APPDATA\Code\User\workspaceStorage"
    if (Test-Path $wsStorage) {
        Get-ChildItem $wsStorage -Directory | ForEach-Object {
            $wsJson = Join-Path $_.FullName "workspace.json"
            if (Test-Path $wsJson) {
                try {
                    $ws = Get-Content $wsJson -Raw | ConvertFrom-Json
                    if ($ws.folder -and $ws.folder.StartsWith("file:///")) {
                        $folderPath = [System.Uri]::UnescapeDataString($ws.folder.Replace("file:///", ""))
                        if ($folderPath -notin $workspaces) {
                            $workspaces += $folderPath
                        }
                    }
                } catch {}
            }
        }
    }

    return $workspaces
}

function Get-PowerShellDirectories {
    <# Get working directories of PowerShell/cmd/Terminal processes #>
    $dirs = @()
    try {
        $procs = Get-Process -Name powershell, pwsh, cmd, WindowsTerminal -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            try {
                # Get the working directory via CIM
                $cimProc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                if ($cimProc -and $cimProc.ExecutablePath) {
                    $dirs += @{
                        pid = $proc.Id
                        name = $proc.ProcessName
                        # CommandLine may contain the working directory
                        commandLine = $cimProc.CommandLine
                    }
                }
            } catch {}
        }
    } catch {}
    return $dirs
}

# ============================================================================
# SAVE
# ============================================================================
function Save-Layout {
    param([string]$LayoutName, [string]$Desc)

    $layoutFile = Join-Path $LayoutDir "$LayoutName.json"
    Write-Host "  Capturing workspace layout: $LayoutName" -ForegroundColor Cyan

    # --- Screen info ---
    Write-Host "    -> Detecting displays..." -ForegroundColor Blue
    $screens = @()
    try {
        Add-Type -AssemblyName System.Windows.Forms
        foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
            $screens += @{
                name = $screen.DeviceName
                primary = $screen.Primary
                x = $screen.Bounds.X
                y = $screen.Bounds.Y
                width = $screen.Bounds.Width
                height = $screen.Bounds.Height
                workingArea = @{
                    x = $screen.WorkingArea.X
                    y = $screen.WorkingArea.Y
                    width = $screen.WorkingArea.Width
                    height = $screen.WorkingArea.Height
                }
            }
        }
    } catch {}
    Write-Host "    [OK] Found $($screens.Count) display(s)" -ForegroundColor Green

    # --- All windows ---
    Write-Host "    -> Capturing all windows..." -ForegroundColor Blue
    $allWindows = [WindowHelper]::GetAllWindows()
    Write-Host "    [OK] Found $($allWindows.Count) visible window(s)" -ForegroundColor Green

    # --- Categorize windows ---
    $explorerWindows = @()
    $browserWindows = @()
    $vscodeWindows = @()
    $terminalWindows = @()
    $otherWindows = @()

    # Skip list for system processes
    $skipProcesses = @("SearchUI", "ShellExperienceHost", "StartMenuExperienceHost",
                       "TextInputHost", "ApplicationFrameHost", "SystemSettings",
                       "LockApp", "SearchApp", "ScreenClippingHost")

    # Get Explorer folder paths
    Write-Host "    -> Capturing Explorer folders..." -ForegroundColor Blue
    $explorerPaths = Get-ExplorerPaths
    Write-Host "    [OK] Found $($explorerPaths.Count) Explorer window(s)" -ForegroundColor Green

    # Get VS Code workspace info
    Write-Host "    -> Capturing VS Code workspaces..." -ForegroundColor Blue
    $vscodeWorkspaces = Get-VSCodeWorkspaces
    Write-Host "    [OK] Found $($vscodeWorkspaces.Count) VS Code workspace(s)" -ForegroundColor Green

    # Get browser tab group info
    Write-Host "    -> Capturing browser tab groups..." -ForegroundColor Blue
    $braveInfo = Get-BraveTabs
    Write-Host "    [OK] Done" -ForegroundColor Green

    foreach ($win in $allWindows) {
        if ($win.ProcessName -in $skipProcesses) { continue }
        if ($win.Width -lt 50 -or $win.Height -lt 50) { continue }

        $winData = @{
            title = $win.Title
            processName = $win.ProcessName
            processPath = $win.ProcessPath
            bounds = @{
                x = $win.X
                y = $win.Y
                width = $win.Width
                height = $win.Height
            }
            hwnd = $win.Handle.ToInt64()
        }

        switch -Regex ($win.ProcessName) {
            "^explorer$" {
                # Match with Shell.Application data for folder path
                $matchedPath = $explorerPaths | Where-Object { $_.hwnd -eq $win.Handle.ToInt64() } | Select-Object -First 1
                if ($matchedPath) {
                    $winData["path"] = $matchedPath.path
                }
                $explorerWindows += $winData
            }
            "^(brave|chrome|msedge|firefox)$" {
                $winData["app"] = $win.ProcessName
                $browserWindows += $winData
            }
            "^(Code|Code - Insiders)$" {
                # Try to match workspace
                $wsName = ""
                if ($win.Title -match "^(.+?)\s+[-\u2014]\s+(.+?)\s+[-\u2014]\s+Visual Studio Code") {
                    $wsName = $Matches[2]
                } elseif ($win.Title -match "^(.+?)\s+[-\u2014]\s+Visual Studio Code") {
                    $wsName = $Matches[1]
                }
                $winData["workspace"] = $wsName

                # Find actual path
                foreach ($wsPath in $vscodeWorkspaces) {
                    if ($wsPath -and $wsName -and (Split-Path $wsPath -Leaf) -ieq $wsName) {
                        $winData["workspacePath"] = $wsPath
                        break
                    }
                }
                $vscodeWindows += $winData
            }
            "^(powershell|pwsh|cmd|WindowsTerminal|wt)$" {
                $terminalWindows += $winData
            }
            default {
                $otherWindows += $winData
            }
        }
    }

    # --- Assemble layout ---
    Write-Host "    -> Saving layout..." -ForegroundColor Blue
    $layout = @{
        name = $LayoutName
        description = $Desc
        platform = "windows"
        savedAt = (Get-Date).ToString("o")
        screenCount = $screens.Count
        screens = $screens
        windows = @{
            explorer = $explorerWindows
            browser = $browserWindows
            vscode = $vscodeWindows
            terminal = $terminalWindows
            other = $otherWindows
        }
        vscodeWorkspaces = $vscodeWorkspaces
        braveTabGroups = $braveInfo.groups
    }

    $layout | ConvertTo-Json -Depth 10 | Set-Content $layoutFile -Encoding UTF8

    $total = $explorerWindows.Count + $browserWindows.Count + $vscodeWindows.Count + $terminalWindows.Count + $otherWindows.Count
    Write-Host "    [OK] Saved $total windows across $($screens.Count) screen(s)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Layout '$LayoutName' saved to $layoutFile" -ForegroundColor Green
}


# ============================================================================
# RESTORE
# ============================================================================
function Restore-Layout {
    param([string]$LayoutName)

    $layoutFile = Join-Path $LayoutDir "$LayoutName.json"
    if (-not (Test-Path $layoutFile)) {
        Write-Host "  Layout '$LayoutName' not found." -ForegroundColor Red
        List-Layouts
        return
    }

    Write-Host "  Restoring workspace layout: $LayoutName" -ForegroundColor Cyan
    $layout = Get-Content $layoutFile -Raw | ConvertFrom-Json

    # Screen check
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $currentScreenCount = [System.Windows.Forms.Screen]::AllScreens.Count
    if ($currentScreenCount -ne $layout.screenCount) {
        Write-Host "  Warning: Layout saved with $($layout.screenCount) screen(s), you have $currentScreenCount." -ForegroundColor Yellow
    }

    # --- Restore Explorer windows ---
    $explorerWindows = $layout.windows.explorer
    if ($explorerWindows -and $explorerWindows.Count -gt 0) {
        Write-Host "    Restoring $($explorerWindows.Count) Explorer window(s)..." -ForegroundColor Blue
        foreach ($ew in $explorerWindows) {
            $path = $ew.path
            if ($path -and (Test-Path $path)) {
                Start-Process explorer.exe -ArgumentList $path
                Start-Sleep -Milliseconds 800
            }
        }
        # Wait for windows to open, then position them
        Start-Sleep -Seconds 1
        $shell = New-Object -ComObject Shell.Application
        $openWindows = $shell.Windows()
        for ($i = 0; $i -lt [Math]::Min($openWindows.Count, $explorerWindows.Count); $i++) {
            try {
                $ew = $explorerWindows[$i]
                $b = $ew.bounds
                $hwnd = [IntPtr]$openWindows.Item($i).HWND
                [WindowHelper]::MoveWindow($hwnd, $b.x, $b.y, $b.width, $b.height, $true)
            } catch {}
        }
        Write-Host "    [OK] Explorer windows restored" -ForegroundColor Green
    }

    # --- Restore VS Code windows ---
    $vscodeWindows = $layout.windows.vscode
    if ($vscodeWindows -and $vscodeWindows.Count -gt 0) {
        Write-Host "    Restoring $($vscodeWindows.Count) VS Code window(s)..." -ForegroundColor Blue
        foreach ($vw in $vscodeWindows) {
            $wsPath = if ($vw.workspacePath) { $vw.workspacePath } else { $vw.workspace }
            if ($wsPath -and (Test-Path $wsPath -ErrorAction SilentlyContinue)) {
                Start-Process code -ArgumentList $wsPath -ErrorAction SilentlyContinue
            } else {
                Start-Process code -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 2
        }
        # Position VS Code windows
        Start-Sleep -Seconds 1
        $codeProcs = Get-Process -Name "Code" -ErrorAction SilentlyContinue
        if ($codeProcs) {
            $codeHwnds = [WindowHelper]::GetAllWindows() | Where-Object { $_.ProcessName -eq "Code" }
            for ($i = 0; $i -lt [Math]::Min($codeHwnds.Count, $vscodeWindows.Count); $i++) {
                $b = $vscodeWindows[$i].bounds
                [WindowHelper]::MoveWindow($codeHwnds[$i].Handle, $b.x, $b.y, $b.width, $b.height, $true)
            }
        }
        Write-Host "    [OK] VS Code windows restored" -ForegroundColor Green
    }

    # --- Restore browser windows ---
    $browserWindows = $layout.windows.browser
    if ($browserWindows -and $browserWindows.Count -gt 0) {
        Write-Host "    Restoring $($browserWindows.Count) browser window(s)..." -ForegroundColor Blue
        foreach ($bw in $browserWindows) {
            $browserExe = switch ($bw.app) {
                "brave"  { "brave.exe" }
                "chrome" { "chrome.exe" }
                "msedge" { "msedge.exe" }
                default  { "brave.exe" }
            }
            try {
                Start-Process $browserExe -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            } catch {}
        }
        Start-Sleep -Seconds 1
        # Position browser windows
        $browserProcs = [WindowHelper]::GetAllWindows() | Where-Object {
            $_.ProcessName -match "^(brave|chrome|msedge|firefox)$"
        }
        for ($i = 0; $i -lt [Math]::Min($browserProcs.Count, $browserWindows.Count); $i++) {
            $b = $browserWindows[$i].bounds
            [WindowHelper]::MoveWindow($browserProcs[$i].Handle, $b.x, $b.y, $b.width, $b.height, $true)
        }
        Write-Host "    [OK] Browser windows restored" -ForegroundColor Green
    }

    # --- Restore terminal windows ---
    $terminalWindows = $layout.windows.terminal
    if ($terminalWindows -and $terminalWindows.Count -gt 0) {
        Write-Host "    Restoring $($terminalWindows.Count) terminal window(s)..." -ForegroundColor Blue
        foreach ($tw in $terminalWindows) {
            $termExe = switch -Regex ($tw.processName) {
                "WindowsTerminal|wt" { "wt.exe" }
                "pwsh"               { "pwsh.exe" }
                "powershell"         { "powershell.exe" }
                default              { "cmd.exe" }
            }
            try {
                Start-Process $termExe -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            } catch {}
        }
        Start-Sleep -Seconds 1
        # Position terminal windows
        $termProcs = [WindowHelper]::GetAllWindows() | Where-Object {
            $_.ProcessName -match "^(powershell|pwsh|cmd|WindowsTerminal|wt)$"
        }
        for ($i = 0; $i -lt [Math]::Min($termProcs.Count, $terminalWindows.Count); $i++) {
            $b = $terminalWindows[$i].bounds
            [WindowHelper]::MoveWindow($termProcs[$i].Handle, $b.x, $b.y, $b.width, $b.height, $true)
        }
        Write-Host "    [OK] Terminal windows restored" -ForegroundColor Green
    }

    # --- Restore other windows ---
    $otherWindows = $layout.windows.other
    if ($otherWindows -and $otherWindows.Count -gt 0) {
        # Group by process
        $grouped = $otherWindows | Group-Object -Property processName
        foreach ($group in $grouped) {
            Write-Host "    Restoring $($group.Count) $($group.Name) window(s)..." -ForegroundColor Blue
            foreach ($ow in $group.Group) {
                $exePath = $ow.processPath
                if ($exePath -and (Test-Path $exePath)) {
                    try {
                        Start-Process $exePath -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 500
                    } catch {}
                }
            }
            Start-Sleep -Milliseconds 500
            # Position
            $procs = [WindowHelper]::GetAllWindows() | Where-Object { $_.ProcessName -eq $group.Name }
            for ($i = 0; $i -lt [Math]::Min($procs.Count, $group.Group.Count); $i++) {
                $b = $group.Group[$i].bounds
                [WindowHelper]::MoveWindow($procs[$i].Handle, $b.x, $b.y, $b.width, $b.height, $true)
            }
        }
        Write-Host "    [OK] Other windows restored" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  Layout restored!" -ForegroundColor Green
}


# ============================================================================
# LIST
# ============================================================================
function List-Layouts {
    Write-Host "  Saved Workspace Layouts:" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-ChildItem $LayoutDir -Filter "*.json" -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) {
        Write-Host "  No layouts saved yet." -ForegroundColor Yellow
        Write-Host "  Run: .\layout.ps1 save <name>" -ForegroundColor White
        return
    }

    foreach ($f in $files) {
        $layout = Get-Content $f.FullName -Raw | ConvertFrom-Json
        $name = $layout.name
        $desc = $layout.description
        $saved = $layout.savedAt.Substring(0, 19).Replace("T", " ")
        $screenCount = $layout.screenCount
        $total = 0
        $layout.windows.PSObject.Properties | ForEach-Object {
            if ($_.Value -is [System.Array]) { $total += $_.Value.Count }
        }

        Write-Host "  $name" -ForegroundColor White -NoNewline
        Write-Host " ($($layout.platform))" -ForegroundColor DarkGray
        if ($desc) { Write-Host "    $desc" -ForegroundColor Gray }
        Write-Host "    $total windows | $screenCount screen(s) | saved $saved" -ForegroundColor DarkGray
        Write-Host ""
    }
}


# ============================================================================
# INFO
# ============================================================================
function Show-LayoutInfo {
    param([string]$LayoutName)

    $layoutFile = Join-Path $LayoutDir "$LayoutName.json"
    if (-not (Test-Path $layoutFile)) {
        Write-Host "  Layout '$LayoutName' not found." -ForegroundColor Red
        return
    }

    $layout = Get-Content $layoutFile -Raw | ConvertFrom-Json

    Write-Host "  Layout: $($layout.name)" -ForegroundColor Cyan
    if ($layout.description) { Write-Host "  Description: $($layout.description)" }
    Write-Host "  Platform: $($layout.platform)"
    Write-Host "  Saved: $($layout.savedAt.Substring(0, 19).Replace('T', ' '))"
    Write-Host "  Screens: $($layout.screenCount)"
    Write-Host ""

    $categories = @{
        explorer = "Explorer"
        browser = "Browser"
        vscode = "VS Code"
        terminal = "Terminal"
        other = "Other"
    }

    foreach ($key in $categories.Keys) {
        $wins = $layout.windows.$key
        if ($wins -and $wins.Count -gt 0) {
            Write-Host "  $($categories[$key]) ($($wins.Count) window(s)):" -ForegroundColor Yellow
            foreach ($w in $wins) {
                $title = if ($w.title.Length -gt 60) { $w.title.Substring(0, 57) + "..." } else { $w.title }
                $extra = ""
                if ($w.path) { $extra = " -> $($w.path)" }
                elseif ($w.workspacePath) { $extra = " -> $($w.workspacePath)" }
                elseif ($w.workspace) { $extra = " -> $($w.workspace)" }
                $b = $w.bounds
                Write-Host "    - $title$extra  [$($b.x),$($b.y) $($b.width)x$($b.height)]" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
}


# ============================================================================
# DELETE
# ============================================================================
function Remove-Layout {
    param([string]$LayoutName)

    $layoutFile = Join-Path $LayoutDir "$LayoutName.json"
    if (-not (Test-Path $layoutFile)) {
        Write-Host "  Layout '$LayoutName' not found." -ForegroundColor Red
        return
    }

    Remove-Item $layoutFile
    Write-Host "  Layout '$LayoutName' deleted." -ForegroundColor Green
}


# ============================================================================
# SCREENS
# ============================================================================
function Show-Screens {
    Write-Host "  Current Display Configuration:" -ForegroundColor Cyan
    Write-Host ""

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $i = 1
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $primary = if ($screen.Primary) { " (primary)" } else { "" }
        Write-Host "  Display ${i}: $($screen.DeviceName)$primary" -ForegroundColor White
        Write-Host "    Bounds: ($($screen.Bounds.X), $($screen.Bounds.Y)) $($screen.Bounds.Width) x $($screen.Bounds.Height)"
        Write-Host "    Working: ($($screen.WorkingArea.X), $($screen.WorkingArea.Y)) $($screen.WorkingArea.Width) x $($screen.WorkingArea.Height)"
        Write-Host ""
        $i++
    }
}


# ============================================================================
# HELP
# ============================================================================
function Show-Help {
    Write-Host "Workspace Layout Manager (Windows)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Save and restore your multi-monitor window layouts."
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\layout.ps1 save <name> [-Description '...']   Save current layout"
    Write-Host "  .\layout.ps1 restore <name>                     Restore a saved layout"
    Write-Host "  .\layout.ps1 list                               List all saved layouts"
    Write-Host "  .\layout.ps1 info <name>                        Show layout details"
    Write-Host "  .\layout.ps1 delete <name>                      Delete a saved layout"
    Write-Host "  .\layout.ps1 screens                            Show current displays"
    Write-Host ""
    Write-Host "Or use the batch launcher:" -ForegroundColor White
    Write-Host "  layout save my-setup"
    Write-Host "  layout restore my-setup"
}


# ============================================================================
# MAIN
# ============================================================================
switch ($Command) {
    "save" {
        if (-not $Name) {
            Write-Host "  Usage: .\layout.ps1 save <name>" -ForegroundColor Red
            return
        }
        Save-Layout -LayoutName $Name -Desc $Description
    }
    "restore" {
        if (-not $Name) {
            Write-Host "  Usage: .\layout.ps1 restore <name>" -ForegroundColor Red
            return
        }
        Restore-Layout -LayoutName $Name
    }
    "list" { List-Layouts }
    "info" {
        if (-not $Name) {
            Write-Host "  Usage: .\layout.ps1 info <name>" -ForegroundColor Red
            return
        }
        Show-LayoutInfo -LayoutName $Name
    }
    "delete" {
        if (-not $Name) {
            Write-Host "  Usage: .\layout.ps1 delete <name>" -ForegroundColor Red
            return
        }
        Remove-Layout -LayoutName $Name
    }
    "screens" { Show-Screens }
    default { Show-Help }
}
