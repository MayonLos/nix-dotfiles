# Screenshot & Pin-to-Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Snipaste-style screenshot workflow: Print for annotated region screenshots, Ctrl+Shift+Print for annotated screenshot pinned as floating window.

**Architecture:** Two shell scripts (writeShellScriptBin) — `screenshot-region` for capture+annotate+copy+save, `screenshot-pin` for capture+annotate+pin. Spawned via niri keybinds. swayimg windows get floating+always-on-top via niri window rules.

**Tech Stack:** grim, slurp, satty, swayimg, wl-clipboard, writeShellScriptBin

---

## File Structure

| File | Responsibility |
|------|---------------|
| `modules/home/packages.nix` | Add grim, slurp, satty, swayimg packages |
| `modules/home/programs/apps/screenshot.nix` | (new) Define `screenshot-region` and `screenshot-pin` scripts |
| `modules/home/wm/niri/keybinds.nix` | Replace niri built-in screenshot binds with script spawns |
| `modules/home/wm/niri/rules.nix` | Add swayimg floating window rule |

---

### Task 1: Add screenshot tool packages

**Files:**
- Modify: `modules/home/packages.nix`

- [ ] **Step 1: Add grim, slurp, satty, swayimg to home.packages**

In `modules/home/packages.nix`, add the four new packages alongside existing media-related packages:

```nix
# Add after brightnessctl line (or similar location):
grim
slurp
satty
swayimg
```

The exact location is within the `home.packages = with pkgs; [` block, after `brightnessctl` (line 29):

```nix
brightnessctl
pamixer
pavucontrol
playerctl
mangohud
# Screenshot & pin-to-screen
grim
slurp
satty
swayimg
```

- [ ] **Step 2: Verify nix eval**

Run: `nix eval .#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.home.packages --no-warn-dirty 2>&1 | grep -E "grim|slurp|satty|swayimg"`

Expected: derivation paths for all four packages appear in output.

- [ ] **Step 3: Commit**

```bash
git add modules/home/packages.nix
git commit -m "feat: add grim, slurp, satty, swayimg for screenshot workflow"
```

---

### Task 2: Create screenshot scripts

**Files:**
- Create: `modules/home/programs/apps/screenshot.nix`

- [ ] **Step 1: Create screenshot.nix with both scripts**

```nix
{
  pkgs,
  ...
}:

let
  screenshot-region = pkgs.writeShellScriptBin "screenshot-region" ''
    set -euo pipefail

    GRIM="${pkgs.grim}/bin/grim"
    SLURP="${pkgs.slurp}/bin/slurp"
    SATTY="${pkgs.satty}/bin/satty"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    DATE="${pkgs.coreutils}/bin/date"

    SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
    "$MKDIR" -p "$SCREENSHOT_DIR"

    FILE="$SCREENSHOT_DIR/screenshot-$("$DATE" +%Y%m%d-%H%M%S).png"

    GEOM=$("$SLURP" -d) || exit 0
    "$GRIM" -g "$GEOM" - | "$SATTY" -f - --output "$FILE" --copy-command "$WL_COPY"
  '';

  screenshot-pin = pkgs.writeShellScriptBin "screenshot-pin" ''
    set -euo pipefail

    GRIM="${pkgs.grim}/bin/grim"
    SLURP="${pkgs.slurp}/bin/slurp"
    SATTY="${pkgs.satty}/bin/satty"
    SWAYIMG="${pkgs.swayimg}/bin/swayimg"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    DATE="${pkgs.coreutils}/bin/date"

    PIN_DIR="/tmp/niri-pins"
    "$MKDIR" -p "$PIN_DIR"

    FILE="$PIN_DIR/pin-$("$DATE" +%Y%m%d-%H%M%S).png"

    GEOM=$("$SLURP" -d) || exit 0
    "$GRIM" -g "$GEOM" - | "$SATTY" -f - --output "$FILE" --copy-command "$WL_COPY"

    if [ -f "$FILE" ]; then
      "$SWAYIMG" "$FILE"
    fi
  '';
in
{
  home.packages = [
    screenshot-region
    screenshot-pin
  ];
}
```

