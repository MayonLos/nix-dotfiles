# Screenshot & Pin-to-Screen Design

## Overview

Snipaste-style screenshot workflow for Wayland/niri: interactive region capture with annotation, clipboard integration, and pin-to-screen (floating always-on-top image window).

## Requirements

- **Print**: Select region → annotate (arrows, text, shapes) → copy to clipboard + auto-save to `~/Pictures/Screenshots/`
- **Ctrl+Shift+Print**: Select region → annotate → pin to screen as floating always-on-top window
- Pinned windows must be movable, resizable, and closeable via keyboard

## Tool Selection

| Tool | Purpose | Rationale |
|------|---------|-----------|
| grim | Screenshot capture | Wayland-native, wlroots-compatible |
| slurp | Interactive region selection | Tied to wlroots, shows coordinates during drag |
| satty | Post-capture annotation | Modern GTK4, supports arrows/text/shapes/blur/highlight |
| swayimg | Pin-to-screen viewer | Lightweight, Wayland-native, scriptable |

All are packaged in nixpkgs. No Qt dependency. Each tool does one thing.

## Architecture

```
Print:
  slurp → grim → stdout pipe → satty (annotate) → copy to clipboard + save to ~/Pictures

Ctrl+Shift+Print:
  slurp → grim → stdout pipe → satty (annotate) → save to /tmp/screenshots/
                                                  → swayimg (floating, always-on-top)
```

## Implementation

### Packages

Add to `modules/home/packages.nix`: grim, slurp, satty, swayimg.

### Scripts

Two small shell scripts under `modules/home/services/` (or inline in niri keybinds via `writeShellScriptBin`):

**screenshot-region**: `grim -g "$(slurp -d)" - | satty -f - --output "$HOME/Pictures/Screenshots/screenshot-$(date).png" --copy-command wl-copy`

**screenshot-pin**: generates a timestamped filename first, then pipes grim → satty with `--output` set to that file, and after satty exits, launches `swayimg` on the saved file. Uses a variable so the filename is deterministic through the chain, not a glob.

### Niri Keybinds

- `Print` → spawn screenshot-region script
- `Ctrl+Shift+Print` → spawn screenshot-pin script

### Niri Window Rules

For swayimg windows:
- `open-floating = true`
- `default-column-width = { proportion = 0.5; }`
- Floating geometry: centered, initial size based on image aspect ratio

The pin window should be closeable via `Mod+Shift+C` (niri's close-window, already bound).

## Error Handling

- `slurp`: ESC cancels region selection; script exits cleanly
- `grim`: Pipe to `satty` handles stream errors (satty shows error if no input)
- `satty`: Close/Cancel exits without saving or copying
- `swayimg`: Window rule ensures it always floats even if rule evaluation is delayed

## Files Changed

| File | Change |
|------|--------|
| `modules/home/packages.nix` | Add grim, slurp, satty, swayimg |
| `modules/home/wm/niri/keybinds.nix` | Replace niri built-in screenshot binds with script spawns |
| `modules/home/wm/niri/rules.nix` | Add swayimg floating window rule |
| `modules/home/programs/apps/screenshot.nix` | (new) Script definitions + packages |
