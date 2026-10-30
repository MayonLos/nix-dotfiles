use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Video {
    pub bvid: String,
    pub aid: u64,
    pub cid: u64,
    pub title: String,
    pub up: String,
    pub mid: u64,
    pub cover: String,
    pub views: u64,
    pub danmaku: u64,
    pub likes: u64,
    pub duration: String,
    pub description: String,
    pub pages: Vec<Part>,
    pub collection: Vec<Video>,
}
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Part {
    pub cid: u64,
    pub page: u64,
    pub part: String,
}
pub fn number(v: &Value) -> u64 {
    v.as_u64()
        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        .unwrap_or(0)
}
pub fn clean(s: &str) -> String {
    let mut tag = false;
    s.chars()
        .filter(|c| {
            if *c == '<' {
                tag = true;
                return false;
            }
            if *c == '>' {
                tag = false;
                return false;
            }
            !tag && (!c.is_control() || *c == '\n')
        })
        .collect::<String>()
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
}
impl Video {
    pub fn parse(v: &Value) -> Self {
        let owner = v
            .get("owner")
            .or_else(|| v.get("upper"))
            .unwrap_or(&Value::Null);
        let stat = v.get("stat").or_else(|| v.get("cnt_info")).unwrap_or(v);
        let text = |key: &str| clean(v[key].as_str().unwrap_or(""));
        let mut title = text("title");
        if title.is_empty() {
            title = text("name");
        }
        let pages = v["pages"]
            .as_array()
            .map(|p| {
                p.iter()
                    .map(|p| Part {
                        cid: number(&p["cid"]),
                        page: number(&p["page"]),
                        part: clean(p["part"].as_str().unwrap_or("")),
                    })
                    .collect()
            })
            .unwrap_or_default();
        let collection = v["ugc_season"]["sections"]
            .as_array()
            .map(|s| {
                s.iter()
                    .flat_map(|s| s["episodes"].as_array().into_iter().flatten())
                    .map(|ep| {
                        let mut video = Self::parse(ep.get("arc").unwrap_or(ep));
                        if video.bvid.is_empty() {
                            video.bvid = ep["bvid"].as_str().unwrap_or("").into();
                        }
                        if video.aid == 0 {
                            video.aid = number(&ep["aid"]);
                        }
                        if video.cid == 0 {
                            video.cid = number(&ep["cid"]);
                        }
                        video
                    })
                    .collect()
            })
            .unwrap_or_default();
        Self {
            bvid: text("bvid"),
            aid: number(v.get("aid").or_else(|| v.get("id")).unwrap_or(&Value::Null)),
            cid: number(&v["cid"]),
            title,
            up: clean(
                owner["name"]
                    .as_str()
                    .or_else(|| v["author"].as_str())
                    .or_else(|| owner["uname"].as_str())
                    .unwrap_or(""),
            ),
            mid: number(
                owner
                    .get("mid")
                    .or_else(|| v.get("mid"))
                    .unwrap_or(&Value::Null),
            ),
            cover: v["pic"]
                .as_str()
                .or_else(|| v["cover"].as_str())
                .unwrap_or("")
                .to_string(),
            views: number(
                stat.get("view")
                    .or_else(|| stat.get("play"))
                    .unwrap_or(&Value::Null),
            ),
            danmaku: number(
                stat.get("danmaku")
                    .or_else(|| stat.get("danmaku_count"))
                    .unwrap_or(&Value::Null),
            ),
            likes: number(&stat["like"]),
            duration: v["duration"]
                .as_str()
                .map(str::to_owned)
                .unwrap_or_else(|| {
                    let n = number(&v["duration"]);
                    format!("{}:{:02}", n / 60, n % 60)
                }),
            description: text("desc"),
            pages,
            collection,
        }
    }
    pub fn link(&self) -> String {
        format!("https://www.bilibili.com/video/{}", self.bvid)
    }
}
pub fn videos(v: &Value) -> Vec<Video> {
    v.as_array()
        .map(|a| {
            a.iter()
                .map(Video::parse)
                .filter(|v| !v.bvid.is_empty())
                .collect()
        })
        .unwrap_or_default()
}
pub fn count(n: u64) -> String {
    if n >= 10000 {
        format!("{:.1}万", n as f64 / 10000.)
    } else {
        n.to_string()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn search_and_details() {
        let v = Video::parse(
            &serde_json::json!({"bvid":"BVtest","title":"<em>测试</em>\u{1b}[31m", "author":"UP", "mid":"42", "play":123, "duration":"3:21"}),
        );
        assert_eq!(v.title, "测试[31m");
        assert_eq!(v.mid, 42);
        assert_eq!(v.views, 123);
        let v = Video::parse(
            &serde_json::json!({"bvid":"BVtest","pages":[{"cid":42,"page":1,"part":"一"}], "stat":{"view":456},"owner":{"name":"甲"}}),
        );
        assert_eq!(v.pages[0].cid, 42);
        assert_eq!(v.views, 456);
    }
    #[test]
    fn recorded_public_payloads() {
        let popular: Value =
            serde_json::from_str(include_str!("../fixtures/popular-public.json")).unwrap();
        let search: Value =
            serde_json::from_str(include_str!("../fixtures/search-public.json")).unwrap();
        let detail: Value =
            serde_json::from_str(include_str!("../fixtures/view-public.json")).unwrap();
        assert_eq!(videos(&popular["list"]).len(), 3);
        assert_eq!(videos(&search["result"]).len(), 3);
        let video = Video::parse(&detail);
        assert_ne!(video.cid, 0);
        assert!(!video.pages.is_empty());
        assert!(!video.up.is_empty());
    }
    #[test]
    fn collection_uses_episode_cid() {
        let v = Video::parse(
            &serde_json::json!({"ugc_season":{"sections":[{"episodes":[{"cid":123,"bvid":"BVfixture","aid":456,"arc":{"title":"合集第一集"}}]}]}}),
        );
        assert_eq!(v.collection[0].cid, 123);
        assert_eq!(v.collection[0].bvid, "BVfixture");
    }
    #[test]
    fn text_is_terminal_safe() {
        assert_eq!(clean("<em>树</em>&amp;\u{7}"), "树&");
    }
}
