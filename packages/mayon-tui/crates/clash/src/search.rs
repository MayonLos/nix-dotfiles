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
    fn logs_redact_credentials() {
        assert_eq!(
            redact_log("load https://example.invalid/?token=x failed"),
            "load [链接/凭据已隐藏] failed"
        );
    }
}
