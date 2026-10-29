use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=CLASHTUI_PALETTE");
    // Nix passes the selected entity palette. Local cargo builds read the same
    // public repository palette; there is no second embedded color scheme.
    let colors: serde_json::Value = if let Ok(json) = env::var("CLASHTUI_PALETTE") {
        serde_json::from_str(&json).expect("CLASHTUI_PALETTE must be JSON")
    } else {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../appearance/appearance/onedark.nix");
        println!("cargo:rerun-if-changed={}", path.display());
        let source = fs::read_to_string(path).expect("repository One Dark palette is required");
        let mut map = serde_json::Map::new();
        for line in source.lines() {
            if let Some((key, value)) = line.trim().split_once(" = \"#") {
                map.insert(key.into(), format!("#{}", &value[..6]).into());
            }
        }
        map.into()
    };
    let mut generated = String::new();
    for role in [
        "bg",
        "surface",
        "selection",
        "border",
        "fg",
        "muted",
        "blue",
        "green",
        "yellow",
        "red",
        "cyan",
        "brightFg",
    ] {
        let hex = colors[role].as_str().expect("palette role missing");
        let rgb = u32::from_str_radix(hex.trim_start_matches('#'), 16).expect("hex color");
        generated.push_str(&format!(
            "pub const {}: Color = Color::Rgb({}, {}, {});\n",
            role.to_uppercase(),
            rgb >> 16,
            (rgb >> 8) & 255,
            rgb & 255
        ));
    }
    fs::write(
        PathBuf::from(env::var("OUT_DIR").unwrap()).join("palette.rs"),
        generated,
    )
    .unwrap();
}
