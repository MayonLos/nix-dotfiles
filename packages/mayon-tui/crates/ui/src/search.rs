use crate::theme::YELLOW;
use ratatui::{
    style::Style,
    text::{Line, Span},
};
use std::{
    cell::RefCell,
    collections::{HashMap, VecDeque},
    ops::Range,
};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Match {
    pub score: u32,
    /// Character offsets into the original text (not UTF-8 byte offsets).
    pub ranges: Vec<Range<usize>>,
}

#[derive(Clone, Debug)]
struct IndexedText {
    chars: Vec<char>,
    map: Vec<usize>,
}

impl IndexedText {
    fn new(text: &str) -> Self {
        Self::mapped(
            text.chars()
                .enumerate()
                .flat_map(|(index, ch)| ch.to_lowercase().map(move |lowered| (lowered, index))),
        )
    }

    fn mapped(entries: impl IntoIterator<Item = (char, usize)>) -> Self {
        let (chars, map): (Vec<_>, Vec<_>) = entries.into_iter().unzip();
        Self { chars, map }
    }

    fn find(&self, query: &[char]) -> Option<Vec<Range<usize>>> {
        if query.is_empty() || query.len() > self.chars.len() {
            return None;
        }
        let start = self
            .chars
            .windows(query.len())
            .position(|part| part == query)?;
        Some(self.mapped_range(start..start + query.len()))
    }

    fn subsequence(&self, query: &[char]) -> Option<Vec<Range<usize>>> {
        if query.is_empty() {
            return Some(Vec::new());
        }
        let mut positions = Vec::with_capacity(query.len());
        let mut needle = 0;
        for (index, ch) in self.chars.iter().enumerate() {
            if *ch == query[needle] {
                positions.push(index);
                needle += 1;
                if needle == query.len() {
                    break;
                }
            }
        }
        if needle != query.len() {
            return None;
        }
        Some(
            positions
                .into_iter()
                .flat_map(|i| self.mapped_range(i..i + 1))
                .collect(),
        )
    }

    fn mapped_range(&self, range: Range<usize>) -> Vec<Range<usize>> {
        let mut result: Vec<Range<usize>> = Vec::new();
        for idx in range {
            let original = self.map[idx];
            if let Some(last) = result.last_mut().filter(|last| last.end == original) {
                last.end += 1;
            } else if result.last().is_none_or(|last| last.end <= original) {
                result.push(original..original + 1);
            }
        }
        result
    }
}

#[derive(Clone, Debug)]
struct PinyinText {
    full: IndexedText,
    initials: IndexedText,
}

#[derive(Clone, Debug)]
pub struct SearchText {
    original: String,
    literal: IndexedText,
    pinyin: Option<PinyinText>,
    short: bool,
}

impl SearchText {
    pub fn new(text: &str) -> Self {
        use pinyin::ToPinyin;
        let han: Vec<char> = text.chars().filter(|ch| is_han(*ch)).collect();
        let pinyin = if han.is_empty() {
            None
        } else {
            let mut full = Vec::new();
            let mut initials = Vec::new();
            for (index, ch) in text.chars().enumerate() {
                if is_han(ch) {
                    let syllable = ch
                        .to_pinyin()
                        .map(|p| p.plain().to_owned())
                        .unwrap_or_default();
                    full.extend(syllable.chars().map(|pinyin| (pinyin, index)));
                    initials.push((syllable.chars().next().unwrap_or(ch), index));
                } else {
                    full.extend(ch.to_lowercase().map(|lower| (lower, index)));
                    initials.extend(ch.to_lowercase().map(|lower| (lower, index)));
                }
            }
            Some(PinyinText {
                full: IndexedText::mapped(full),
                initials: IndexedText::mapped(initials),
            })
        };
        Self {
            original: text.to_owned(),
            literal: IndexedText::new(text),
            pinyin,
            short: text.chars().count() <= 80,
        }
    }
    pub fn as_str(&self) -> &str {
        &self.original
    }
}

#[derive(Clone, Debug)]
pub struct Matcher {
    terms: Vec<Vec<char>>,
}

impl Matcher {
    pub fn new(query: &str) -> Self {
        Self {
            terms: query
                .split_whitespace()
                .map(|term| term.chars().flat_map(char::to_lowercase).collect())
                .collect(),
        }
    }

    pub fn matches(&self, text: &str) -> bool {
        self.find(text).is_some()
    }

