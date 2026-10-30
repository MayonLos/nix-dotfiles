# mayon-ui

Shared One Dark constants, grapheme-safe Unicode cell clipping and byte/latency formatting;
status chrome, numbered tabs, subtle selected table rows with a blue left
marker, rounded thin borders, confirmation/help/input overlays and footers. Hints retain complete key/action pairs and fall back to `? 更多`;
tables clip each cell before Ratatui rendering rather than cutting a word at the edge.
`terminal()` owns raw mode, alternate screen and mouse cleanup. `Refresh<T>`
allows one background future at a time and returns completions over a channel.

`build.rs` reads `MAYON_TUI_PALETTE` supplied by Nix or the repository's public
One Dark palette for plain Cargo. It creates constants in Cargo's OUT_DIR;
no generated colors are committed. There is no runtime configuration or state.

Run `cargo test -p mayon-ui` from the workspace; all tools link this crate.
Change primitives here, keep application state in each tool, then inspect
all tools at wide and approximately 90-column sizes in real Kitty. Prefer
channel completion values to shared mutable rendering state. A new widget
should have a small public API and must clip/wrap terminal cell widths safely.
