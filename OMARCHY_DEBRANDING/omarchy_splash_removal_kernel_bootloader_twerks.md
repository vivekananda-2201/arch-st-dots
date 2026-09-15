# Omarchy Linux — Complete Guide to Boot Splash Removal & Verbose TTY Logging

## Overview & Purpose

By default, Omarchy Linux boots silently with a graphical **Plymouth** boot splash that hides kernel messages, systemd service startup logs, and presents a graphical password input box for disk decryption (LUKS).

This guide provides an in-depth, step-by-step explanation of:
1. **How the Omarchy boot stack works** under the hood.
2. **Why and how** the graphical splash suppresses boot logs and controls the decryption prompt.
3. **How to manually remove** the splash and restore a traditional, verbose Linux boot sequence with raw TTY logging and a blinking cursor.
4. **How to automate** this with the included one-click script `remove-splash.sh`.

---

## Architecture: The Omarchy Boot Stack

Omarchy uses a modern Arch-based boot pipeline:

```
[ UEFI Firmware ]
       │
       ▼
[ Limine Bootloader ]  ── reads /boot/limine.conf
       │
       ▼
[ Unified Kernel Image (UKI) ]  ── /boot/EFI/Linux/omarchy_linux.efi
   ├── Embedded Linux Kernel (vmlinuz)
   ├── Embedded Initramfs (built via mkinitcpio)
   └── Embedded Kernel Command Line (cmdline)
       │
       ▼
[ Initramfs Execution ]
   ├── Runs build hooks: base, udev, keyboard, autodetect, kms, encrypt...
   └── Prompts for LUKS Passphrase (Decryption)
       │
       ▼
[ Real Root Mount & Switchroot ]
       │
       ▼
[ systemd Init (PID 1) ]  ── starts services ([ OK ] Started...)
       │
       ▼
[ Display Manager (SDDM) ] ── launches Hyprland session
```

### How the Splash Screen Is Triggered

Two distinct subsystems control the splash and boot visibility:

1. **The Kernel Command Line (`cmdline`)**:
   - `quiet`: Suppresses informational kernel messages (`dmesg`).
   - `splash`: Tells Plymouth to activate the graphical bootsplash on the framebuffer.
   - `loglevel=0`: Suppresses console log levels, displaying only system panic/emergencies.
   - `systemd.show_status=false`: Suppresses the `[ OK ] Started ...` status lines during systemd initialization.
   - `rd.udev.log_level=0`: Mutes udev device discovery messages in the initramfs.
   - `vt.global_cursor_default=0`: Hides the blinking console cursor on the virtual terminal.

2. **The Initramfs Hook Stack (`mkinitcpio`)**:
   - When `plymouth` is included in the `HOOKS=(...)` array in `/etc/mkinitcpio.conf.d/`, the Plymouth daemon and graphics assets are packed directly into the initramfs ramdisk.
   - During boot, the Arch Linux `encrypt` hook checks:
     ```sh
     if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
         plymouth ask-for-password --prompt="A password is required..."
     else
         echo ""
         echo "A password is required to access the root volume:"
         while ! cryptsetup open ...; do sleep 2; done
     fi
     ```
   - If Plymouth is in the initramfs, it intercepts the password prompt and renders the graphical theme.
   - If Plymouth is **not** in the initramfs, the hook falls back to a clean, direct TTY console text prompt:
     ```text
     A password is required to access the root volume:
     ```

---

## Detailed Manual Removal Guide

To completely remove the splash and make boot 100% verbose, changes are required in **two** locations: `mkinitcpio` and `limine`.

### Step 1: Remove Plymouth from Initramfs Hooks (`mkinitcpio`)

Omarchy configures mkinitcpio hooks via drop-in files under `/etc/mkinitcpio.conf.d/`.

1. Check the existing configuration in `/etc/mkinitcpio.conf.d/omarchy_hooks.conf`:
   ```bash
   cat /etc/mkinitcpio.conf.d/omarchy_hooks.conf
   ```
   Notice that `HOOKS` contains `plymouth`:
   ```bash
   HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
   FILES+=(/etc/vconsole.conf)
   ```

2. Remove `plymouth` from that line so `keyboard` comes early (allowing password entry):
   ```bash
   sudo sed -i 's/ plymouth / /g' /etc/mkinitcpio.conf.d/omarchy_hooks.conf
   ```

3. **Make it persistent against system updates**:
   Since `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` is owned by the `omarchy-settings` package, an update may reinstall or overwrite it. To prevent this, create a drop-in file that sorts last (e.g. `zz_no_plymouth.conf`):
   ```bash
   sudo bash -c 'cat << "EOF" > /etc/mkinitcpio.conf.d/zz_no_plymouth.conf
   # Persistent override: Drop plymouth hook to boot in raw TTY mode
   HOOKS=(${HOOKS[@]/plymouth/})
   EOF'
   ```
   *Why this works*: Files in `/etc/mkinitcpio.conf.d/` are sourced in alphabetical order. Because `zz_no_plymouth.conf` is sourced after `omarchy_hooks.conf`, `HOOKS=(${HOOKS[@]/plymouth/})` strips `plymouth` out of the array regardless of future package updates.

---

### Step 2: Remove Silent Boot Flags from the Kernel Command Line (`Limine`)

Omarchy's bootloader entries are managed by `limine-entry-tool`.

1. Check where the silent flags come from:
   Omarchy ships a default drop-in at `/etc/limine-entry-tool.d/omarchy-defaults.conf`:
   ```bash
   KERNEL_CMDLINE[default]+=" quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0"
   ```
   Notice the `+=` operator.