- [ ] **Step 2: Verify nix eval**

Run: `nix eval .#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.home.packages --no-warn-dirty 2>&1 | grep -E "screenshot-region|screenshot-pin"`

Expected: derivation paths for both scripts appear.

- [ ] **Step 3: Commit**

```bash
git add modules/home/programs/apps/screenshot.nix
git commit -m "feat: add screenshot-region and screenshot-pin scripts"
```

---

### Task 3: Update niri keybinds

**Files:**
- Modify: `modules/home/wm/niri/keybinds.nix:207-211`

- [ ] **Step 1: Replace built-in screenshot binds with script spawns**

Replace the three existing screenshot binds (lines 207-211):

```nix
# Before:
"Print".action.screenshot = {
  show-pointer = false;
};
"Alt+Print".action.screenshot-window = { };
"Ctrl+Print".action.screenshot-screen = {
  show-pointer = false;
};
```

With:

```nix
"Print" = {
  action = spawn "screenshot-region";
  allow-when-locked = false;
};
"Ctrl+Shift+Print" = {
  action = spawn "screenshot-pin";
  allow-when-locked = false;
};
```

Keep `Alt+Print` and `Ctrl+Print` for niri built-in window/screen screenshots as fallback.

- [ ] **Step 2: Verify nix eval**

Run: `nix eval .#nixosConfigurations.nixos-btw.config.programs.niri.settings.binds --no-warn-dirty 2>&1 | grep -E "Print|screenshot"`

Expected: should reference screenshot-region and screenshot-pin scripts.

- [ ] **Step 3: Commit**

```bash
git add modules/home/wm/niri/keybinds.nix
git commit -m "feat: bind Print to screenshot-region, Ctrl+Shift+Print to screenshot-pin"
```

---

### Task 4: Add swayimg window rule

**Files:**
- Modify: `modules/home/wm/niri/rules.nix`

- [ ] **Step 1: Add floating window rule for swayimg**

Add a window rule for swayimg to open in floating mode:

In `modules/home/wm/niri/rules.nix`, add to the `window-rules` list after the existing foot rule (line 19):

```nix
{
  matches = [ { app-id = "swayimg"; } ];
  open-floating = true;
  default-column-width = { proportion = 0.5; };
  focus-ring-width = 0;
  border = {
    width = 2;
    active-color = "#61afef";
    inactive-color = "#3b4252";
  };
}
```

- [ ] **Step 2: Verify nix eval**

Run: `nix eval .#nixosConfigurations.nixos-btw.config.programs.niri.settings.window-rules --no-warn-dirty 2>&1`

Expected: window rules list includes swayimg entry with open-floating = true.

- [ ] **Step 3: Commit**

```bash
git add modules/home/wm/niri/rules.nix
git commit -m "feat: add swayimg floating window rule for pin-to-screen"
```

---

### Task 5: End-to-end verification

- [ ] **Step 1: Rebuild NixOS**

```bash
sudo nixos-rebuild switch --flake /home/mayon/nix-dotfiles#nixos-btw
```

- [ ] **Step 2: Restart niri session**

Log out and back in, or restart niri.

- [ ] **Step 3: Test Print (screenshot-region)**

Press Print → slurp region selector appears → drag to select region → satty annotation UI appears → add an arrow or text → confirm (Enter/click checkmark) → screenshot saved to `~/Pictures/Screenshots/` and copied to clipboard → paste somewhere to verify.

- [ ] **Step 4: Test Ctrl+Shift+Print (screenshot-pin)**

Press Ctrl+Shift+Print → same flow as above → after confirming in satty → swayimg window appears as a floating overlay → window can be moved, resized → close with Mod+Shift+C.

- [ ] **Step 5: Verify pin windows are floating**

Check that swayimg windows: float above tiled windows, can be freely moved, are not tiled into a column.
