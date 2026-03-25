#!/bin/bash
# ============================================================================
# Workspace Layout Manager - Installer
# Installs the `layout` command so you can use it from any terminal
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"

echo "🔧 Installing Workspace Layout Manager..."
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy the script
cp "$SCRIPT_DIR/layout" "$INSTALL_DIR/layout"
chmod +x "$INSTALL_DIR/layout"

# Create the config directory
mkdir -p "${HOME}/.config/workspace-layouts"

# Add to PATH if not already there
add_to_path() {
    local shell_rc="$1"
    if [[ -f "$shell_rc" ]]; then
        if ! grep -q '.local/bin' "$shell_rc" 2>/dev/null; then
            echo '' >> "$shell_rc"
            echo '# Workspace Layout Manager' >> "$shell_rc"
            echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "$shell_rc"
            echo "  ✓ Added to PATH in $(basename "$shell_rc")"
        else
            echo "  ✓ PATH already configured in $(basename "$shell_rc")"
        fi
    fi
}

# Detect shell and add to PATH
if [[ -f "${HOME}/.zshrc" ]]; then
    add_to_path "${HOME}/.zshrc"
elif [[ -f "${HOME}/.bashrc" ]]; then
    add_to_path "${HOME}/.bashrc"
elif [[ -f "${HOME}/.bash_profile" ]]; then
    add_to_path "${HOME}/.bash_profile"
fi

echo ""
echo "✅ Installed! You can now use the 'layout' command."
echo ""
echo "Quick start:"
echo "  layout save isaac-sim-3screen --desc \"Isaac Sim on 3 screens\""
echo "  layout save comp-arch-study --desc \"40005 Computer Architecture\""
echo "  layout restore isaac-sim-3screen"
echo "  layout list"
echo ""
echo "⚠️  If 'layout' is not found, restart your terminal or run:"
echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
echo ""
echo "📌 Note: On first use, macOS will ask for Accessibility permissions."
echo "   Go to System Settings → Privacy & Security → Accessibility"
echo "   and allow iTerm (or Terminal) to control your computer."
