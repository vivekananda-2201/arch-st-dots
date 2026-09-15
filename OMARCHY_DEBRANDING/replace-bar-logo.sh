#!/usr/bin/env bash
# ==============================================================================
# Omarchy Bar Logo Replacement Script (Omarchy -> Arch Linux Logo)
# ==============================================================================
# Purpose:
#   Replaces the proprietary Omarchy logo (\ue900) on the Quickshell status bar
#   with the official Arch Linux logo (, \uf303) from Nerd Fonts.
#
# How it works:
#   1. Creates a standalone user plugin at ~/.config/omarchy/plugins/<user>.menu/
#   2. Installs BarWidget.qml configured with text: "" (Arch Linux glyph)
#      using the system's default Nerd Font family.
#   3. Keeps the native omarchy.menu active so all menu popups, hotkeys,
#      and command launchers continue to work untouched.
#   4. Updates ~/.config/omarchy/shell.json to load the Arch widget in the bar.
#   5. Hot-reloads Quickshell to apply the change immediately.
# ==============================================================================

set -euo pipefail

# Output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

CURRENT_USER="${USER:-$(id -un)}"
PLUGIN_ID="${CURRENT_USER}.menu"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"
TARGET_DIR="${PLUGINS_DIR}/${PLUGIN_ID}"
SHELL_CONF="${HOME}/.config/omarchy/shell.json"
TIMESTAMP=$(date +%s)

info "Setting up Arch Linux logo on the status bar for user: ${CURRENT_USER}..."

# ------------------------------------------------------------------------------
# 1. Create User Bar Widget Plugin
# ------------------------------------------------------------------------------
mkdir -p "${TARGET_DIR}"

info "Writing plugin manifest to ${TARGET_DIR}/manifest.json..."
cat << EOF > "${TARGET_DIR}/manifest.json"
{
  "schemaVersion": 1,
  "id": "${PLUGIN_ID}",
  "name": "Arch Linux menu button",
  "version": "1.0.0",
  "author": "${CURRENT_USER}",
  "description": "Quickshell bar widget displaying the Arch Linux logo",
  "kinds": [
    "bar-widget"
  ],
  "keepLoaded": true,
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Arch Menu",
    "description": "Launches the Omarchy menu with Arch logo",
    "category": "Compositor",
    "allowMultiple": false
  }
}
EOF

info "Writing Arch Linux bar widget to ${TARGET_DIR}/BarWidget.qml..."
cat << 'EOF' > "${TARGET_DIR}/BarWidget.qml"
import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
EOF
success "Plugin files created in ${TARGET_DIR}"

# ------------------------------------------------------------------------------
# 2. Update ~/.config/omarchy/shell.json
# ------------------------------------------------------------------------------
if [[ -f "${SHELL_CONF}" ]]; then
    cp "${SHELL_CONF}" "${SHELL_CONF}.bak.${TIMESTAMP}"
    info "Created backup of shell.json at ${SHELL_CONF}.bak.${TIMESTAMP}"

    # Use jq to cleanly replace omarchy.menu with the new widget ID and ensure it's not disabled
    jq \
      --arg oldId "omarchy.menu" \
      --arg newId "${PLUGIN_ID}" '
        walk(
          if type == "object" and .id == $oldId then
            .id = $newId
          else
            .
          end
        )
        | if .disabledPlugins then
            .disabledPlugins = [.disabledPlugins[] | select(. != $oldId and . != $newId)]
          else
            .
          end
      ' "${SHELL_CONF}" > "${SHELL_CONF}.tmp"
    mv "${SHELL_CONF}.tmp" "${SHELL_CONF}"
    success "Updated ${SHELL_CONF} to use ${PLUGIN_ID}"
else
    warn "${SHELL_CONF} not found; skipping shell.json edit."
fi

# ------------------------------------------------------------------------------
# 3. Rescan Plugins and Restart Shell
# ------------------------------------------------------------------------------
info "Reloading Quickshell status bar..."

if command -v omarchy-shell &>/dev/null; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if command -v omarchy &>/dev/null; then
    omarchy restart shell >/dev/null 2>&1 || true
fi

success "Status bar logo successfully replaced with the Arch Linux logo ()!"
echo -e "  - Left-click: Toggles the menu as usual.\n  - Right-click: Opens terminal.\n  - Native omarchy.menu backend remains 100% active."
