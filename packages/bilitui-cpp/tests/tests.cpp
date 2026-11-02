#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include <ftxui/screen/screen.hpp>

#include <fstream>
#include <sstream>

#include "app.hpp"
#include "core/search.hpp"
#include "core/text.hpp"
#include "media/download.hpp"
#include "media/stream.hpp"
#include "ui/terminal.hpp"

using namespace bili;
static Json fixture(const std::string& name) {
    std::ifstream file(std::string(FIXTURES) + "/" + name);
    std::stringstream text;
    text << file.rdbuf();
    return Json::parse(text.str());
}
static InputEvent press(KeyCode code) {
    InputEvent event;
    event.key.code = code;
    return event;
}
static InputEvent ch(char32_t c) {
    InputEvent event;
    event.key.code = KeyCode::Char;
    event.key.ch = c;
    return event;
}
static InputEvent paste(const std::string& text) {
    InputEvent event;
    event.type = InputEvent::Type::Paste;
    event.paste = text;
    return event;
}
static std::string frame(App& app, int width = 120, int height = 30) {
    ftxui::Screen screen(width, height);
    app.draw(screen);
    std::string out;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) out += screen.PixelAt(x, y).character;
        out += '\n';
    }
    return out;
}
static bool contains(const std::string& text, const std::string& part) { return text.find(part) != std::string::npos; }
static std::shared_ptr<Api> anonymous() { return std::make_shared<Api>(""); }

