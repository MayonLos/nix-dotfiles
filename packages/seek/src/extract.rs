//! Bounded text extraction for seek. This module never walks directories: callers
//! provide one explicitly selected file at a time.
use anyhow::{bail, Context, Result};
use quick_xml::{events::Event, Reader};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Read,
    path::Path,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const MAX_ARCHIVE_ENTRIES: usize = 4096;
const MAX_ARCHIVE_BYTES: u64 = 128 * 1024 * 1024;
const MAX_XML_BYTES: u64 = 32 * 1024 * 1024;
const MAX_CHARS_PER_CHUNK: usize = 700;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Chunk {
    pub path: String,
    pub page: Option<u32>,
    pub title: String,
    pub line_start: usize,
    pub line_end: usize,
    pub text: String,
}

pub fn extract(path: &Path, ocr: bool, max_bytes: u64) -> Result<Vec<Chunk>> {
    let metadata =
        fs::symlink_metadata(path).with_context(|| format!("stat {}", path.display()))?;
    if !metadata.file_type().is_file() {
        bail!("not a regular file: {}", path.display());
    }
    if metadata.len() > max_bytes {
        bail!("file exceeds configured size limit: {}", path.display());
    }
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    match ext.as_str() {
        "pdf" => extract_pdf(path, ocr),
        "docx" | "pptx" | "xlsx" => extract_ooxml(path, &ext),
        _ => {
            let mut content = String::new();
            fs::File::open(path)?
                .take(max_bytes.saturating_add(1))
                .read_to_string(&mut content)
                .with_context(|| format!("read UTF-8 {}", path.display()))?;
            if content.len() as u64 > max_bytes {
                bail!("file grew beyond configured size limit while reading");
            }
            Ok(chunk_text(path, None, None, &content))
        }
    }
}

fn chunk_text(path: &Path, page: Option<u32>, title_hint: Option<&str>, text: &str) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let mut title = title_hint.unwrap_or_default().to_owned();
    let mut pending = String::new();
    let mut start = 1usize;
    let mut last_line = 1usize;
    let flush = |pending: &mut String,
                 start: usize,
                 end: usize,
                 title: &String,
                 chunks: &mut Vec<Chunk>| {
        let value = pending.trim();
        if !value.is_empty() {
            chunks.push(Chunk {
                path: path.display().to_string(),
                page,
                title: title.clone(),
                line_start: start,
                line_end: end,
                text: value.to_owned(),
            });
        }
        pending.clear();
    };

    for (line_index, line) in text.lines().enumerate() {
        let line_no = line_index + 1;
        let trimmed = line.trim();
        if title.is_empty()
            && (trimmed.starts_with('#') || (trimmed.starts_with('[') && trimmed.ends_with(']')))
        {
            title = trimmed
                .trim_start_matches('#')
                .trim()
                .trim_matches(['[', ']'])
                .to_owned();
        }
        let mut fragment = String::new();
        let mut fragment_len = 0usize;
        for ch in line.chars() {
            if fragment_len >= MAX_CHARS_PER_CHUNK {
                if !pending.is_empty() {
                    flush(&mut pending, start, last_line, &title, &mut chunks);
                }
                chunks.push(Chunk {
                    path: path.display().to_string(),
                    page,
                    title: title.clone(),
                    line_start: line_no,
                    line_end: line_no,
                    text: std::mem::take(&mut fragment),
                });
                start = line_no;
                fragment_len = 0;
            }
            fragment.push(ch);
            fragment_len += 1;
        }
        let needed = fragment.chars().count() + usize::from(!pending.is_empty());
        if !pending.is_empty() && pending.chars().count() + needed > MAX_CHARS_PER_CHUNK {
            flush(&mut pending, start, last_line, &title, &mut chunks);
            start = line_no;
        }
        if !pending.is_empty() {
            pending.push('\n');
        }
        pending.push_str(&fragment);
        last_line = line_no;
    }
    if !pending.is_empty() {
        flush(&mut pending, start, last_line, &title, &mut chunks);
    }
    chunks
}

