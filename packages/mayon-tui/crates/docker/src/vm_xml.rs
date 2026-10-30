//! Bounded parser for libvirt XML metadata. It never resolves entities or reads files.
use std::collections::HashMap;

const MAX_INPUT: usize = 4 * 1024 * 1024;
const MAX_DEPTH: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Node {
    pub name: String,
    pub attrs: HashMap<String, String>,
    pub text: String,
    pub children: Vec<Node>,
}
impl Node {
    pub fn child(&self, name: &str) -> Option<&Node> {
        self.children.iter().find(|node| node.name == name)
    }

    pub fn attr(&self, name: &str) -> Option<&str> {
        self.attrs.get(name).map(String::as_str)
    }

    /// Returns matching nodes below this node in document order.
    pub fn descendants(&self, name: &str) -> Vec<&Node> {
        let mut found = Vec::new();
        self.collect_descendants(name, &mut found);
        found
    }

    fn collect_descendants<'a>(&'a self, name: &str, found: &mut Vec<&'a Node>) {
        for child in &self.children {
            if child.name == name {
                found.push(child);
            }
            child.collect_descendants(name, found);
        }
    }
}

pub fn parse(input: &str) -> Result<Node, String> {
    if input.len() > MAX_INPUT {
        return Err("XML exceeds 4 MiB limit".into());
    }
    let mut parser = Parser { input, cursor: 0 };
    parser.skip_misc()?;
    if parser.cursor == input.len() {
        return Err("XML has no root element".into());
    }
    if parser.starts_with("<!") {
        return Err("DTD and declarations are not supported".into());
    }
    let root = parser.element(1)?;
    parser.skip_misc()?;
    if parser.cursor != input.len() {
        return Err("content follows the XML root element".into());
    }
    Ok(root)
}