2. Override this in `/etc/default/limine`:
   According to Limine documentation, `/etc/default/limine` has the highest configuration priority. Using `=` (assignment) rather than `+=` (append) completely **replaces** the command line, discarding the drop-in's `quiet splash` values!

3. Inspect your current hardware-specific parameters:
   ```bash
   cat /proc/cmdline
   ```
   Identify your required parameters:
   - `cryptdevice=PARTUUID=...:root` (identifies your encrypted partition)
   - `root=/dev/mapper/root` (mapped root filesystem)
   - `zswap.enabled=0`
   - `rootflags=subvol=@` (Btrfs subvolume)
   - `rw` & `rootfstype=btrfs`
   - `resume=/dev/mapper/root` & `resume_offset=...` (hibernation setup)
   - `rtc_cmos.use_acpi_alarm=1`
   - `initramfs_async=0` (prevents early init mounting races)

4. Edit `/etc/default/limine`:
   ```bash
   sudo nano /etc/default/limine
   ```
   Set `KERNEL_CMDLINE[default]` to your clean parameters (WITHOUT `quiet`, `splash`, `loglevel=0`, `systemd.show_status=false`, `rd.udev.log_level=0`, or `vt.global_cursor_default=0`):

   ```bash
   TARGET_OS_NAME="Omarchy"

   ESP_PATH="/boot"

   KERNEL_CMDLINE[default]="cryptdevice=PARTUUID=YOUR-PARTUUID:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs resume=/dev/mapper/root resume_offset=YOUR-OFFSET rtc_cmos.use_acpi_alarm=1 initramfs_async=0"

   ENABLE_UKI=yes
   CUSTOM_UKI_NAME="omarchy"

   ENABLE_LIMINE_FALLBACK=yes

   FIND_BOOTLOADERS=yes
   BOOT_ORDER="*, *fallback, Snapshots"
   MAX_SNAPSHOT_ENTRIES=5
   SNAPSHOT_FORMAT_CHOICE=5
   ```

---

### Step 3: Rebuild the UKI & Update Limine

In a Unified Kernel Image (UKI) architecture, the kernel command line and the initramfs ramdisk are bundled together into the EFI executable (`/boot/EFI/Linux/omarchy_linux.efi`). 

Therefore, simply changing configuration files has no effect until the UKI is regenerated.

Run:
```bash
sudo limine-update
```
*(Alternatively, `sudo limine-mkinitcpio`)*.

You will see:
1. `Limine EFI update completed successfully.`
2. `Building UKI for linux (...)`
3. `-> Running build hook: [base]`
4. `-> Running build hook: [udev]`
5. `-> Running build hook: [keyboard]`
   *(Notice `plymouth` is NO LONGER in the list of running build hooks!)*
6. `-> Running build hook: [block]`
7. `-> Running build hook: [encrypt]`
8. `Creating unified kernel image: ... -> /boot/EFI/Linux/omarchy_linux.efi`
9. `Updated: /boot/limine.conf`

---

### Step 4: Verify the New Configuration

Before rebooting, verify that the bootloader and UKI received the updated parameters:

```bash
sudo limine-entry-tool --get-cmdline linux
```
Expected output:
```text
cryptdevice=PARTUUID=...:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs resume=... initramfs_async=0
```

Verify `/boot/limine.conf`:
```bash
sudo grep -A 5 "//linux" /boot/limine.conf
```
Ensure the `cmdline:` field does **not** contain `quiet` or `splash`.

---

## One-Click Automated Script (`remove-splash.sh`)

A self-contained, automated script is located in this directory:
```bash
~/Projects/arch-st-dots/OMARCHY_DEBRANDING/remove-splash.sh
```

### How to Run It
```bash
cd ~/Projects/arch-st-dots/OMARCHY_DEBRANDING
./remove-splash.sh
```

### What the Script Does Automatically:
1. Validates root/sudo privileges.
2. Creates `/etc/mkinitcpio.conf.d/zz_no_plymouth.conf` to persistently eliminate Plymouth from initramfs.
3. Cleans `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` (with automatic timestamped backup).
4. Dynamically reads your system's UUIDs and boot parameters from `/etc/default/limine` or `/proc/cmdline`.
5. Removes `quiet`, `splash`, `loglevel=0`, `systemd.show_status=false`, `rd.udev.log_level=0`, and `vt.global_cursor_default=0`.
6. Preserves all critical disk encryption, Btrfs subvolume, swap, and hibernation offsets.
7. Automatically invokes `limine-update` to rebuild `/boot/EFI/Linux/omarchy_linux.efi` and sync `/boot/limine.conf`.
8. Verifies the generated parameters and reports status.

You can safely re-run this script anytime — especially after major Omarchy system updates or fresh reinstalls.

---

## FAQ & Precautions

### Why not simply run `sudo pacman -R plymouth`?
In Omarchy, the package `omarchy-settings` declares `plymouth` as a hard dependency. Attempting to remove Plymouth via `pacman -R` will fail dependency resolution, and using `pacman -Rdd` will break package manager integrity during `omarchy update`. 

Leaving the package installed on disk but dropping it from `mkinitcpio` and removing `splash` from `cmdline` is the cleanest, most stable solution. Plymouth will remain completely inactive and never load.

### How do I restore the graphical splash if I change my mind?
1. Remove the override drop-in:
   ```bash
   sudo rm /etc/mkinitcpio.conf.d/zz_no_plymouth.conf
   ```
2. Restore `/etc/default/limine` from its backup (e.g. `/etc/default/limine.bak.*`):
   ```bash
   sudo cp /etc/default/limine.bak.<timestamp> /etc/default/limine
   ```
3. Rebuild the UKI:
   ```bash
   sudo limine-update
   ```
