use crate::index::Hit;
use anyhow::{bail, Result};
use std::{
    path::Path,
    process::{Command, Stdio},
};
pub fn command(hit: &Hit, viewer: &str) -> Result<Vec<String>> {
    let p = Path::new(&hit.chunk.path);
    if !p.is_absolute() {
        bail!("只打开绝对文件路径");
    }
    let pdf = p.extension().is_some_and(|e| e.eq_ignore_ascii_case("pdf"));
    let page = hit.chunk.page.unwrap_or(1).to_string();
    Ok(match (viewer, pdf) {
        ("zathura", true) => vec!["zathura".into(), "-P".into(), page, hit.chunk.path.clone()],
        ("okular", true) => vec![
            "okular".into(),
            "--page".into(),
            page,
            hit.chunk.path.clone(),
        ],
        ("auto", true) => {
            let mut url =
                url::Url::from_file_path(p).map_err(|_| anyhow::anyhow!("文件 URL 无效"))?;
            url.set_fragment(Some(&format!("page={page}")));
            vec!["xdg-open".into(), url.to_string()]
        }
        ("auto" | "zathura" | "okular", _) => vec!["xdg-open".into(), hit.chunk.path.clone()],
        _ => bail!("viewer 只支持 auto / zathura / okular"),
    })
}
pub fn open(hit: &Hit, viewer: &str) -> Result<()> {
    if !Path::new(&hit.chunk.path).is_file() {
        bail!("源文件已不可用");
    }
    let args = command(hit, viewer)?;
    Command::new(&args[0])
        .args(&args[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pdf_page_and_spaces_are_argv() {
        let h = Hit {
            chunk: crate::extract::Chunk {
                path: "/tmp/course notes.pdf".into(),
                page: Some(7),
                title: String::new(),
                line_start: 1,
                line_end: 2,
                text: String::new(),
            },
            score: 1.0,
        };
        assert_eq!(
            command(&h, "zathura").unwrap(),
            ["zathura", "-P", "7", "/tmp/course notes.pdf"]
        );
        assert!(command(&h, "auto").unwrap()[1].ends_with("notes.pdf#page=7"));
    }
}