struct Parser<'a> {
    input: &'a str,
    cursor: usize,
}
impl Parser<'_> {
    fn starts_with(&self, s: &str) -> bool {
        self.input[self.cursor..].starts_with(s)
    }

    fn rest(&self) -> &str {
        &self.input[self.cursor..]
    }

    fn skip_space(&mut self) {
        while let Some(c) = self.rest().chars().next() {
            if !c.is_ascii_whitespace() {
                break;
            }
            self.cursor += c.len_utf8();
        }
    }

    fn skip_misc(&mut self) -> Result<(), String> {
        loop {
            self.skip_space();
            if self.starts_with("<!--") {
                self.skip_until("-->", "unterminated XML comment")?;
            } else if self.starts_with("<?") {
                self.skip_until("?>", "unterminated XML processing instruction")?;
            } else if self.starts_with("<!") {
                return Err("DTD and declarations are not supported".into());
            } else {
                return Ok(());
            }
        }
    }

    fn skip_until(&mut self, terminator: &str, error: &str) -> Result<(), String> {
        let Some(offset) = self.rest().find(terminator) else {
            return Err(error.into());
        };
        self.cursor += offset + terminator.len();
        Ok(())
    }

    fn name(&mut self) -> Result<String, String> {
        let start = self.cursor;
        let Some(first) = self.input.as_bytes().get(self.cursor).copied() else {
            return Err("expected XML name".into());
        };
        if !is_name_start_byte(first) {
            return Err("expected XML name".into());
        }
        self.cursor += 1;
        while let Some(byte) = self.input.as_bytes().get(self.cursor).copied() {
            if is_name_byte(byte) {
                self.cursor += 1;
            } else {
                break;
            }
        }
        if self.cursor == start {
            return Err("expected XML name".into());
        }
        Ok(self.input[start..self.cursor].to_owned())
    }

    fn element(&mut self, depth: usize) -> Result<Node, String> {
        if depth > MAX_DEPTH {
            return Err("XML nesting exceeds 64 elements".into());
        }
        self.expect("<")?;
        if self.starts_with("/") || self.starts_with("!") || self.starts_with("?") {
            return Err("expected opening XML element".into());
        }
        let name = self.name()?;
        let mut attrs = HashMap::new();
        loop {
            self.skip_space();
            if self.starts_with("/>") {
                self.cursor += 2;
                return Ok(Node {
                    name,
                    attrs,
                    text: String::new(),
                    children: Vec::new(),
                });
            }
            if self.starts_with(">") {
                self.cursor += 1;
                break;
            }
            let key = self.name()?;
            if attrs.contains_key(&key) {
                return Err(format!("duplicate XML attribute {key}"));
            }
            self.skip_space();
            self.expect("=")?;
            self.skip_space();
            let quote = self
                .rest()
                .chars()
                .next()
                .ok_or("missing XML attribute value")?;
            if quote != '\'' && quote != '"' {
                return Err("XML attributes must use quotes".into());
            }
            self.cursor += quote.len_utf8();
            let value_start = self.cursor;
            let Some(offset) = self.rest().find(quote) else {
                return Err("unterminated XML attribute value".into());
            };
            let raw = &self.input[value_start..value_start + offset];
            if raw.contains('<') {
                return Err("XML attribute contains an unescaped '<'".into());
            }
            attrs.insert(key, decode_entities(raw)?);
            self.cursor = value_start + offset + quote.len_utf8();
        }

        let mut node = Node {
            name: name.clone(),
            attrs,
            text: String::new(),
            children: Vec::new(),
        };
        loop {
            if self.cursor >= self.input.len() {
                return Err(format!("unterminated XML element {name}"));
            }
            if self.starts_with("</") {
                self.cursor += 2;
                let close_name = self.name()?;
                self.skip_space();
                self.expect(">")?;
                if close_name != name {
                    return Err(format!(
                        "mismatched closing element: expected {name}, got {close_name}"
                    ));
                }
                return Ok(node);
            }
            if self.starts_with("<!--") {
                self.skip_until("-->", "unterminated XML comment")?;
            } else if self.starts_with("<?") {
                self.skip_until("?>", "unterminated XML processing instruction")?;
            } else if self.starts_with("<![CDATA[") {
                self.cursor += "<![CDATA[".len();
                let Some(offset) = self.rest().find("]]>") else {
                    return Err("unterminated XML CDATA section".into());
                };
                node.text
                    .push_str(&self.input[self.cursor..self.cursor + offset]);
                self.cursor += offset + "]]>".len();
            } else if self.starts_with("<!") {
                return Err("DTD and declarations are not supported".into());
            } else if self.starts_with("<") {
                node.children.push(self.element(depth + 1)?);
            } else {
                let Some(offset) = self.rest().find('<') else {
                    return Err(format!("unterminated XML element {name}"));
                };
                let raw = &self.input[self.cursor..self.cursor + offset];
                node.text.push_str(&decode_entities(raw)?);
                self.cursor += offset;
            }
        }
    }

    fn expect(&mut self, token: &str) -> Result<(), String> {
        if self.starts_with(token) {
            self.cursor += token.len();
            Ok(())
        } else {
            Err(format!("expected {token:?} in XML"))
        }
    }
}

fn is_name_start_byte(byte: u8) -> bool {
    byte.is_ascii_alphabetic() || matches!(byte, b'_' | b':')
}

fn is_name_byte(byte: u8) -> bool {
    is_name_start_byte(byte) || byte.is_ascii_digit() || matches!(byte, b'-' | b'.')
}