TEST_CASE("md5 and WBI signature match the recorded fixture") {
    CHECK(md5_hex("") == "d41d8cd98f00b204e9800998ecf8427e");
    CHECK(md5_hex("The quick brown fox jumps over the lazy dog") == "9e107d9d372bb6826bd81d3542a419d6");
    const Json wbi = fixture("wbi.json");
    Params params;
    for (const Json& pair : wbi["params"]) params.emplace_back(pair[0].get<std::string>(), pair[1].get<std::string>());
    const Params signed_params = wbi_sign(params, wbi["img_key"], wbi["sub_key"], wbi["timestamp"]);
    std::string query;
    for (const auto& [name, value] : signed_params) {
        if (name == "w_rid") continue;
        if (!query.empty()) query += '&';
        query += form_encode(name) + "=" + form_encode(value);
    }
    CHECK(query == wbi["expected_query"].get<std::string>());
    CHECK(signed_params.back().second == wbi["expected_w_rid"].get<std::string>());
    CHECK_THROWS(wbi_sign(params, "short", "short", 1));
}
TEST_CASE("remote text cannot drive the terminal") {
    CHECK(clean("<em>树</em>&amp;\x07") == "树&");
    CHECK(clean("a\x1b[31mb") == "a[31mb");
    CHECK(clean("x\xc2\x9b" "31my") == "x31my");
    CHECK(clean("\xff\xfe") == "\xef\xbf\xbd\xef\xbf\xbd");
}
TEST_CASE("duration normalization") {
    CHECK(normalize_duration("3151:13") == "52:31:13");
    CHECK(normalize_duration("3:21") == "3:21");
    CHECK(normalize_duration("0:05") == "0:05");
    CHECK(seconds_text(3661) == "1:01:01");
}
TEST_CASE("recorded public payloads parse") {
    CHECK(parse_videos(fixture("popular-public.json")["list"]).size() == 3);
    CHECK(parse_videos(fixture("search-public.json")["result"]).size() == 3);
    const Video video = parse_video(fixture("view-public.json"));
    CHECK(video.cid != 0);
    CHECK_FALSE(video.parts.empty());
    CHECK_FALSE(video.up.empty());
    const Video episode = parse_video(Json::parse(R"({"ugc_season":{"sections":[{"episodes":[{"cid":123,"bvid":"BVfixture","aid":456,"title":"第一集","arc":{}}]}]}})"));
    CHECK(episode.collection[0].cid == 123);
    CHECK(episode.collection[0].bvid == "BVfixture");
    CHECK(episode.collection[0].title == "第一集");
    // Odd types must never throw from the parser.
    CHECK(parse_video(Json::parse(R"({"title":1,"pages":"x","stat":[],"owner":3,"duration":{}})")).title.empty());
}
TEST_CASE("pinyin and literal filtering") {
    CHECK(match("shenghuo", "给生活留一点空白"));
    CHECK(match("sh", "生活"));
    CHECK(match("rust suoyou", "从零理解 Rust 的所有权"));
    CHECK_FALSE(match("rust missing", "从零理解 Rust 的所有权"));
    CHECK(match("xianggang", "香港 Apple")->ranges.front().first == 0);
    CHECK(match("apple", "香港 Apple")->ranges.front().first == 3);
    CHECK(match("APPLE", "apple"));
}
TEST_CASE("API boundaries") {
    CHECK(write_path_allowed("/x/click-interface/web/heartbeat"));
    CHECK(write_path_allowed("/x/v3/fav/resource/deal"));
    CHECK_FALSE(write_path_allowed("/x/web-interface/archive/like"));
    CHECK_FALSE(write_path_allowed("/x/web-interface/coin/add"));
    CHECK(qr_url_allowed("https://account.bilibili.com/h5/account-h5/auth/scan-web?x=1"));
    CHECK_FALSE(qr_url_allowed("http://account.bilibili.com/"));
    CHECK_FALSE(qr_url_allowed("https://bilibili.com.evil.example/"));
    CHECK_FALSE(qr_url_allowed("https://evilbilibili.com/"));
    CHECK_FALSE(qr_url_allowed("https://user@account.bilibili.com/"));
    CHECK(safe_api_message("bad SESSDATA=abc") == "接口返回了凭据相关错误，敏感内容已隐藏");
    CHECK(safe_api_message("see https://x.example/a now") == "see [链接已隐藏] now");
    CHECK(clean_cookie("a=1; b=2\x7f; bad name=3; c=ok") == "a=1; c=ok");
    std::string cookie = "a=1; b=2";
    set_cookie(cookie, "a", "3");
    CHECK(cookie == "b=2; a=3");
    CHECK_THROWS(unwrap_api(Json::parse(R"({"code":-101,"message":"x"})")));
}
TEST_CASE("QR login needs a complete new session") {
    const Json waiting = Json::parse(R"({"code":0,"data":{"code":86101}})");
    CHECK(parse_qr_poll("", waiting, {}).first == 86101);
    const Json done = Json::parse(R"({"code":0,"data":{"code":0,"url":"https://evil.example/?SESSDATA=x&bili_jct=y"}})");
    CHECK_THROWS(parse_qr_poll("", done, {}));
    const Json url = Json::parse(R"({"code":0,"data":{"code":0,"url":"https://passport.bilibili.com/x?SESSDATA=a%2Cb&bili_jct=c&DedeUserID=1&other=z"}})");
    const auto ok = parse_qr_poll("buvid3=q", url, {});
    REQUIRE(ok.second);
    CHECK(cookie_value(*ok.second, "SESSDATA") == "a%2Cb");
    CHECK(cookie_value(*ok.second, "buvid3") == "q");
    CHECK_FALSE(cookie_value(*ok.second, "other"));
    const auto header = parse_qr_poll("", Json::parse(R"({"code":0,"data":{"code":0}})"), {"SESSDATA=s; Path=/; HttpOnly", "bili_jct=j; Path=/"});
    CHECK(cookie_value(*header.second, "SESSDATA") == "s");
}
TEST_CASE("media hosts are bounded") {
    CHECK(trusted_media_url("//upos-sz-mirror.bilivideo.com/a.m4s?x=1") == "https://upos-sz-mirror.bilivideo.com/a.m4s?x=1");
    CHECK(trusted_media_url("http://i0.hdslb.com/c.jpg") == "https://i0.hdslb.com/c.jpg");
    CHECK_THROWS(trusted_media_url("https://bilivideo.com.evil.example/a"));
    CHECK_THROWS(trusted_media_url("https://user:pw@upos.bilivideo.com/a"));
    CHECK_THROWS(trusted_media_url("https://upos.bilivideo.com:8443/a"));
    CHECK_THROWS(trusted_media_url("file:///etc/passwd"));
}
TEST_CASE("stream selection") {
    const Json data = Json::parse(R"({"accept_quality":[80,64],"accept_description":["1080P","720P"],"dash":{
        "video":[{"id":80,"codecid":7,"bandwidth":10,"baseUrl":"https://upos-a.bilivideo.com/80"},
                 {"id":64,"codecid":7,"bandwidth":5,"baseUrl":"https://evil.example/64","backupUrl":["https://upos-b.bilivideo.com/64"]}],
        "audio":[{"bandwidth":1,"baseUrl":"https://upos-a.bilivideo.com/low"},{"bandwidth":9,"baseUrl":"https://upos-a.bilivideo.com/high"}]}})");
    const Stream best = parse_stream(data, 0);
    CHECK(best.quality == 80);
    CHECK(best.video == "https://upos-a.bilivideo.com/80");
    CHECK(best.audio == "https://upos-a.bilivideo.com/high");
    const Stream limited = parse_stream(data, 64);
    CHECK(limited.video == "https://upos-b.bilivideo.com/64");
    CHECK_THROWS(parse_stream(data, 16));
    CHECK_THROWS(parse_stream(Json::parse(R"({"durl":[{"url":"https://a.bilivideo.com/1"},{"url":"https://a.bilivideo.com/2"}]})"), 0));
}
TEST_CASE("player info, subtitles and resume") {
    const PlayerInfo info = parse_player_info(Json::parse(R"({"last_play_cid":22,"last_play_time":125000,
        "subtitle":{"subtitles":[{"lan":"ai-zh","lan_doc":"中文（AI）","subtitle_url":"//aisubtitle.hdslb.com/x.json"},{"lan":"zh-Hans","lan_doc":"中文","subtitle_url":"//a.hdslb.com/y.json"}]}})"));
    CHECK(info.last_seconds == 125);
    CHECK(preferred_subtitle(info.subtitles)->language == "zh-Hans");
    CHECK(subtitle_to_srt(Json::parse(R"({"body":[{"from":1.5,"to":3,"content":"你好"},{"from":"bad","to":1,"content":"skip"},{"from":3,"to":4,"content":"  "}]})")) ==
          "1\n00:00:01,500 --> 00:00:03,000\n你好\n\n");
    Details details;
    details.video.parts = {{11, 1, "一", 600}, {22, 2, "二", 600}, {33, 3, "三", 600}};
    details.info = {22, 125, {}};
    CHECK(resume_point(details) == std::pair<size_t, uint64_t>{1, 125});
    details.info = {22, 590, {}};
    CHECK(resume_point(details) == std::pair<size_t, uint64_t>{2, 0});
    details.info = {33, 599, {}};
    CHECK(resume_point(details) == std::pair<size_t, uint64_t>{2, 0});
    details.info = {};
    CHECK(resume_point(details) == std::pair<size_t, uint64_t>{0, 0});
}
TEST_CASE("series continuation") {
    PlayItem item;
    item.video.bvid = "A";
    item.video.parts = {{1, 1, "", 0}, {2, 2, "", 0}};
    item.start = 90;
    const auto second = next_in_series(item);
    REQUIRE(second);
    CHECK(second->part == 1);
    CHECK(second->start == 0);
    CHECK_FALSE(next_in_series(*second));
    Video a, b;
    a.bvid = "A";
    b.bvid = "B";
    PlayItem last = *second;
    last.video.collection = {a, b};
    const auto episode = next_in_series(last);
    REQUIRE(episode);
    CHECK(episode->video.bvid == "B");
    CHECK(episode->video.collection.size() == 2);
    CHECK_FALSE(next_in_series(*episode));
}
TEST_CASE("cover decoding rejects bad data") {
    CHECK_FALSE(decode_jpeg(""));
    CHECK_FALSE(decode_jpeg("not a jpeg"));
    CHECK_FALSE(decode_jpeg(std::string("\xff\xd8\xff\xe0", 4) + std::string(50, '\x41')));
}
TEST_CASE("filenames and config") {
    CHECK(safe_filename("a/b:c\x01") == "a_b_c");
    CHECK(safe_filename("...") == "video");
    const Config config = parse_config("report_history = false # off\ndownload_dir = \"/tmp/x\"\ndanmaku = true\n[danmaku_options]\nsubtitles = false\n");
    CHECK_FALSE(config.report_history);
    CHECK(config.download_dir == "/tmp/x");
    CHECK(config.subtitles);
}
TEST_CASE("input parser") {
    InputParser parser;
    auto events = parser.feed("a\xe4\xb8\xad\x1b[A\x1b[3~\r\t");
    REQUIRE(events.size() == 6);
    CHECK(events[0].key.is(U'a'));
    CHECK(events[1].key.is(U'中'));
    CHECK(events[2].key.code == KeyCode::Up);
    CHECK(events[3].key.code == KeyCode::Delete);
    CHECK(events[4].key.code == KeyCode::Enter);
    CHECK(events[5].key.code == KeyCode::Tab);
    CHECK(parser.feed("\xe4\xb8").empty());
    events = parser.feed("\xad");
    REQUIRE(events.size() == 1);
    CHECK(events[0].key.is(U'中'));
    CHECK(parser.feed("\x1b").empty());
    events = parser.flush();
    REQUIRE(events.size() == 1);
    CHECK(events[0].key.code == KeyCode::Escape);
    events = parser.feed("\x1b[200~line\nq\x1b[201~q");
    REQUIRE(events.size() == 2);
    CHECK(events[0].type == InputEvent::Type::Paste);
    CHECK(events[0].paste == "line\nq");
    CHECK(events[1].key.is(U'q'));
    events = parser.feed("\x1b[200~ab\x1b[20");
    CHECK(events.empty());
    events = parser.feed("1~");
    REQUIRE(events.size() == 1);
    CHECK(events[0].paste == "ab");
    events = parser.feed("\x1b[<0;5;7M\x1b[<0;5;7m\x1b[<65;1;1M\x1b[I\x1b[O\x1b\x7f\x01");
    REQUIRE(events.size() == 6);
    CHECK(events[0].type == InputEvent::Type::MouseClick);
    CHECK(events[0].x == 4);
    CHECK(events[0].y == 6);
    CHECK(events[1].type == InputEvent::Type::WheelDown);
    CHECK(events[2].type == InputEvent::Type::FocusIn);
    CHECK(events[3].type == InputEvent::Type::FocusOut);
    CHECK(events[4].key.code == KeyCode::Backspace);
    CHECK(events[4].key.alt);
    CHECK(events[5].key.ctrl);
    CHECK(events[5].key.ch == U'a');
}
TEST_CASE("text input") {
    TextInput input;
    input.paste("Apple\n中文");
    CHECK(input.str() == "Apple 中文");
    Key home{KeyCode::Home};
    input.handle(home);
    Key letter{KeyCode::Char, U'中'};
    CHECK(input.handle(letter));
    CHECK(input.str() == "中Apple 中文");
    CHECK(input.before_cursor() == "中");
    Key end{KeyCode::End};
    input.handle(end);
    Key word{KeyCode::Char, U'w', true};
    CHECK(input.handle(word));
    CHECK(input.str() == "中Apple ");
    Key alt{KeyCode::Char, U'x', false, true};
    CHECK_FALSE(input.handle(alt));
    input.paste("\x1b[31m");
    CHECK(input.str() == "中Apple [31m");
}
TEST_CASE("starts in the search box and Enter plays with resume") {
    App app(anonymous(), parse_config(""), true);
    CHECK(app.focus() == Focus::Input);
    const std::string first = frame(app);
    CHECK(contains(first, "最相关"));
    CHECK(contains(first, "最近搜索"));
    app.handle(paste("信号"));
    CHECK(app.input_text() == "信号");
    // Letters typed in the box are text, not shortcuts.
    app.handle(ch(U'q'));
    CHECK(app.input_text() == "信号q");
    app.handle(press(KeyCode::Enter));
    CHECK(app.focus() == Focus::List);
    REQUIRE(app.selected_video());
    Details details;
    details.video = *app.selected_video();
    details.info = {2002, 90, {}};
    app.put_details(details);
    const std::string preview = frame(app);
    CHECK(contains(preview, "已看到"));
    CHECK(contains(preview, "P2"));
    CHECK(contains(preview, "分 P"));
    app.handle(press(KeyCode::Enter));
    REQUIRE(app.demo_played().size() == 1);
    CHECK(app.demo_played()[0].part == 1);
    CHECK(app.demo_played()[0].start == 90);
}
TEST_CASE("parts panel plays a chosen episode") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    Details details;
    details.video = *app.selected_video();
    app.put_details(details);
    app.handle(press(KeyCode::Right));
    CHECK(app.focus() == Focus::Parts);
    app.handle(ch(U'j'));
    app.handle(ch(U'j'));
    CHECK(contains(frame(app), "第 3 讲"));
    app.handle(press(KeyCode::Enter));
    REQUIRE(app.demo_played().size() == 1);
    CHECK(app.demo_played()[0].part == 2);
    CHECK(app.demo_played()[0].start == 0);
    app.handle(press(KeyCode::Left));
    CHECK(app.focus() == Focus::List);
}
TEST_CASE("local filter keeps identity and restores on Esc") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    app.handle(ch(U'j'));
    const std::string key = app.selected_video()->key();
    app.handle(ch(U'/'));
    CHECK(app.focus() == Focus::Filter);
    app.handle(paste("fuliye"));
    CHECK(app.list().visible.size() == 1);
    CHECK(app.selected_video()->key() == key);
    // q edits the filter rather than quitting.
    CHECK_FALSE(app.handle(ch(U'q')));
    CHECK(app.list().visible.empty());
    CHECK(contains(frame(app), "没有匹配"));
    app.handle(press(KeyCode::Escape));
    CHECK(app.list().filter.empty());
    CHECK(app.list().visible.size() == 5);
    CHECK(app.selected_video()->key() == key);
    app.handle(ch(U'/'));
    app.handle(paste("nix"));
    app.handle(press(KeyCode::Enter));
    CHECK(app.focus() == Focus::List);
    app.handle(press(KeyCode::Escape));
    CHECK(app.list().filter.empty());
}
TEST_CASE("list rendering highlights matches and survives tiny sizes") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    app.handle(ch(U'/'));
    app.handle(paste("fuliye"));
    ftxui::Screen screen(120, 30);
    app.draw(screen);
    bool yellow = false;
    for (int y = 0; y < 30; ++y) {
        for (int x = 0; x < 120; ++x) yellow = yellow || (screen.PixelAt(x, y).character == "傅" && screen.PixelAt(x, y).foreground_color == ftxui::Color::RGB(0xe5, 0xc0, 0x7b));
    }
    CHECK(yellow);
    for (const auto& size : {std::pair{1, 1}, {10, 3}, {80, 24}, {109, 24}, {110, 24}, {300, 100}}) frame(app, size.first, size.second);
    app.handle(press(KeyCode::Escape));
    app.handle(ch(U'?'));
    for (const auto& size : {std::pair{1, 1}, {10, 3}, {80, 24}}) frame(app, size.first, size.second);
    app.handle(press(KeyCode::Escape));
    app.handle(ch(U' '));
    REQUIRE(app.modal());
    CHECK(contains(frame(app), "更多"));
    for (const auto& size : {std::pair{1, 1}, {10, 3}, {80, 24}}) frame(app, size.first, size.second);
    app.handle(press(KeyCode::Escape));
    CHECK_FALSE(app.modal());
}
TEST_CASE("headers are skipped, appended pages dedupe") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    Page page;
    Video header;
    header.kind = Kind::Header;
    header.title = "稍后再看";
    Video a, b;
    a.bvid = "A";
    a.title = "甲";
    b.bvid = "B";
    b.title = "乙";
    Video second_header = header;
    second_header.title = "继续学习";
    page.items = {header, a, second_header, b};
    const uint64_t id = app.list().id;
    app.apply_page(id, page, false);
    REQUIRE(app.selected_video());
    CHECK(app.selected_video()->bvid == "A");
    app.handle(ch(U'j'));
    CHECK(app.selected_video()->bvid == "B");
    app.handle(ch(U'j'));
    CHECK(app.selected_video()->bvid == "B");
    app.handle(ch(U'k'));
    app.handle(ch(U'k'));
    CHECK(app.selected_video()->bvid == "A");
    Page more;
    more.items = {b};
    app.apply_page(id, more, true);
    CHECK(app.list().items.size() == 4);
    app.apply_page(99999, more, true);
    CHECK(app.list().items.size() == 4);
}
TEST_CASE("first selection prefers videos over pinned accounts") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    Video user, video;
    user.kind = Kind::User;
    user.mid = 7;
    user.title = "讲课的 UP";
    video.bvid = "V";
    video.title = "课程";
    Page page;
    page.items = {user, video};
    app.apply_page(app.list().id, page, false);
    CHECK(app.selected_video()->bvid == "V");
    app.handle(ch(U'k'));
    CHECK(app.selected_video()->kind == Kind::User);
    page.items = {user};
    app.apply_page(app.list().id, page, false);
    CHECK(app.selected_video()->kind == Kind::User);
}
TEST_CASE("tabs, login gate and quit") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    app.handle(ch(U'2'));
    CHECK(app.tab() == TabId::Learn);
    app.handle(press(KeyCode::Tab));
    CHECK(app.tab() == TabId::Follow);
    app.handle(ch(U's'));
    CHECK(app.tab() == TabId::Search);
    CHECK(app.focus() == Focus::Input);
    app.handle(press(KeyCode::Escape));
    InputEvent click;
    click.type = InputEvent::Type::MouseClick;
    click.x = 10;
    click.y = 0;
    app.handle(click);
    CHECK(app.tab() == TabId::Learn);
    app.handle(ch(U'1'));
    CHECK(app.handle(ch(U'q')));
}
TEST_CASE("losing focus suspends passive deadlines") {
    App app(anonymous(), parse_config(""), true);
    app.handle(press(KeyCode::Escape));
    app.handle(ch(U'j'));
    CHECK(app.next_deadline());
    InputEvent out;
    out.type = InputEvent::Type::FocusOut;
    app.handle(out);
    CHECK_FALSE(app.focused());
    CHECK_FALSE(app.next_deadline());
    InputEvent in;
    in.type = InputEvent::Type::FocusIn;
    app.handle(in);
    CHECK(app.next_deadline());
}
TEST_CASE("base64") {
    CHECK(base64("") == "");
    CHECK(base64("f") == "Zg==");
    CHECK(base64("fo") == "Zm8=");
    CHECK(base64("foo") == "Zm9v");
}
