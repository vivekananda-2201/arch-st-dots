# Laptop Lid Screen Wakeup & Instant Screen-Off Fix

## Overview & Goal

On laptops running **Omarchy Linux** with **Hyprland** (especially modern hybrid laptops such as ASUS TUF / ROG with Intel Raptor Lake + NVIDIA GeForce RTX GPUs), closing the laptop lid often results in the screen failing to turn back on, leaving the user with a permanent black screen or a frozen machine upon opening the lid.

This guide provides:
1. **Root cause analysis** of why the screen failed to wake up.
2. **The clean architecture** of the instant screen-off / screen-on fix (no sleep, no lock screen).
3. **Automated one-click setup** using `fix-lid-screen.sh`.
4. **Manual step-by-step instructions** to apply or inspect each configuration.
5. **Rollback instructions** to restore system defaults if needed.

---

## Root Cause Analysis

When diagnosing the issue on ASUS TUF Gaming F16 hardware (`FX607VUR`), four compounding factors were identified:

1. **Systemd-logind Defaulted to Suspend (`s2idle`)**:
   By default, `/etc/systemd/logind.conf` sets `HandleLidSwitch=suspend`. Closing the lid triggered a full Linux system suspend rather than simply turning off the display.
2. **NVIDIA Driver Sleep Services Were Disabled**:
   On hybrid NVIDIA laptops running Wayland, the proprietary driver requires `nvidia-suspend.service` and `nvidia-resume.service` to preserve VRAM and GPU power states. Because these were disabled, the PCI bus stalled and the kernel hung upon resume:
   ```text
   nvidia-modeset: ACPI reported no NVIDIA native backlight available; attempting to use ACPI backlight.
   PM: suspend exit
   ```
   *(System locked up immediately after this point, requiring a hard power reset).*
3. **Intel Raptor Lake-P Panel Self Refresh 2 (PSR2) Bug**:
   The internal 144Hz panel (`eDP-2`) is driven by the Intel iGPU (`i915`). We verified that `PSR mode: PSR2 enabled` was active with status `SU_STANDBY`. Raptor Lake has a known bug where the panel timing fails to recover after waking from deep sleep states.
4. **Omarchy Clamshell / DPMS Logic**:
   Omarchy's `/usr/share/omarchy/bin/omarchy-system-lid-close` locked the screen via Quickshell, but `/usr/share/omarchy/bin/omarchy-hyprland-monitor-clamshell` only explicitly dispatches `dpms enable` if an external monitor configuration changed (`changed=1`). Without an external monitor, no explicit DPMS wake command was sent.

---

## The Desired Solution

Rather than risking hardware sleep crashes, background task termination, and lock screen delays:
* **Lid Closed:** Display powers completely OFF (`dpms off`).
* **Lid Opened:** Display powers immediately ON (`dpms on`).
* **No Lock Screen:** The desktop is immediately accessible right where you left off.
* **No Suspend / Sleep:** Music, downloads, SSH sessions, and compiles continue uninterrupted.
* **Clamshell Mode Preserved:** If an external monitor is plugged in, closing the lid keeps the external monitor running and only powers down the laptop screen.

---

## Architectural Implementation

### 1. Systemd-logind Drop-In: Disable Sleep on Lid Switch
Instead of modifying the vendor `/etc/systemd/logind.conf` directly, we place a high-priority drop-in file at `/etc/systemd/logind.conf.d/30-lid-ignore.conf`:

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

* **Why it's safe:** Uses systemd's official drop-in architecture.
* **Live Reload:** Reloaded via `sudo systemctl reload systemd-logind` (`Type=notify-reload`), which re-reads configuration live without terminating user sessions or killing GUI apps.

### 2. Standalone Lid Handler Script: `~/.local/bin/omarchy-lid-handler`
A lightweight bash script manages display power states via Hyprland's IPC:

```bash
#!/bin/bash
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
esac
```

