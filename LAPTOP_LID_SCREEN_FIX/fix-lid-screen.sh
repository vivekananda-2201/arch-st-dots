#!/usr/bin/env bash
# ==============================================================================
# Omarchy / Hyprland Laptop Lid Screen-Off Fix Script
# ==============================================================================
# Purpose:
#   Fixes laptop lid screen wakeup issues by disabling system suspend/sleep on
#   lid close, turning the display OFF immediately when closed, and turning it
#   ON immediately when opened — with NO lock screen and NO sleep freeze.
#
# What this script does:
#   1. Configures systemd-logind drop-in (/etc/systemd/logind.conf.d/30-lid-ignore.conf)
#      to ignore lid switch events so the system never suspends or freezes.
#   2. Reloads systemd-logind cleanly without terminating the user session.
#   3. Installs a lightweight lid handler at ~/.local/bin/omarchy-lid-handler
#      that dispatches Hyprland DPMS off/on and supports clamshell mode if an
#      external monitor is connected.
#   4. Updates ~/.config/hypr/bindings.lua to unbind Omarchy's default lid lock
#      and bind the new instant screen-off/screen-on handler.
#   5. Validates Hyprland configuration with `hyprctl reload` and `hyprctl configerrors`.
# ==============================================================================

set -euo pipefail

# Output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

CURRENT_USER="${USER:-$(id -un)}"
USER_HOME="${HOME:-$(getent passwd "${CURRENT_USER}" | cut -d: -f6)}"
BIN_DIR="${USER_HOME}/.local/bin"
HANDLER_PATH="${BIN_DIR}/omarchy-lid-handler"
HYPR_DIR="${USER_HOME}/.config/hypr"
BINDINGS_LUA="${HYPR_DIR}/bindings.lua"
LOGIND_DROPIN_DIR="/etc/systemd/logind.conf.d"
LOGIND_DROPIN_FILE="${LOGIND_DROPIN_DIR}/30-lid-ignore.conf"
TIMESTAMP=$(date +%s)

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  Omarchy / Hyprland Laptop Lid Screen-Off Fix        ${NC}"
echo -e "${BOLD}======================================================${NC}"
info "Running fix for user: ${CURRENT_USER}..."

# ------------------------------------------------------------------------------
# 1. Configure systemd-logind to Ignore Lid Switch Events (No Suspend / Sleep)
# ------------------------------------------------------------------------------
info "Configuring systemd-logind to ignore lid switch events..."

sudo_cmd=""
if [[ $EUID -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
        sudo_cmd="sudo"
    else
        error "Root privileges are required to configure /etc/systemd/logind.conf.d/. Please run with sudo."
        exit 1
    fi
fi

$sudo_cmd mkdir -p "${LOGIND_DROPIN_DIR}"

info "Writing ${LOGIND_DROPIN_FILE}..."
$sudo_cmd bash -c "cat << 'EOF' > '${LOGIND_DROPIN_FILE}'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF"

success "Created ${LOGIND_DROPIN_FILE}"

info "Reloading systemd-logind service configuration..."
$sudo_cmd systemctl reload systemd-logind
success "systemd-logind successfully reloaded."

# ------------------------------------------------------------------------------
# 2. Install omarchy-lid-handler in ~/.local/bin
# ------------------------------------------------------------------------------
info "Installing lid handler script to ${HANDLER_PATH}..."
mkdir -p "${BIN_DIR}"

cat << 'EOF' > "${HANDLER_PATH}"
#!/bin/bash

# omarchy-lid-handler: Screen off on lid close, screen on on lid open (no suspend, no lock)

case "$1" in
  close)
    if omarchy-hw-external-monitors 2>/dev/null; then
      # Clamshell mode: keep external monitor active, turn off internal laptop screen only
      INTERNAL=$(omarchy-hyprland-monitor-laptop 2>/dev/null)
      hyprctl dispatch "hl.dsp.dpms({ action = 'off', monitor = '${INTERNAL:-eDP-2}' })" >/dev/null 2>&1 || true
    else
      # Standalone mode: turn off display immediately
      hyprctl dispatch "hl.dsp.dpms({ action = 'off' })" >/dev/null 2>&1 || true
    fi
    ;;
  open)
    # Turn display back on immediately
    hyprctl dispatch "hl.dsp.dpms({ action = 'on' })" >/dev/null 2>&1 || true
    ;;
  *)
    echo "Usage: $0 {close|open}" >&2
    exit 1
    ;;
esac
EOF

chmod +x "${HANDLER_PATH}"
success "Installed executable lid handler at ${HANDLER_PATH}"

# ------------------------------------------------------------------------------
# 3. Update ~/.config/hypr/bindings.lua
# ------------------------------------------------------------------------------
mkdir -p "${HYPR_DIR}"

if [[ ! -f "${BINDINGS_LUA}" ]]; then
    info "Creating new ${BINDINGS_LUA}..."
    touch "${BINDINGS_LUA}"
fi

# Check if lid switch bindings already exist in bindings.lua
if grep -q "omarchy-lid-handler" "${BINDINGS_LUA}"; then
    info "Lid switch bindings already configured in ${BINDINGS_LUA}; skipping append."
else
    info "Backing up ${BINDINGS_LUA} to ${BINDINGS_LUA}.bak.${TIMESTAMP}..."
    cp "${BINDINGS_LUA}" "${BINDINGS_LUA}.bak.${TIMESTAMP}"

    info "Adding lid switch overrides to ${BINDINGS_LUA}..."
    cat << 'EOF' >> "${BINDINGS_LUA}"

----------------------------------------------------------------
-- Lid Switch (Display off on close, display on on open - no suspend/lock)
----------------------------------------------------------------
hl.unbind("switch:on:Lid Switch")
hl.unbind("switch:off:Lid Switch")

o.bind("switch:on:Lid Switch", "Turn display off on lid close", "omarchy-lid-handler close", { locked = true })
o.bind("switch:off:Lid Switch", "Turn display on on lid open", "omarchy-lid-handler open", { locked = true })
EOF
    success "Appended custom lid bindings to ${BINDINGS_LUA}"
fi

# ------------------------------------------------------------------------------
# 4. Reload Hyprland and Validate Configuration
# ------------------------------------------------------------------------------
if command -v hyprctl &>/dev/null; then
    info "Reloading Hyprland configuration..."
    hyprctl reload >/dev/null 2>&1 || true

    errors=$(hyprctl configerrors 2>&1 || true)
    if [[ -z "${errors// }" ]]; then
        success "Hyprland configuration validated cleanly with 0 errors."
    else
        warn "Hyprland reported config notices:"
        echo "${errors}"
    fi
else
    warn "hyprctl not found or Hyprland is not currently running. Changes will take effect on next login."
fi

# ------------------------------------------------------------------------------
# 5. Verification Summary
# ------------------------------------------------------------------------------
echo ""
success "Laptop Lid Screen-Off Fix applied successfully!"
echo -e "  ${GREEN}✔${NC} System sleep on lid close disabled (systemd-logind drop-in active)."
echo -e "  ${GREEN}✔${NC} Screen powers completely OFF on lid close (no lock screen, no sleep freeze)."
echo -e "  ${GREEN}✔${NC} Screen powers immediately ON on lid open (instant display wakeup)."
echo -e "  ${GREEN}✔${NC} Background processes, music, downloads, and SSH sessions continue running."
echo -e "  ${GREEN}✔${NC} Clamshell mode supported (closing lid with external monitor keeps external monitor on)."
echo ""
echo -e "${BLUE}Test it now:${NC} Simply close your laptop lid, wait a moment, and open it again."
