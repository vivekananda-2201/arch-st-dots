
# Omarchy — Restore Traditional Linux Boot Logs

## Goal

Remove Omarchy's graphical boot splash and restore visible:

- LUKS/initramfs messages
- Linux kernel messages
- systemd status messages
- traditional TTY-style boot output

Instead of:

    UEFI
      ↓
    Limine
      ↓
    Plymouth / Omarchy splash
      ↓
    systemd
      ↓
    Display Manager

Use:

    UEFI
      ↓
    Limine
      ↓
    LUKS / initramfs
      ↓
    Kernel + systemd logs
      ↓
    Hyprland

---

## Important: My Omarchy Boot Stack

This installation uses:

- Limine
- Unified Kernel Image (UKI)
- mkinitcpio
- `limine-mkinitcpio-hook`
- Plymouth
- Btrfs
- encrypted root filesystem

The UKI is located at:

    /boot/EFI/Linux/omarchy_linux.efi

Do NOT manually edit this `.efi` file.

It is generated automatically.

---

# 1. Back Up Limine Configuration

Before changing anything:

    sudo cp /etc/default/limine /etc/default/limine.backup

Verify:

    ls -l /etc/default/limine*

If something goes wrong, the original configuration can be restored:

    sudo cp /etc/default/limine.backup /etc/default/limine

---

# 2. Inspect Current Kernel Parameters

Check:

    cat /proc/cmdline

Typical Omarchy configuration may contain:

    quiet
    splash
    loglevel=0
    systemd.show_status=false
    rd.udev.log_level=0

These suppress boot output.

---

# 3. Find Where the Parameters Come From

Check:

    grep -R "quiet\|splash\|systemd.show_status\|rd.udev.log_level\|loglevel" \
        /etc/default/limine /etc/limine* 2>/dev/null

The relevant configuration is normally:

    /etc/default/limine

For this setup, the line originally looked like:

    KERNEL_CMDLINE[default]+=" quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0"

---

# 4. Edit `/etc/default/limine`

Open it with any editor available on the system.

For example:

    sudo vim /etc/default/limine

or:

    sudo nano /etc/default/limine

Remove:

    quiet
    splash
    loglevel=0
    systemd.show_status=false
    rd.udev.log_level=0

Keep:

    vt.global_cursor_default=0

if you want to keep the cursor hidden during boot.

The resulting line can simply be:

    KERNEL_CMDLINE[default]+=" vt.global_cursor_default=0"

IMPORTANT:

Do NOT remove parameters required for the system to boot, such as:

    cryptdevice=...
    root=...
    rootflags=...
    rootfstype=...
    rw
    resume=...

Those are unrelated to the graphical splash.

---

# 5. Regenerate the Omarchy UKI

Changing `/etc/default/limine` does NOT automatically modify the
already-generated UKI.

Regenerate it with:

    sudo limine-mkinitcpio

You should see something similar to:

    Building UKI for linux (...)
    ...
    Creating unified kernel image
    ...
    UKI stored in /boot/EFI/Linux/omarchy_linux.efi
    Updated: /boot/limine.conf

Warnings about optional firmware modules may appear.

For example:

    Possibly missing firmware for module: ...

Do not automatically assume these warnings are related to the
boot-splash change.

---

# 6. Verify Before Rebooting

Check:

    sudo bootctl list

Look at the `options:` line.

It should NO LONGER contain:

    quiet
    splash
    loglevel=0
    systemd.show_status=false
    rd.udev.log_level=0

It should still contain your important boot parameters, such as:

    cryptdevice=...
    root=/dev/mapper/root
    rootflags=subvol=@
    rw
    rootfstype=btrfs
    resume=...

Example:

    options: rtc_cmos.use_acpi_alarm=1
    resume=/dev/mapper/root
    resume_offset=...
    vt.global_cursor_default=0
    cryptdevice=...
    root=/dev/mapper/root
    ...

---

# 7. Reboot

Once `bootctl list` shows the new parameters:

    sudo reboot

After reboot, verify the running kernel:

    cat /proc/cmdline

The old suppression parameters should now be gone.

---

# Expected Result

Instead of:

    [ Omarchy graphical splash ]

you should see something closer to:

    LUKS password prompt
    ↓
    Linux kernel output
    ↓
    systemd [ OK ] messages
    ↓
    services starting
    ↓
    Hyprland

---

# Important: Plymouth Is Still Installed

After removing `splash`, you may still see:

    -> Running build hook: [plymouth]

when running:

    sudo limine-mkinitcpio

This is NOT necessarily a problem.

Plymouth can remain installed and included in the initramfs.

Do NOT immediately uninstall Plymouth just because the hook appears.

The important change is removing:

    splash

from the kernel command line.

Only remove/disable Plymouth separately if you specifically want
Plymouth completely gone from the boot stack.

---

# IMPORTANT Precautions

## 1. Do not edit the UKI manually

Do NOT modify:

    /boot/EFI/Linux/omarchy_linux.efi

It is generated automatically and will be replaced during future
kernel/UKI regeneration.

Always modify the source configuration:

    /etc/default/limine

then regenerate:

    sudo limine-mkinitcpio


## 2. Do not remove boot-critical parameters

Never blindly delete parameters such as:

    cryptdevice=...
    root=...
    rootflags=...
    rootfstype=...
    rw
    resume=...

These may be required for your encrypted/Btrfs installation to boot.


## 3. Always keep a backup

Before modifying Limine:

    sudo cp /etc/default/limine /etc/default/limine.backup

If necessary:

    sudo cp /etc/default/limine.backup /etc/default/limine

Then regenerate:

    sudo limine-mkinitcpio


## 4. Verify before rebooting

Always run:

    sudo bootctl list

before rebooting.

Make sure the generated UKI contains your required
`cryptdevice`, `root`, Btrfs and resume parameters.


## 5. Keep a recovery method available

Because this system uses:

    Limine + UKI + encrypted root + Btrfs

keep your Omarchy/Arch installation USB available until you are
comfortable recovering the system.

If the system fails to boot, you can boot the USB and repair the
installation from a live environment.


# Quick Version

For future reinstalls:

    sudo cp /etc/default/limine /etc/default/limine.backup

Edit:

    sudo vim /etc/default/limine

Remove:

    quiet
    splash
    loglevel=0
    systemd.show_status=false
    rd.udev.log_level=0

Keep your:

    cryptdevice
    root
    rootflags
    rootfstype
    rw
    resume

Then:

    sudo limine-mkinitcpio

Verify:

    sudo bootctl list

Then:

    sudo reboot

After boot:

    cat /proc/cmdline




## Quick version

- For your notes, the entire procedure boils down to:

```
sudo cp /etc/default/limine /etc/default/limine.backup

sudo nvim /etc/default/limine
# Remove:
# quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0

sudo limine-mkinitcpio

sudo bootctl list

sudo reboot
```
