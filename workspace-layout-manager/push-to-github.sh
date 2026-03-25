#!/bin/bash
# Run this script from the workspace-layout-manager/ directory to push to GitHub
# Usage: bash push-to-github.sh

set -euo pipefail

REPO_URL="https://github.com/Ice-Citron/Entrenchment.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR=$(mktemp -d)

echo "📦 Cloning Entrenchment repo..."
git clone "$REPO_URL" "$TEMP_DIR/Entrenchment"

echo "📁 Copying workspace-layout-manager files..."
mkdir -p "$TEMP_DIR/Entrenchment/workspace-layout-manager/windows"

# Copy all files
cp "$SCRIPT_DIR/layout" "$TEMP_DIR/Entrenchment/workspace-layout-manager/layout"
cp "$SCRIPT_DIR/install.sh" "$TEMP_DIR/Entrenchment/workspace-layout-manager/install.sh"
cp "$SCRIPT_DIR/README.md" "$TEMP_DIR/Entrenchment/workspace-layout-manager/README.md"
cp "$SCRIPT_DIR/windows/layout.ps1" "$TEMP_DIR/Entrenchment/workspace-layout-manager/windows/layout.ps1"
cp "$SCRIPT_DIR/windows/layout.bat" "$TEMP_DIR/Entrenchment/workspace-layout-manager/windows/layout.bat"
cp "$SCRIPT_DIR/windows/install.bat" "$TEMP_DIR/Entrenchment/workspace-layout-manager/windows/install.bat"

# Make scripts executable
chmod +x "$TEMP_DIR/Entrenchment/workspace-layout-manager/layout"
chmod +x "$TEMP_DIR/Entrenchment/workspace-layout-manager/install.sh"

# Update root README
cat > "$TEMP_DIR/Entrenchment/README.md" << 'EOF'
# Entrenchment

A collection of productivity tools and automation utilities.

## Projects

### [Workspace Layout Manager](./workspace-layout-manager/)
Save and restore multi-monitor window layouts with a single command. Supports macOS and Windows — captures Finder/Explorer windows, iTerm/PowerShell terminals, Brave/Chrome browser tabs, VS Code workspaces, and more. Switch between project contexts (e.g. Isaac Sim development vs. Computer Architecture revision) without manually rearranging everything.

## License

MIT
EOF

cd "$TEMP_DIR/Entrenchment"

echo "📝 Committing..."
git add -A
git commit -m "Add workspace-layout-manager: cross-platform window layout save/restore

- macOS shell script: captures Finder, iTerm2, Brave Browser, VS Code, Preview, RDP windows
- Windows PowerShell script: captures Explorer, browsers, VS Code, terminals, generic apps
- Both use JSON storage in ~/.config/workspace-layouts/
- Includes install scripts for both platforms"

echo "🚀 Pushing to GitHub..."
git push origin main

echo ""
echo "✅ Done! View at: https://github.com/Ice-Citron/Entrenchment"

# Cleanup
rm -rf "$TEMP_DIR"