fn extract_pdf(path: &Path, ocr: bool) -> Result<Vec<Chunk>> {
    let tmp = tempfile::Builder::new().prefix("seek-pdf-").tempdir()?;
    let extracted = tmp.path().join("text.txt");
    let child = Command::new("pdftotext")
        .args(["-layout", "-enc", "UTF-8"])
        .arg(path)
        .arg(&extracted)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("pdftotext is required to index PDF files (install poppler)")?;
    let output = run_timeout(child, Duration::from_secs(60), "pdftotext")?;
    if !output.status.success() {
        bail!("pdftotext failed for {}", path.display());
    }
    let metadata = fs::metadata(&extracted)?;
    if metadata.len() > MAX_ARCHIVE_BYTES {
        bail!("extracted PDF text exceeds 128 MiB");
    }
    let text = fs::read_to_string(extracted).context("pdftotext produced invalid UTF-8")?;
    let mut pages = Vec::new();
    for (index, page_text) in split_pdf_pages(&text).into_iter().enumerate() {
        let page_no = index as u32 + 1;
        if page_text.trim().is_empty() && ocr {
            let recognized = ocr_pdf_page(path, page_no)?;
            pages.extend(chunk_text(path, Some(page_no), None, &recognized));
        } else {
            pages.extend(chunk_text(path, Some(page_no), None, page_text));
        }
    }
    Ok(pages)
}

fn split_pdf_pages(text: &str) -> Vec<&str> {
    // Poppler emits one form feed after every page. Remove only the final
    // delimiter; trimming all delimiters would discard trailing scanned pages.
    text.strip_suffix('\u{000c}')
        .unwrap_or(text)
        .split('\u{000c}')
        .collect()
}

fn run_timeout(mut child: Child, timeout: Duration, label: &str) -> Result<std::process::Output> {
    let start = Instant::now();
    loop {
        if child.try_wait()?.is_some() {
            return child
                .wait_with_output()
                .with_context(|| format!("wait for {label}"));
        }
        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            bail!("{label} timed out");
        }
        thread::sleep(Duration::from_millis(50));
    }
}