    pub fn find(&self, text: &str) -> Option<Match> {
        self.find_in(&SearchText::new(text))
    }

    pub fn highlight(&self, text: &str) -> Line<'static> {
        self.highlight_in(&SearchText::new(text))
    }

    pub fn highlight_in(&self, text: &SearchText) -> Line<'static> {
        let ranges = partial_ranges(text, &self.terms);
        highlight(text.as_str(), &ranges)
    }

    pub fn matches_in(&self, text: &SearchText) -> bool {
        self.find_in(text).is_some()
    }

    pub fn find_in(&self, text: &SearchText) -> Option<Match> {
        if self.terms.is_empty() {
            return Some(Match::default());
        }
        let mut score = 0;
        let mut ranges = Vec::new();
        for term in &self.terms {
            let found = match_term(text, term)?;
            score += found.0;
            ranges.extend(found.1);
        }
        Some(Match {
            score,
            ranges: merge_ranges(ranges),
        })
    }
}

fn partial_ranges(text: &SearchText, terms: &[Vec<char>]) -> Vec<Range<usize>> {
    merge_ranges(
        terms
            .iter()
            .flat_map(|term| {
                match_term(text, term)
                    .map(|found| found.1)
                    .unwrap_or_default()
            })
            .collect(),
    )
}

fn match_term(text: &SearchText, term: &[char]) -> Option<(u32, Vec<Range<usize>>)> {
    let found = if let Some(ranges) = text.literal.find(term) {
        Some((400, ranges))
    } else if term.iter().any(|ch| ch.is_ascii_alphabetic()) {
        text.pinyin.as_ref().and_then(|p| {
            p.full
                .find(term)
                .map(|r| (300, r))
                .or_else(|| p.initials.find(term).map(|r| (200, r)))
        })
    } else {
        None
    };
    found.or_else(|| {
        if !text.short || term.len() <= 1 {
            return None;
        }
        text.literal
            .subsequence(term)
            .map(|r| (100, r))
            .or_else(|| {
                text.pinyin
                    .as_ref()
                    .and_then(|p| p.full.subsequence(term).map(|r| (100, r)))
            })
            .or_else(|| {
                text.pinyin
                    .as_ref()
                    .and_then(|p| p.initials.subsequence(term).map(|r| (100, r)))
            })
    })
}

fn merge_ranges(mut ranges: Vec<Range<usize>>) -> Vec<Range<usize>> {
    ranges.sort_by_key(|range| range.start);
    let mut merged: Vec<Range<usize>> = Vec::new();
    for range in ranges {
        if let Some(last) = merged.last_mut().filter(|last| range.start <= last.end) {
            last.end = last.end.max(range.end);
        } else {
            merged.push(range);
        }
    }
    merged
}

/// A small bounded cache for row text, including its transliteration indexes.
#[derive(Debug)]
pub struct SearchCache {
    capacity: usize,
    entries: RefCell<HashMap<String, SearchText>>,
    order: RefCell<VecDeque<String>>,
}

impl Default for SearchCache {
    fn default() -> Self {
        Self::new(8192)
    }
}

impl SearchCache {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            entries: RefCell::new(HashMap::new()),
            order: RefCell::new(VecDeque::new()),
        }
    }

    pub fn find(&self, matcher: &Matcher, text: &str) -> Option<Match> {
        if let Some(found) = self.entries.borrow().get(text) {
            return matcher.find_in(found);
        }
        if self.capacity == 0 {
            return matcher.find(text);
        }
        let value = SearchText::new(text);
        let mut entries = self.entries.borrow_mut();
        if entries.len() >= self.capacity {
            if let Some(oldest) = self.order.borrow_mut().pop_front() {
                entries.remove(&oldest);
            }
        }
        self.order.borrow_mut().push_back(text.to_owned());
        entries.insert(text.to_owned(), value);
        entries.get(text).and_then(|value| matcher.find_in(value))
    }

    pub fn matches(&self, matcher: &Matcher, text: &str) -> bool {
        self.find(matcher, text).is_some()
    }

    pub fn highlight(&self, matcher: &Matcher, text: &str) -> Line<'static> {
        if let Some(indexed) = self.entries.borrow().get(text) {
            return matcher.highlight_in(indexed);
        }
        if self.capacity == 0 {
            return matcher.highlight(text);
        }
        let indexed = SearchText::new(text);
        let mut entries = self.entries.borrow_mut();
        if entries.len() >= self.capacity {
            if let Some(oldest) = self.order.borrow_mut().pop_front() {
                entries.remove(&oldest);
            }
        }
        self.order.borrow_mut().push_back(text.to_owned());
        entries.insert(text.to_owned(), indexed);
        matcher.highlight_in(entries.get(text).expect("inserted search text"))
    }

    pub fn clear(&self) {
        self.entries.borrow_mut().clear();
        self.order.borrow_mut().clear();
    }
}

