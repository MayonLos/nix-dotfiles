use pinyin::ToPinyin;
/// Cached per name, supporting literal Chinese and Latin/pinyin subsequences.
pub fn search_key(text: &str) -> String {
    let initials: String = text
        .chars()
        .map(|c| {
            c.to_pinyin()
                .and_then(|p| p.plain().chars().next())
                .unwrap_or(c)
        })
        .collect();
    format!("{} {}", text.to_lowercase(), initials.to_lowercase())
}
pub fn matches(key: &str, query: &str) -> bool {
    let query = query.trim().to_lowercase();
    if query.is_empty() || key.contains(&query) {
        return true;
    }
    let mut chars = query.chars();
    let mut next = chars.next();
    for ch in key.chars() {
        if Some(ch) == next {
            next = chars.next();
            if next.is_none() {
                return true;
            }
        }
    }
    false
}
pub fn redact_log(text: &str) -> String {
    text.split_whitespace()
        .map(|word| {
            if word.contains("://")
                || word.to_ascii_lowercase().contains("token=")
                || word.to_ascii_lowercase().contains("secret=")
            {
                "[链接/凭据已隐藏]"
            } else {
                word
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn multilingual_fuzzy_search() {
        let key = search_key("🇭🇰 香港 HK 高速 Tokyo 01");
        for q in ["香港", "xggs", "hk", "tko", "TOKYO", "01"] {
            assert!(matches(&key, q), "{q}");
        }
        assert!(!matches(&key, "日本"));
        assert_eq!(
            redact_log("load https://example.invalid/?token=x failed"),
            "load [链接/凭据已隐藏] failed"
        );
    }
}