### 3. Hyprland User Bindings Override: `~/.config/hypr/bindings.lua`
In Omarchy, system defaults live in `/usr/share/omarchy/default/hypr/` and should never be edited directly. Instead, user overrides are added to `~/.config/hypr/bindings.lua`:

```lua
----------------------------------------------------------------
-- Lid Switch (Display off on close, display on on open - no suspend/lock)
----------------------------------------------------------------
hl.unbind("switch:on:Lid Switch")
hl.unbind("switch:off:Lid Switch")

o.bind("switch:on:Lid Switch", "Turn display off on lid close", "omarchy-lid-handler close", { locked = true })
o.bind("switch:off:Lid Switch", "Turn display on on lid open", "omarchy-lid-handler open", { locked = true })
```

* `hl.unbind`: Removes the default `omarchy-system-lid-close` (which called `omarchy-system-lock`).
* `locked = true`: Ensures Hyprland catches switch events even when the display is powered down or locked.

---

## One-Click Automated Run

To apply the complete fix in one step, execute `fix-lid-screen.sh`:

```bash
cd "$(dirname "$0")"
chmod +x fix-lid-screen.sh
./fix-lid-screen.sh
```

### What the script handles automatically:
1. Prompts for `sudo` to write `/etc/systemd/logind.conf.d/30-lid-ignore.conf`.
2. Reloads `systemd-logind` cleanly.
3. Creates and chmod's `~/.local/bin/omarchy-lid-handler`.
4. Creates a timestamped backup of `~/.config/hypr/bindings.lua`.
5. Checks for idempotency so duplicate bindings are never added.
6. Runs `hyprctl reload` and validates syntax with `hyprctl configerrors`.

---

## Manual Step-by-Step Instructions

If you prefer to apply each step manually:

### Step 1: Configure systemd-logind
```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo bash -c 'cat << "EOF" > /etc/systemd/logind.conf.d/30-lid-ignore.conf
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF'

sudo systemctl reload systemd-logind
```

### Step 2: Install `omarchy-lid-handler`
Create `~/.local/bin/omarchy-lid-handler`, paste the script from section 2 above, and make it executable:
```bash
chmod +x ~/.local/bin/omarchy-lid-handler
```

### Step 3: Update Hyprland Bindings
Append the following block to `~/.config/hypr/bindings.lua`:
```lua
hl.unbind("switch:on:Lid Switch")
hl.unbind("switch:off:Lid Switch")

o.bind("switch:on:Lid Switch", "Turn display off on lid close", "omarchy-lid-handler close", { locked = true })
o.bind("switch:off:Lid Switch", "Turn display on on lid open", "omarchy-lid-handler open", { locked = true })
```

### Step 4: Reload Hyprland
```bash
hyprctl reload
hyprctl configerrors
```

---

## Verification & Testing

1. **Verify Logind Configuration:**
   ```bash
   systemd-analyze cat-config systemd/logind.conf | grep -E "HandleLid"
   ```
   *Expected output:* `HandleLidSwitch=ignore` (along with external power and docked set to ignore).

2. **Verify Hyprland Bindings:**
   ```bash
   hyprctl binds -j | jq '.[] | select(.key | contains("switch"))'
   ```
   *Expected output:* Two bindings for `switch:on:Lid Switch` and `switch:off:Lid Switch` pointing to `omarchy-lid-handler`.

3. **Physical Test:**
   - Close the laptop lid: The display powers off completely within milliseconds.
   - Open the laptop lid: The display powers back on immediately to your active workspace.

---

## How to Rollback / Revert

If you ever want to restore Omarchy's default suspend-on-lid behavior:

1. Remove the logind drop-in:
   ```bash
   sudo rm -f /etc/systemd/logind.conf.d/30-lid-ignore.conf
   sudo systemctl reload systemd-logind
   ```
2. Remove the lid bindings from `~/.config/hypr/bindings.lua` (or restore the `.bak` file).
3. Reload Hyprland:
   ```bash
   hyprctl reload
   ```
4. Optionally remove the handler:
   ```bash
   rm -f ~/.local/bin/omarchy-lid-handler
   ```