pub fn highlight(text: &str, ranges: &[Range<usize>]) -> Line<'static> {
    let chars: Vec<char> = text.chars().collect();
    let mut spans = Vec::new();
    let mut cursor = 0;
    for range in ranges {
        let start = range.start.min(chars.len()).max(cursor);
        let end = range.end.min(chars.len()).max(start);
        if cursor < start {
            spans.push(Span::raw(chars[cursor..start].iter().collect::<String>()));
        }
        if start < end {
            spans.push(Span::styled(
                chars[start..end].iter().collect::<String>(),
                Style::default().fg(YELLOW),
            ));
        }
        cursor = end;
    }
    if cursor < chars.len() {
        spans.push(Span::raw(chars[cursor..].iter().collect::<String>()));
    }
    Line::from(spans)
}

fn is_han(ch: char) -> bool {
    matches!(ch as u32, 0x3400..=0x4DBF | 0x4E00..=0x9FFF | 0xF900..=0xFAFF | 0x20000..=0x3134F)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn literal_is_case_insensitive_and_unicode_safe() {
        assert!(Matcher::new("apple").matches("Apple"));
        let found = Matcher::new("港").find("香香港").unwrap();
        assert_eq!(found.ranges, vec![2..3]);
    }
    #[test]
    fn pinyin_full_and_initials_map_to_han() {
        assert_eq!(
            Matcher::new("xianggang").find("地区香港").unwrap().ranges,
            vec![2..4]
        );
        assert_eq!(
            Matcher::new("xg").find("地区香港").unwrap().ranges,
            vec![2..4]
        );
        assert_eq!(
            Matcher::new("xiangganghk").find("香港HK").unwrap().ranges,
            vec![0..4]
        );
        assert!(!Matcher::new("xg").matches("xyz"));
    }
    #[test]
    fn pinyin_subsequence_only_matches_short_text() {
        let query = Matcher::new("xggs");
        let found = query.find("🇭🇰 香港 HK 高速 01").unwrap();
        assert!(!found.ranges.is_empty());
        assert!(!query.matches(&format!(
            "香{}港{}高{}速",
            "-".repeat(27),
            "-".repeat(27),
            "-".repeat(27)
        )));
    }

    #[test]
    fn terms_are_and_and_scored_by_match_quality() {
        assert!(Matcher::new("xiang 01").matches("香港节点 01"));
        assert!(!Matcher::new("xiang missing").matches("香港节点 01"));
        assert!(
            Matcher::new("alpha").find("alpha").unwrap().score
                > Matcher::new("ap").find("alpha").unwrap().score
        );
    }
    #[test]
    fn subsequence_only_matches_short_text() {
        assert!(Matcher::new("abc").matches("a_b_c"));
        assert!(!Matcher::new("abc").matches(&format!("a{}b{}c", "-".repeat(39), "-".repeat(39))));
    }
    #[test]
    fn partial_cell_highlights_existing_terms() {
        let line = Matcher::new("apple Tokyo").highlight("Apple node");
        assert!(line.spans.iter().any(|span| span.style.fg == Some(YELLOW)));
    }

    #[test]
    fn cache_reuses_rows_and_respects_capacity() {
        let cache = SearchCache::new(1);
        let query = Matcher::new("xiang");
        assert!(cache.matches(&query, "香港"));
        assert_eq!(cache.find(&query, "香港").unwrap().ranges, vec![0..1]);
        cache.matches(&query, "上海");
        assert!(cache.matches(&query, "香港"));
    }

    #[test]
    fn highlight_uses_character_ranges() {
        let line = highlight("节点Apple", &[0..2, 4..6]);
        assert_eq!(
            line.spans
                .iter()
                .map(|s| s.content.as_ref())
                .collect::<String>(),
            "节点Apple"
        );
        assert_eq!(line.spans.len(), 4);
    }
}
