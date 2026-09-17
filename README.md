# Arch Linux & Omarchy Dotfiles & Fixes (`arch-st-dots`)

Personal dotfiles, automation scripts, and hardware fixes for Arch Linux with Omarchy and Hyprland.

---

## Directory Index

### 1. [`LAPTOP_LID_SCREEN_FIX/`](LAPTOP_LID_SCREEN_FIX/)
Fixes laptop lid screen wake-up freeze on hybrid Intel/NVIDIA laptops (e.g. ASUS TUF Gaming F16).
- **Behavior:** Powers screen completely OFF when lid is closed; powers screen immediately ON when lid is opened (0 lock screen, 0 suspend freeze).
- **Guide:** [`LAPTOP_LID_SCREEN_FIX/README.md`](LAPTOP_LID_SCREEN_FIX/README.md)
- **Script:** [`LAPTOP_LID_SCREEN_FIX/fix-lid-screen.sh`](LAPTOP_LID_SCREEN_FIX/fix-lid-screen.sh)

---

### 2. [`OMARCHY_DEBRANDING/`](OMARCHY_DEBRANDING/)
Collection of scripts to replace Omarchy branding with clean Arch Linux and upstream Linux styling.
- **Status Bar Logo:** [`replace-bar-logo.sh`](OMARCHY_DEBRANDING/replace-bar-logo.sh) — Replaces Omarchy bar glyph with official Arch Linux Nerd Font icon (``).
- **Terminal Logo:** [`replace-terminal-logo.sh`](OMARCHY_DEBRANDING/replace-terminal-logo.sh) — Replaces Omarchy ASCII art with clean "LINUX" block ASCII art.
- **Boot Splash Removal:** [`remove-splash.sh`](OMARCHY_DEBRANDING/remove-splash.sh) — Safely removes Plymouth boot splash and configures clean verbose Linux boot logs.
- **Lid Fix:** [`fix-lid-screen.sh`](OMARCHY_DEBRANDING/fix-lid-screen.sh) & [`laptop_lid_screen_off_fix.md`](OMARCHY_DEBRANDING/laptop_lid_screen_off_fix.md).