fn decode_entities(raw: &str) -> Result<String, String> {
    let mut decoded = String::with_capacity(raw.len());
    let mut cursor = 0;
    while let Some(offset) = raw[cursor..].find('&') {
        let start = cursor + offset;
        decoded.push_str(&raw[cursor..start]);
        let entity_start = start + 1;
        let Some(end_offset) = raw[entity_start..].find(';') else {
            return Err("unterminated XML entity".into());
        };
        let end = entity_start + end_offset;
        let entity = &raw[entity_start..end];
        match entity {
            "amp" => decoded.push('&'),
            "lt" => decoded.push('<'),
            "gt" => decoded.push('>'),
            "quot" => decoded.push('"'),
            "apos" => decoded.push('\''),
            _ if entity.starts_with("#x") || entity.starts_with("#X") => {
                let value = u32::from_str_radix(&entity[2..], 16)
                    .map_err(|_| "invalid hexadecimal XML character reference")?;
                decoded.push(xml_char(value)?);
            }
            _ if entity.starts_with('#') => {
                let value = entity[1..]
                    .parse::<u32>()
                    .map_err(|_| "invalid decimal XML character reference")?;
                decoded.push(xml_char(value)?);
            }
            _ => return Err(format!("unknown XML entity &{entity};")),
        }
        cursor = end + 1;
    }
    decoded.push_str(&raw[cursor..]);
    Ok(decoded)
}

fn xml_char(value: u32) -> Result<char, String> {
    let valid = matches!(value, 0x9 | 0xA | 0xD)
        || (0x20..=0xD7FF).contains(&value)
        || (0xE000..=0xFFFD).contains(&value)
        || (0x10000..=0x10FFFF).contains(&value);
    if !valid {
        return Err("XML character reference is not a valid XML code point".into());
    }
    char::from_u32(value).ok_or_else(|| "invalid Unicode code point in XML".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_libvirt_disk_chains_and_decodes_quoted_paths() {
        let xml = r#"<?xml version="1.0"?>
        <!-- metadata only -->
        <domain><name>guest &amp; lab</name><devices>
          <disk type='file' device='disk'><source file='/vms/磁盘 &quot;A&quot;.qcow2'/>
            <backingStore><format type='qcow2'/><source file='/pool/base&amp;seed.qcow2'/>
              <backingStore><source file='/pool/root.qcow2'/></backingStore>
            </backingStore>
          </disk>
        </devices></domain>"#;
        let root = parse(xml).unwrap();
        assert_eq!(root.child("name").unwrap().text, "guest & lab");
        let disk = root.descendants("disk")[0];
        assert_eq!(disk.attr("type"), Some("file"));
        assert_eq!(
            disk.descendants("source")[0].attr("file"),
            Some("/vms/磁盘 \"A\".qcow2")
        );
        assert_eq!(
            disk.descendants("source")[1].attr("file"),
            Some("/pool/base&seed.qcow2")
        );
        assert_eq!(
            disk.descendants("source")[2].attr("file"),
            Some("/pool/root.qcow2")
        );
    }

    #[test]
    fn parses_numeric_entities_and_self_closing_elements() {
        let root = parse("<pool><path>/x&#32;&#x2F;é</path><volume/></pool>").unwrap();
        assert_eq!(root.child("path").unwrap().text, "/x /é");
        assert!(root.child("volume").unwrap().children.is_empty());
    }

    #[test]
    fn rejects_external_entities_declarations_and_malformed_documents() {
        for xml in [
            "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><x>&e;</x>",
            "<x>&external;</x>",
            "<x>&#0;</x>",
            "<x><y></x>",
            "<x>",
            "<x/><y/>",
            "<x a=unquoted/>",
            "<x a='1' a='2'/>",
        ] {
            assert!(parse(xml).is_err(), "accepted: {xml}");
        }
    }

    #[test]
    fn enforces_document_size_and_nesting_limits() {
        let huge = format!("<x>{}</x>", " ".repeat(MAX_INPUT));
        assert!(parse(&huge).unwrap_err().contains("4 MiB"));
        let deep = format!("{}x{}", "<x>".repeat(MAX_DEPTH), "</x>".repeat(MAX_DEPTH));
        assert!(parse(&deep).is_ok());
        let too_deep = format!("<x>{}</x>", deep);
        assert!(parse(&too_deep).unwrap_err().contains("64"));
    }
}
