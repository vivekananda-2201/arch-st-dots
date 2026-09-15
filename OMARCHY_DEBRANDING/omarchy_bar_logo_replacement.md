# Omarchy Status Bar — Replace Omarchy Logo with Arch Linux Logo

## Overview & Goal

In Omarchy Linux, the top Wayland status bar (often referred to as Waybar, but technically rendered by **Quickshell**) displays a custom Omarchy brand icon on the far left.

This guide explains:
1. **How the status bar widget system works** in Omarchy.
2. **Why and how** to safely customize the bar button without modifying system files in `/usr/share/omarchy/`.
3. **How to manually replace** the Omarchy icon with the official Arch Linux logo (``) while preserving all native menu functionality.
4. **How to automate** this change anytime with the provided `replace-bar-logo.sh` script.

---

## Architectural Details: How the Bar Button Works

The status bar is defined in `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "left": [
        {
          "id": "omarchy.menu"
        }
      ],
      ...
    }
  }
}
```

The default menu widget code lives in `/usr/share/omarchy/shell/plugins/menu/BarWidget.qml`:
```qml
WidgetButton {
  id: button
  anchors.fill: parent
  bar: root.bar
  text: "\ue900"            // <-- Custom Omarchy glyph
  fontFamily: "omarchy"     // <-- Proprietary font file
  ...
}
```

### Why You Must NOT Edit `/usr/share/omarchy/`
Any edits inside `/usr/share/omarchy/` will be immediately erased on the next `omarchy update`. 

Instead, Omarchy provides a dedicated user plugin mechanism in `~/.config/omarchy/plugins/`. Any plugin located here survives system updates and can be cleanly referenced in `~/.config/omarchy/shell.json`.

---

## The Clean Solution: Dedicated Bar Widget

Rather than cloning the entire multi-thousand-line menu system (`Menu.qml`, `MenuModel.js`, etc.), we create a lightweight user plugin that **only** provides a `bar-widget`.

* **The Bar Button:** Handled by our custom user plugin (`<user>.menu`), displaying the Arch Linux Nerd Font glyph (``).
* **The Menu Backend:** Continues to be handled by Omarchy's native `omarchy.menu` engine. All keyboard shortcuts (`Super + Space`, `Super + Alt + Space`), IPC commands, and submenus work 100% as intended.

---

## Manual Step-by-Step Guide

### Step 1: Create the User Plugin Directory

Replace `<username>` with your actual username (e.g., `vicky`):
```bash
mkdir -p ~/.config/omarchy/plugins/<username>.menu
```

---

### Step 2: Create `manifest.json`

Create `~/.config/omarchy/plugins/<username>.menu/manifest.json`:
```json
{
  "schemaVersion": 1,
  "id": "<username>.menu",
  "name": "Arch Linux menu button",
  "version": "1.0.0",
  "author": "<username>",
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
```

*Note: Notice `kinds` only lists `"bar-widget"`. Because it does not claim the `"menu"` kind, it will not conflict with or disable the native menu.*

---

### Step 3: Create `BarWidget.qml`

Create `~/.config/omarchy/plugins/<username>.menu/BarWidget.qml`:
```qml
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
```

*Key points:*
* `text: ""`: The Arch Linux logo (Unicode `\uf303` from Nerd Fonts).
* `fontFamily` is omitted, causing `WidgetButton` to automatically inherit the bar's default monospace font (`JetBrainsMono Nerd Font`).
* Left-click triggers `omarchy.menu` toggle.
* Right-click launches your default terminal (`xdg-terminal-exec`).

---

### Step 4: Update `~/.config/omarchy/shell.json`

Edit `~/.config/omarchy/shell.json`. Under `"bar" -> "layout" -> "left"`, change the widget ID from `"omarchy.menu"` to `"<username>.menu"`:

```json
      "left": [
        {
          "id": "<username>.menu"
        }
      ],
```

---

### Step 5: Reload the Status Bar

Tell the Omarchy shell to rescan its plugins and reload the bar:
```bash
omarchy-shell shell rescanPlugins
omarchy restart shell
```

The Arch Linux logo will now appear on your top status bar.

---

## One-Click Automated Script (`replace-bar-logo.sh`)

A self-contained script is included in this repository:
```bash
~/Projects/arch-st-dots/OMARCHY_DEBRANDING/replace-bar-logo.sh
```

### How to Run:
```bash
cd ~/Projects/arch-st-dots/OMARCHY_DEBRANDING
./replace-bar-logo.sh
```

### What it does automatically:
1. Detects your username and creates `~/.config/omarchy/plugins/<user>.menu/`.
2. Generates `manifest.json` and `BarWidget.qml` with the Arch Linux glyph.
3. Creates a timestamped backup of `~/.config/omarchy/shell.json`.
4. Uses `jq` to update your bar layout cleanly.
5. Reloads Quickshell immediately so the new logo appears without logging out.

---

## How to Revert to Default

If you ever want to switch back to the original Omarchy icon:
1. Edit `~/.config/omarchy/shell.json` and change `"<username>.menu"` back to `"omarchy.menu"`.
2. Run:
   ```bash
   omarchy restart shell
   ```
3. (Optional) Delete the custom plugin directory:
   ```bash
   rm -rf ~/.config/omarchy/plugins/<username>.menu
   ```
