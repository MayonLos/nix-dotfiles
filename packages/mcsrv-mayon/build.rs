use std::{env, fs, path::PathBuf};
fn main() {
    println!("cargo:rerun-if-env-changed=MAYON_TUI_PALETTE");
    let keys = [
        ("BG", "bg"),
        ("DEEP", "deep"),
        ("SURFACE", "surface"),
        ("SELECTION", "selection"),
        ("BORDER", "border"),
        ("FG", "fg"),
        ("BRIGHT_FG", "brightFg"),
        ("MUTED", "muted"),
        ("BLUE", "blue"),
        ("GREEN", "green"),
        ("YELLOW", "yellow"),
        ("RED", "red"),
        ("CYAN", "cyan"),
        ("PURPLE", "purple"),
        ("ORANGE", "orange"),
    ];
    let json: Option<serde_json::Value> = env::var("MAYON_TUI_PALETTE")
        .ok()
        .map(|text| serde_json::from_str(&text).expect("palette JSON"));
    let source = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap())
        .join("../../aspects/appearance/appearance/onedark.nix");
    let nix = if json.is_none() {
        println!("cargo:rerun-if-changed={}", source.display());
        fs::read_to_string(source).expect("shared One Dark palette")
    } else {
        String::new()
    };
    let mut generated = String::from("use ratatui::style::Color;\n");
    for (constant, key) in keys {
        let value = if let Some(ref json) = json {
            json[key].as_str().expect("palette color").to_owned()
        } else {
            let prefix = format!("{key} = \"");
            nix.lines()
                .find_map(|line| {
                    line.trim()
                        .strip_prefix(&prefix)
                        .and_then(|v| v.strip_suffix("\";"))
                        .map(str::to_owned)
                })
                .expect("shared palette literal")
        };
        assert!(
            value.starts_with('#') && value.len() == 7,
            "palette hex RGB"
        );
        let mut channels = Vec::new();
        for n in 0..3 {
            channels
                .push(u8::from_str_radix(&value[1 + n * 2..3 + n * 2], 16).expect("palette RGB"));
        }
        generated.push_str(&format!(
            "pub const {constant}: Color = Color::Rgb({}, {}, {});\n",
            channels[0], channels[1], channels[2]
        ));
    }
    fs::write(
        PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("palette.rs"),
        generated,
    )
    .expect("write palette");
}
