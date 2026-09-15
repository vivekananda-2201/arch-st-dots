#!/usr/bin/env bash
# ==============================================================================
# Omarchy Splash & Quiet Boot Removal Script
# ==============================================================================
# Purpose:
#   Completely removes Plymouth graphical boot splash and quiet boot parameters
#   on Omarchy Linux systems using Limine bootloader and mkinitcpio UKIs.
#
# What it does:
#   1. Strips 'plymouth' hook from mkinitcpio initramfs configuration.
#   2. Creates persistent drop-in /etc/mkinitcpio.conf.d/zz_no_plymouth.conf
#      so future package updates never re-add Plymouth.
#   3. Cleans kernel command line in /etc/default/limine (removes 'quiet',
#      'splash', 'loglevel=0', 'systemd.show_status=false', 'rd.udev.log_level=0',
#      and 'vt.global_cursor_default=0') while preserving all essential boot,
#      LUKS, Btrfs, and hibernation parameters.
#   4. Rebuilds the Unified Kernel Image (UKI) and updates /boot/limine.conf.
# ==============================================================================

set -euo pipefail

# Color output helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Ensure running as root
if (( EUID != 0 )); then
    info "Elevating privileges with sudo..."
    exec sudo bash "$0" "$@"
fi

info "Starting Omarchy splash & quiet boot removal..."

TIMESTAMP=$(date +%s)

# ------------------------------------------------------------------------------
# 1. mkinitcpio: Remove Plymouth hook
# ------------------------------------------------------------------------------
info "Configuring mkinitcpio to exclude Plymouth from initramfs..."

# Create a permanent high-priority drop-in that strips 'plymouth' from HOOKS array
cat << 'EOF' > /etc/mkinitcpio.conf.d/zz_no_plymouth.conf
# Persistent override: Drop plymouth hook to boot in raw TTY mode
HOOKS=(${HOOKS[@]/plymouth/})
EOF
success "Created /etc/mkinitcpio.conf.d/zz_no_plymouth.conf"

# Also clean /etc/mkinitcpio.conf.d/omarchy_hooks.conf if it exists
if [[ -f /etc/mkinitcpio.conf.d/omarchy_hooks.conf ]]; then
    if grep -q "plymouth" /etc/mkinitcpio.conf.d/omarchy_hooks.conf; then
        cp /etc/mkinitcpio.conf.d/omarchy_hooks.conf "/etc/mkinitcpio.conf.d/omarchy_hooks.conf.bak.${TIMESTAMP}"
        sed -i 's/ plymouth / /g' /etc/mkinitcpio.conf.d/omarchy_hooks.conf
        success "Cleaned 'plymouth' from /etc/mkinitcpio.conf.d/omarchy_hooks.conf (backup created)"
    fi
fi

# ------------------------------------------------------------------------------
# 2. Limine: Clean Kernel Command Line
# ------------------------------------------------------------------------------
info "Configuring /etc/default/limine kernel command line..."

LIMINE_CONF="/etc/default/limine"
if [[ -f "$LIMINE_CONF" ]]; then
    cp "$LIMINE_CONF" "${LIMINE_CONF}.bak.${TIMESTAMP}"
    info "Created backup of ${LIMINE_CONF} at ${LIMINE_CONF}.bak.${TIMESTAMP}"
fi

# Determine current required hardware and boot arguments
# We check /etc/default/limine backup first, then fall back to /proc/cmdline
SOURCE_CMDLINE=""
if [[ -f "${LIMINE_CONF}.bak.${TIMESTAMP}" ]]; then
    SOURCE_CMDLINE=$(grep -E '^KERNEL_CMDLINE\[default\]' "${LIMINE_CONF}.bak.${TIMESTAMP}" | sed 's/.*=//; s/["\+]//g' | tr '\n' ' ')
fi
if [[ -z "$SOURCE_CMDLINE" ]]; then
    SOURCE_CMDLINE=$(cat /proc/cmdline)
fi

# Extract essential parameters (cryptdevice, root, zswap, rootflags, rw, rootfstype, resume, resume_offset, rtc_cmos, initramfs_async)
declare -a CLEAN_PARAMS=()
for param in $SOURCE_CMDLINE; do
    case "$param" in
        quiet|splash|loglevel=*|systemd.show_status=*|rd.udev.log_level=*|vt.global_cursor_default=*)
            # Suppress unwanted silent boot flags
            continue
            ;;
        *)
            # Only add if not already present
            if [[ ! " ${CLEAN_PARAMS[*]:-} " =~ " ${param} " ]]; then
                CLEAN_PARAMS+=("$param")
            fi
            ;;
    esac
done

# Ensure initramfs_async=0 is present (recommended by Omarchy to prevent init race)
if [[ ! " ${CLEAN_PARAMS[*]:-} " =~ " initramfs_async=0 " ]]; then
    CLEAN_PARAMS+=("initramfs_async=0")
fi

CLEAN_CMDLINE_STR="${CLEAN_PARAMS[*]}"

# Write the updated /etc/default/limine using '=' assignment to override drop-ins
cat << EOF > "$LIMINE_CONF"
TARGET_OS_NAME="Omarchy"

ESP_PATH="/boot"

KERNEL_CMDLINE[default]="${CLEAN_CMDLINE_STR}"

ENABLE_UKI=yes
CUSTOM_UKI_NAME="omarchy"

ENABLE_LIMINE_FALLBACK=yes

# Find and add other bootloaders
FIND_BOOTLOADERS=yes

BOOT_ORDER="*, *fallback, Snapshots"

MAX_SNAPSHOT_ENTRIES=5

SNAPSHOT_FORMAT_CHOICE=5
EOF

success "Updated /etc/default/limine with verbose parameters:"
echo "  -> ${CLEAN_CMDLINE_STR}"

# ------------------------------------------------------------------------------
# 3. Rebuild Unified Kernel Image (UKI) & Update Bootloader
# ------------------------------------------------------------------------------
info "Rebuilding UKI image and updating Limine..."

if command -v limine-update &>/dev/null; then
    limine-update
elif command -v limine-mkinitcpio &>/dev/null; then
    limine-mkinitcpio
elif command -v mkinitcpio &>/dev/null; then
    mkinitcpio -P
else
    error "Neither limine-update nor mkinitcpio was found. Please rebuild initramfs manually."
    exit 1
fi

# Sync snapper bootloader entries if tool is present
if command -v limine-snapper-sync &>/dev/null; then
    limine-snapper-sync || true
fi

# ------------------------------------------------------------------------------
# 4. Verification
# ------------------------------------------------------------------------------
echo ""
info "Verifying resulting kernel command line..."
if command -v limine-entry-tool &>/dev/null; then
    RESULT_CMDLINE=$(limine-entry-tool --get-cmdline linux 2>/dev/null | tr '\n' ' ' || true)
    if [[ -n "$RESULT_CMDLINE" ]]; then
        echo "Active cmdline: $RESULT_CMDLINE"
        if [[ "$RESULT_CMDLINE" =~ quiet|splash ]]; then
            warn "Kernel cmdline still contains quiet/splash. Check /etc/limine-entry-tool.d/ drop-ins."
        else
            success "Verified: quiet and splash are completely gone!"
        fi
    fi
fi

echo ""
success "Splash removal completed successfully!"
echo -e "On your next reboot:\n  - Kernel & systemd logs will be fully visible on screen.\n  - LUKS passphrase prompt will appear directly in raw text TTY.\n  - Blinking console cursor is active."
