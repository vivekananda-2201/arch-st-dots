#!/usr/bin/env bash
# ==============================================================================
# Omarchy Presentation Terminal Logo Replacement Script (Omarchy -> LINUX)
# ==============================================================================
# Purpose:
#   Replaces the Omarchy ASCII logo in all floating presentation windows
#   (updates, package installations, setups) with the custom LINUX ASCII logo.
#
# How it works:
#   1. Installs the LINUX logo to ~/.config/omarchy/branding/logo.txt
#   2. Creates ~/.local/bin/omarchy-show-logo to override the system script
#      in your user PATH (survives system updates).
#   3. Also updates /usr/share/omarchy/logo.txt (if sudo is available).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGO_SRC="${SCRIPT_DIR}/logo.txt"
USER_LOGO_DIR="${HOME}/.config/omarchy/branding"
USER_BIN_DIR="${HOME}/.local/bin"

mkdir -p "${USER_LOGO_DIR}" "${USER_BIN_DIR}"

# 1. Install user logo
if [[ -f "${LOGO_SRC}" ]]; then
    cp "${LOGO_SRC}" "${USER_LOGO_DIR}/logo.txt"
fi

# 2. Install user wrapper script in PATH
cat << 'EOF' > "${USER_BIN_DIR}/omarchy-show-logo"
#!/bin/bash
clear
echo -e "\033[36m"
if [[ -f "$HOME/.config/omarchy/branding/logo.txt" ]]; then
    cat "$HOME/.config/omarchy/branding/logo.txt"
else
    cat << 'LOGO'
   ▄▄▄▄           ▄▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄▄▄▄   ▄▄▄▄▄    ▄▄▄▄▄  ▄▄▄▄▄▄     ▄▄▄▄▄  
  ██████          █████  ██████████████  █████    █████  ▀██████  ▄█████▀  
  ██████          █████  █████▀▀▀▀█████  █████    █████    ▀███████████▀   
  ██████          █████  █████    █████  █████    █████     ▀█████████     
  ██████          █████  █████    █████  █████    █████       ███████      
  ██████          █████  █████    █████  █████    █████      ████████▄     
  █████▄          █████  █████    █████  █████    █████    ▄███████████    
  █████████████▄  █████  █████    █████  ██████████████   ██████▀ ██████▄  
  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀  ▀▀▀▀▀  ▀▀▀▀▀    ▀▀▀▀▀  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀  ▀▀▀▀▀▀    ▀▀▀▀▀▀  
LOGO
fi
echo -e "\033[0m"
echo
EOF
chmod +x "${USER_BIN_DIR}/omarchy-show-logo"

# 3. Optional: update system copy if root/sudo is accessible
if [[ -f "${LOGO_SRC}" ]] && [[ -w "/usr/share/omarchy/logo.txt" || -n "${SUDO_USER:-}" || $(id -u) -eq 0 ]]; then
    sudo cp "${LOGO_SRC}" /usr/share/omarchy/logo.txt 2>/dev/null || true
fi

echo "LINUX ASCII logo successfully installed!"
echo "It will now display in all floating presentation terminals (updates, installs, etc.)."
