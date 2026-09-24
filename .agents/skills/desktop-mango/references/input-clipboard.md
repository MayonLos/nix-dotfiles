# Input method and clipboard

## fcitx5 sizing

The Wayland and X11 candidate windows use different scaling paths. Native Wayland clients use fractional-scale information; the X11 path depends on `PerScreenDPI = "False"` and a working `Xft.dpi` resource merge. `modules/home/base/input-method.nix` and `xresources.nix` configure these halves. Avoid adding `ForceWaylandDPI` without measuring the actual client path; it can double-apply scale.

Determine whether the affected app is Wayland or XWayland at the time of failure. For X clients compare `xwininfo -root -tree` with `mmsg get all-clients`; `xdpyinfo` alone does not show per-window scaling. Check `xrdb -query` for the resource database and inspect the active fcitx5 configuration.

## Clipboard

`modules/home/services/clipboard.nix` bridges Wayland and X11 selections; `cliphist.nix` separately records Wayland clipboard history. Test both directions directly with `wl-paste` and `xclip`, then check the bridge and history user units. A client may use different protocols for windows, IME, and clipboard, so inspect that client's current process/connection behavior before attributing a copy failure to the bridge or changing its platform flags.

First identify the source and destination selection protocols. X11-to-X11
paste can remain within the X11 selection; if `xclip` already reads the expected
payload there, inspect the target app before blaming a cross-protocol bridge.
History recording is not required for clipboard transfer. Check history units
when the symptom is missing history, not as proof that ordinary paste works.

Known current supervision caveat: the bridge waits on both watcher PIDs in one `wait` command. If one watcher exits while the other stays alive, the service may remain active without that direction. Consider this when changing restart behavior; do not claim that a specific client's copy always follows one path.

Preserve the bounded clipboard reads: a selection owner can disappear mid-transfer,
and a blocked read stalls later events because the Wayland watcher runs callbacks
serially. Preserve the shared hash used to suppress feedback between directions.
Select offered MIME types, not a type guessed only from bytes or filenames, so
image copies do not degrade into paths.

Inspect `cliphist list` before blaming the history viewer. An empty database
suggests checking the text/image watcher units; a populated one points to the
viewer path. For a dependency report, inspect the service's effective PATH:
writeShellApplication may inherit commands not listed in runtimeInputs.