fn ocr_pdf_page(path: &Path, page: u32) -> Result<String> {
    let tmp = tempfile::Builder::new()
        .prefix("seek-ocr-")
        .tempdir()
        .context("create private OCR temp dir")?;
    let prefix = tmp.path().join("page");
    let child = Command::new("pdftoppm")
        .args([
            "-f",
            &page.to_string(),
            "-l",
            &page.to_string(),
            "-singlefile",
            "-png",
            "-r",
            "150",
        ])
        .arg(path)
        .arg(&prefix)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("pdftoppm is required for OCR")?;
    let rendered = run_timeout(child, Duration::from_secs(30), "pdftoppm")?;
    if !rendered.status.success() {
        bail!("pdftoppm failed on PDF page {page}");
    }
    let image = prefix.with_extension("png");
    let output_file = tmp.path().join("recognized");
    let child = Command::new("tesseract")
        .arg(&image)
        .arg(&output_file)
        .args(["-l", "chi_sim+eng", "--psm", "3"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("tesseract with chi_sim+eng is required for OCR")?;
    let output = run_timeout(child, Duration::from_secs(45), "tesseract")?;
    if !output.status.success() {
        bail!("tesseract failed on PDF page {page}");
    }
    let output_file = output_file.with_extension("txt");
    let metadata = fs::metadata(&output_file)?;
    if metadata.len() > MAX_XML_BYTES {
        bail!("OCR text exceeds 32 MiB");
    }
    fs::read_to_string(output_file).context("tesseract produced invalid UTF-8")
}

fn read_zip_entry<R: Read + std::io::Seek>(
    archive: &mut zip::ZipArchive<R>,
    name: &str,
    limit: u64,
) -> Result<String> {
    let entry = archive
        .by_name(name)
        .with_context(|| format!("missing OOXML part {name}"))?;
    if entry.size() > limit {
        bail!("OOXML part exceeds size limit: {name}");
    }
    let mut bytes = Vec::with_capacity(entry.size() as usize);
    entry.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        bail!("OOXML part exceeds size limit: {name}");
    }
    String::from_utf8(bytes).with_context(|| format!("OOXML part is not UTF-8: {name}"))
}

fn local_name(name: &[u8]) -> &[u8] {
    name.rsplit(|b| *b == b':').next().unwrap_or(name)
}

fn xml_elements(xml: &str, target: &[u8]) -> Result<Vec<String>> {
    let mut reader = Reader::from_str(xml);
    // OOXML uses xml:space="preserve" to keep meaningful spaces at run
    // boundaries. Do not trim text nodes; doing so joins e.g. "linear " and
    // "algebra" into a different word.
    reader.config_mut().trim_text(false);
    let mut active_depth = None;
    let mut depth = 0usize;
    let mut values = Vec::new();
    let mut current = String::new();
    loop {
        match reader.read_event()? {
            Event::Start(e) => {
                depth += 1;
                if active_depth.is_none() && local_name(e.name().as_ref()) == target {
                    active_depth = Some(depth);
                    current.clear();
                }
            }
            Event::Empty(e) if local_name(e.name().as_ref()) == target => {
                values.push(String::new())
            }
            Event::End(_) => {
                if active_depth == Some(depth) {
                    values.push(std::mem::take(&mut current));
                    active_depth = None;
                }
                depth = depth.saturating_sub(1);
            }
            Event::Text(e) if active_depth.is_some() => {
                let decoded = e.unescape()?;
                current.push_str(&decoded)
            }
            Event::CData(e) if active_depth.is_some() => {
                let decoded = e.decode()?;
                current.push_str(&decoded)
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(values)
}

fn archive_guard<R: Read + std::io::Seek>(archive: &mut zip::ZipArchive<R>) -> Result<()> {
    if archive.len() > MAX_ARCHIVE_ENTRIES {
        bail!("OOXML archive has too many entries");
    }
    let mut total = 0u64;
    for i in 0..archive.len() {
        let entry = archive.by_index(i)?;
        total = total.saturating_add(entry.size());
        if total > MAX_ARCHIVE_BYTES {
            bail!("OOXML expanded size exceeds 128 MiB");
        }
    }
    Ok(())
}

fn extract_ooxml(path: &Path, ext: &str) -> Result<Vec<Chunk>> {
    let file = fs::File::open(path)?;
    let mut archive = zip::ZipArchive::new(file).context("open OOXML ZIP archive")?;
    archive_guard(&mut archive)?;
    let mut chunks = Vec::new();
    match ext {
        "docx" => {
            let xml = read_zip_entry(&mut archive, "word/document.xml", MAX_XML_BYTES)?;
            let text = xml_elements(&xml, b"p")?.join("\n");
            chunks.extend(chunk_text(path, None, None, &text));
        }
        "pptx" => {
            let presentation = read_zip_entry(&mut archive, "ppt/presentation.xml", MAX_XML_BYTES)?;
            let relations = read_zip_entry(
                &mut archive,
                "ppt/_rels/presentation.xml.rels",
                MAX_XML_BYTES,
            )?;
            let rel_map = element_attributes(&relations, b"Relationship")?
                .into_iter()
                .filter_map(|attrs| Some((attrs.get("Id")?.clone(), attrs.get("Target")?.clone())))
                .collect::<std::collections::HashMap<_, _>>();
            let slide_ids = element_attributes(&presentation, b"sldId")?;
            for (position, attrs) in slide_ids.into_iter().enumerate() {
                let rel_id = attrs.get("r:id").or_else(|| attrs.get("id"));
                let Some(target) = rel_id.and_then(|id| rel_map.get(id)) else {
                    continue;
                };
                let name = normalize_part_target("ppt", target);
                let xml = read_zip_entry(&mut archive, &name, MAX_XML_BYTES)?;
                let text = xml_elements(&xml, b"t")?.join("\n");
                chunks.extend(chunk_text(path, Some(position as u32 + 1), None, &text));
            }
        }
        "xlsx" => {
            let shared = if archive.file_names().any(|n| n == "xl/sharedStrings.xml") {
                let xml = read_zip_entry(&mut archive, "xl/sharedStrings.xml", MAX_XML_BYTES)?;
                xml_elements(&xml, b"si")?
            } else {
                Vec::new()
            };
            let workbook = read_zip_entry(&mut archive, "xl/workbook.xml", MAX_XML_BYTES)?;
            let relations =
                read_zip_entry(&mut archive, "xl/_rels/workbook.xml.rels", MAX_XML_BYTES)?;
            let rel_map = element_attributes(&relations, b"Relationship")?
                .into_iter()
                .filter_map(|attrs| Some((attrs.get("Id")?.clone(), attrs.get("Target")?.clone())))
                .collect::<std::collections::HashMap<_, _>>();
            let sheets = element_attributes(&workbook, b"sheet")?;
            for (position, attrs) in sheets.into_iter().enumerate() {
                let title = attrs.get("name").cloned().unwrap_or_default();
                let rel_id = attrs.get("r:id").or_else(|| attrs.get("id"));
                let Some(target) = rel_id.and_then(|id| rel_map.get(id)) else {
                    continue;
                };
                let name = normalize_part_target("xl", target);
                let xml = read_zip_entry(&mut archive, &name, MAX_XML_BYTES)?;
                let rows = worksheet_rows(&xml, &shared)?;
                chunks.extend(chunk_text(
                    path,
                    Some(position as u32 + 1),
                    Some(&title),
                    &rows.join("\n"),
                ));
            }
        }
        _ => bail!("unsupported OOXML type"),
    }
    Ok(chunks)
}

fn element_attributes(
    xml: &str,
    target: &[u8],
) -> Result<Vec<std::collections::HashMap<String, String>>> {
    let mut reader = Reader::from_str(xml);
    let mut out = Vec::new();
    loop {
        match reader.read_event()? {
            Event::Empty(e) | Event::Start(e) if local_name(e.name().as_ref()) == target => {
                let mut values = std::collections::HashMap::new();
                for attr in e.attributes().flatten() {
                    values.insert(
                        String::from_utf8_lossy(attr.key.as_ref()).into_owned(),
                        attr.decode_and_unescape_value(reader.decoder())?
                            .into_owned(),
                    );
                }
                out.push(values);
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(out)
}

fn normalize_part_target(base: &str, target: &str) -> String {
    let mut parts = Vec::new();
    let absolute = target.starts_with('/');
    let target = target.trim_start_matches('/');
    let joined = if absolute || target.starts_with(&format!("{base}/")) {
        target.to_owned()
    } else {
        format!("{base}/{target}")
    };
    for part in joined.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            value => parts.push(value),
        }
    }
    parts.join("/")
}

fn worksheet_rows(xml: &str, shared_strings: &[String]) -> Result<Vec<String>> {
    let mut reader = Reader::from_str(xml);
    let mut rows = Vec::new();
    let mut row: Option<Vec<String>> = None;
    let mut cell: Option<(String, String)> = None;
    let mut depth = 0usize;
    let mut cell_depth = 0usize;
    loop {
        match reader.read_event()? {
            Event::Start(e) => {
                depth += 1;
                match local_name(e.name().as_ref()) {
                    b"row" if row.is_none() => row = Some(Vec::new()),
                    b"c" if row.is_some() && cell.is_none() => {
                        let mut kind = String::new();
                        for attr in e.attributes().flatten() {
                            if local_name(attr.key.as_ref()) == b"t" {
                                kind = attr
                                    .decode_and_unescape_value(reader.decoder())?
                                    .into_owned();
                            }
                        }
                        cell = Some((kind, String::new()));
                        cell_depth = depth;
                    }
                    _ => {}
                }
            }
            Event::Empty(e) if local_name(e.name().as_ref()) == b"c" => {
                if let Some(values) = row.as_mut() {
                    values.push(String::new());
                }
            }
            Event::Text(e) if cell.is_some() => {
                if let Some((_, value)) = cell.as_mut() {
                    value.push_str(&e.unescape()?);
                }
            }
            Event::CData(e) if cell.is_some() => {
                if let Some((_, value)) = cell.as_mut() {
                    value.push_str(&e.decode()?);
                }
            }
            Event::End(e) => {
                match local_name(e.name().as_ref()) {
                    b"c" if cell.is_some() && depth == cell_depth => {
                        if let (Some(values), Some((kind, value))) = (row.as_mut(), cell.take()) {
                            let value = if kind == "s" {
                                value
                                    .parse::<usize>()
                                    .ok()
                                    .and_then(|index| shared_strings.get(index))
                                    .cloned()
                                    .unwrap_or(value)
                            } else {
                                value
                            };
                            values.push(value);
                        }
                    }
                    b"row" if row.is_some() => {
                        let values = row.take().unwrap_or_default();
                        if !values.is_empty() {
                            rows.push(values.join("\t"));
                        }
                    }
                    _ => {}
                }
                depth = depth.saturating_sub(1);
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn make_zip(path: &Path, parts: &[(&str, &str)]) {
        let file = fs::File::create(path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        for (name, content) in parts {
            zip.start_file(*name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(content.as_bytes()).unwrap();
        }
        zip.finish().unwrap();
    }

    fn make_two_page_pdf(path: &Path) {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
            "<< /Length 43 >>\nstream\nBT /F1 18 Tf 72 700 Td (Entropy page) Tj ET\nendstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
            "<< /Length 43 >>\nstream\nBT /F1 18 Tf 72 700 Td (Fourier page) Tj ET\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ];
        let mut bytes = b"%PDF-1.4\n".to_vec();
        let mut offsets = vec![0usize];
        for (index, object) in objects.iter().enumerate() {
            offsets.push(bytes.len());
            bytes
                .extend_from_slice(format!("{} 0 obj\n{}\nendobj\n", index + 1, object).as_bytes());
        }
        let xref = bytes.len();
        bytes.extend_from_slice(
            format!("xref\n0 {}\n0000000000 65535 f \n", offsets.len()).as_bytes(),
        );
        for offset in offsets.iter().skip(1) {
            bytes.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
        }
        bytes.extend_from_slice(
            format!(
                "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
                offsets.len()
            )
            .as_bytes(),
        );
        fs::write(path, bytes).unwrap();
    }
    #[test]
    fn plain_text_keeps_heading_and_line_numbers_and_chunks_long_lines() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("fixture.md");
        fs::write(
            &path,
            "# 课程标题\n一行内容\n".to_string() + &"中".repeat(1500),
        )
        .unwrap();
        let got = extract(&path, false, 10_000).unwrap();
        assert_eq!(got[0].title, "课程标题");
        assert_eq!(got[0].line_start, 1);
        assert!(got
            .iter()
            .all(|c| c.text.chars().count() <= MAX_CHARS_PER_CHUNK));
        assert!(got.last().unwrap().line_end >= 3);
    }
    #[test]
    fn byte_limit_and_non_regular_files_are_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("fixture.txt");
        fs::write(&path, "content").unwrap();
        assert!(extract(&path, false, 3).is_err());
        assert!(extract(dir.path(), false, 10).is_err());
    }
    #[test]
    fn chinese_and_cdata_xml_text_is_decoded() {
        let xml = "<p:a xmlns:p='x'><p:t>微积分</p:t><p:t><![CDATA[heat & flow]]></p:t><p:t>linear </p:t><p:t>algebra</p:t></p:a>";
        assert_eq!(
            xml_elements(xml, b"t").unwrap().join(" "),
            "微积分 heat & flow linear  algebra"
        );
    }

    #[test]
    fn pdf_page_split_preserves_trailing_blank_pages() {
        assert_eq!(split_pdf_pages("\u{000c}\u{000c}\u{000c}").len(), 3);
        assert_eq!(split_pdf_pages("page one\u{000c}page two\u{000c}").len(), 2);
    }

    #[test]
    fn docx_pptx_and_xlsx_keep_text_and_locations() {
        let dir = tempfile::tempdir().unwrap();
        let docx = dir.path().join("notes.docx");
        make_zip(
            &docx,
            &[("word/document.xml", "<w:document xmlns:w='urn:w'><w:body><w:p><w:r><w:t>课程隔离级别</w:t></w:r></w:p><w:p><w:r><w:t>Repeatable read</w:t></w:r></w:p><w:p><w:r><w:t>linear </w:t></w:r><w:r><w:t>algebra</w:t></w:r></w:p></w:body></w:document>")],
        );
        let chunks = extract(&docx, false, 10_000).unwrap();
        assert!(chunks
            .iter()
            .any(|chunk| chunk.text.contains("课程隔离级别")));
        assert!(chunks
            .iter()
            .any(|chunk| chunk.text.contains("Repeatable read")));
        assert!(chunks
            .iter()
            .any(|chunk| chunk.text.contains("linear algebra")));
        assert_eq!(chunks[0].page, None);

        let pptx = dir.path().join("lecture.pptx");
        make_zip(
            &pptx,
            &[
                ("ppt/presentation.xml", "<p:presentation xmlns:p='urn:p' xmlns:r='urn:r'><p:sldIdLst><p:sldId id='2' r:id='rId2'/><p:sldId id='1' r:id='rId1'/></p:sldIdLst></p:presentation>"),
                ("ppt/_rels/presentation.xml.rels", "<Relationships><Relationship Id='rId1' Target='slides/slide1.xml'/><Relationship Id='rId2' Target='slides/slide3.xml'/></Relationships>"),
                (
                    "ppt/slides/slide3.xml",
                    "<p:sld xmlns:p='urn:p' xmlns:a='urn:a'><a:t>第一张傅里叶变换</a:t></p:sld>",
                ),
                (
                    "ppt/slides/slide1.xml",
                    "<p:sld xmlns:p='urn:p' xmlns:a='urn:a'><a:t>后半部分振动</a:t></p:sld>",
                ),
            ],
        );
        let chunks = extract(&pptx, false, 10_000).unwrap();
        assert_eq!(
            chunks.iter().map(|c| c.page).collect::<Vec<_>>(),
            vec![Some(1), Some(2)]
        );
        assert!(chunks[0].text.contains("第一张傅里叶变换"));
        assert!(chunks[1].text.contains("后半部分振动"));

        let xlsx = dir.path().join("grades.xlsx");
        make_zip(
            &xlsx,
            &[
                ("xl/workbook.xml", "<workbook xmlns:r='urn:r'><sheets><sheet name='热学' sheetId='1' r:id='rId9'/></sheets></workbook>"),
                ("xl/_rels/workbook.xml.rels", "<Relationships><Relationship Id='rId9' Target='worksheets/custom.xml' Type='sheet'/></Relationships>"),
                ("xl/sharedStrings.xml", "<sst><si><t>玻尔兹曼常数</t></si></sst>"),
                ("xl/worksheets/custom.xml", "<worksheet><sheetData><row r='1'><c r='A1' t='s'><v>0</v></c><c r='B1' t='inlineStr'><is><t>Boltzmann constant</t></is></c></row></sheetData></worksheet>"),
            ],
        );
        let chunks = extract(&xlsx, false, 10_000).unwrap();
        assert_eq!(chunks[0].title, "热学");
        assert_eq!(chunks[0].page, Some(1));
        assert!(chunks[0].text.contains("玻尔兹曼常数"));
        assert!(chunks[0].text.contains("Boltzmann constant"));
    }

    #[test]
    fn pdf_chunks_preserve_page_numbers() {
        if Command::new("pdftotext").arg("-v").output().is_err() {
            return;
        }
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("lecture.pdf");
        make_two_page_pdf(&path);
        let chunks = extract(&path, false, 10_000).unwrap();
        assert!(chunks
            .iter()
            .any(|c| c.page == Some(1) && c.text.contains("Entropy page")));
        assert!(chunks
            .iter()
            .any(|c| c.page == Some(2) && c.text.contains("Fourier page")));
    }
}
