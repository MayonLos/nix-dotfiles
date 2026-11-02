// Ports the Rust tests of packages/mayon-tui/crates/keys/src/{model,lib}.rs and the search
// tests that apply, and compares the CLI against output recorded from the Rust tool.
// Only reads tests/fixtures; the default data path is exercised through a redirected env.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <filesystem>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <ftxui/screen/color.hpp>
#include <ftxui/screen/screen.hpp>
#include <numeric>
#include <sstream>

#include "app.hpp"
#include "page.hpp"
#include "ui/text.hpp"

using namespace keys;
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;

namespace {
const std::string kFixtures = FIXTURES;
std::vector<Entry> model(std::vector<Binding> rows) { return entries(Export{1, std::move(rows)}); }
Binding binding(const std::string& mode, const std::string& kind, const std::string& raw) { return Binding{mode, kind, raw}; }
std::vector<Entry> sample() {
    return model({binding("default", "bind", "SUPER+SHIFT,K,focusdir,up"), binding("default", "bind", "SHIFT+SUPER,k,spawn,未知动作中文测试"), binding("resize", "bind", "NONE,Escape,setkeymode,default")});
}
std::string slurp(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    REQUIRE(file.good());
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}
InputEvent key(KeyCode code) {
    InputEvent event;
    event.key.code = code;
    return event;
}
InputEvent ch(char32_t value, bool ctrl = false, bool alt = false) {
    InputEvent event;
    event.key = Key{KeyCode::Char, value, ctrl, alt};
    return event;
}
InputEvent paste(const std::string& text) {
    InputEvent event;
    event.type = InputEvent::Type::Paste;
    event.paste = text;
    return event;
}
InputEvent mouse(InputEvent::Type type, int x = 0, int y = 0) {
    InputEvent event;
    event.type = type;
    event.x = x;
    event.y = y;
    return event;
}
void set_query(KeysPage& page, const std::string& text) {
    page.handle(ch(U'/'));
    page.handle(paste(text));
    page.handle(key(KeyCode::Enter));
}
std::string text_of(ftxui::Screen& screen) {
    std::string out;
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) out += screen.PixelAt(x, y).character;
        out += "\n";
    }
    return out;
}
ftxui::Screen render(KeysPage& page, int width, int height) {
    ftxui::Screen screen(width, height);
    page.draw(screen, tui::Rect{0, 0, width, height});
    return screen;
}
bool any_cell_with_fg(ftxui::Screen& screen, uint32_t color) {
    const auto wanted = ftxui::Color::RGB((color >> 16) & 255, (color >> 8) & 255, color & 255);
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) {
            if (screen.PixelAt(x, y).foreground_color == wanted && screen.PixelAt(x, y).character != " ") return true;
        }
    }
    return false;
}
struct Cli {
    int code = 0;
    std::string out;
    std::string err;
};
Cli cli(const std::vector<std::string>& args) {
    std::ostringstream out, err;
    const int code = run_cli(args, out, err);
    return Cli{code, out.str(), err.str()};
}
std::string scratch_file(const std::string& name, const std::string& body) {
    const auto path = std::filesystem::temp_directory_path() /
                      ("keys-test-" + name + "-" + std::to_string(::getpid()) + ".json");
    std::ofstream(path, std::ios::binary) << body;
    return path.string();
}
}  // namespace

TEST_CASE("keeps unknown actions and every input row") {
    const auto result = model({binding("default", "bind", "SUPER+SHIFT,X,brand_new_action,arg,more")});
    REQUIRE(result.size() == 1);
    CHECK(result[0].description == "brand_new_action arg more");
    CHECK(result[0].binding.raw == "SUPER+SHIFT,X,brand_new_action,arg,more");
}
TEST_CASE("marks identical chords that share a mode or the common mode") {
    const auto result = model({binding("default", "bind", "SUPER+CTRL,X,one"), binding("default", "bindl", "CTRL+SUPER,x,two"), binding("common", "bind", "SUPER+CTRL,X,three"), binding("resize", "bind", "SUPER+CTRL,X,four")});
    CHECK((result[0].conflict && result[1].conflict && result[2].conflict));
    CHECK(result[3].conflict);
    CHECK(result[0].chord == "Super+Ctrl+X");
}
TEST_CASE("keeps mouse and gestures in separate device domains") {
    const auto result = model({binding("default", "bind", "SUPER,Left,one"), binding("default", "mousebind", "SUPER,btn_left,two"), binding("default", "gesturebind", "none,left,4,one")});
    for (const Entry& entry : result) CHECK_FALSE(entry.conflict);
    CHECK(result[2].chord.find("4指滑动") != std::string::npos);
}
TEST_CASE("non-common different modes do not conflict") {
    const auto result = model({binding("default", "bind", "NONE,Escape,one"), binding("resize", "bind", "NONE,Escape,two"), binding("Resize", "bind", "NONE,Escape,three"), binding("Resize", "bind", "NONE,Escape,four"), binding("Common", "bind", "NONE,Escape,five")});
    CHECK_FALSE(result[0].conflict);
    CHECK_FALSE(result[1].conflict);
    CHECK((result[2].conflict && result[3].conflict));
    CHECK_FALSE(result[4].conflict);
}
TEST_CASE("system spawn actions and mouse resize are grouped by purpose") {
    const auto result = model({
        binding("default", "bind", "SUPER,L,spawn,noctalia msg session lock"),
        binding("default", "bind", "SUPER,D,spawn,noctalia msg notification-dnd-toggle"),
        binding("default", "bind", "SUPER,I,spawn,noctalia msg caffeine-toggle"),
        binding("default", "bind", "SUPER,S,spawn,noctalia msg panel-toggle control-center"),
        binding("default", "bind", "SUPER,X,spawn,noctalia msg wallpaper-random"),
        binding("default", "bind", "SUPER,B,spawn,noctalia msg brightness-up"),
        binding("default", "bind", "SUPER,T,spawn,unknown-command"),
        binding("default", "bind", "ALT,Tab,spawn,noctalia msg window-switcher hold"),
        binding("default", "mousebind", "SUPER,btn_right,moveresize,curresize"),
    });
    for (size_t i = 0; i < 6; ++i) CHECK(result[i].group == 6);
    CHECK(result[6].group == 2);
    CHECK(result[7].group == 0);
    CHECK(result[8].group == 0);
}
TEST_CASE("previous and next tracks belong to media") {
    const auto result = model({binding("common", "bindl", "NONE,XF86AudioPrev,spawn,playerctl previous"), binding("common", "bindl", "NONE,XF86AudioNext,spawn,playerctl next")});
    for (const Entry& entry : result) CHECK(entry.group == 5);
}
TEST_CASE("toolbox, bilibili and release voice bindings have current descriptions") {
    const auto result = model({
        binding("default", "bind", "SUPER+SHIFT,D,toggle_named_scratchpad,mayon-tools,none,kitty mayon-tools"),
        binding("default", "bind", "SUPER+SHIFT,B,toggle_named_scratchpad,mayon-bili,none,kitty bilitui"),
        binding("default", "bindr", "SUPER+SHIFT,XF86Assistant,spawn,/nix/store/fixture-mayon-voice/bin/mayon-voice toggle"),
    });
    CHECK(result[0].description == "呼出或隐藏工具箱");
    CHECK(result[1].description == "呼出或隐藏 Bilibili TUI");
    CHECK(result[2].chord == "Super+Shift+XF86Assistant");
    CHECK(result[2].description.starts_with("松开"));
}
TEST_CASE("fuzzy matching is case insensitive and supports chinese subsequences") {
    CHECK(Matcher("super x").matches("Super+Shift+X 打开工具箱"));
    CHECK(Matcher("文件管").matches("呼出或隐藏文件管理器 Yazi"));
    CHECK_FALSE(Matcher("浏览器").matches("打开文件管理器"));
    CHECK(Matcher("").matches("anything"));
}
TEST_CASE("control alias and gesture modifiers are normalized") {
    const auto result = model({binding("default", "bind", "CTRL,X,one"), binding("default", "bind", "CONTROL,x,two"), binding("default", "gesturebind", "NONE,left,4,toggleoverview"), binding("default", "gesturebindl", "CTRL,left,4,toggleoverview")});
    CHECK((result[0].conflict && result[1].conflict));
    CHECK(result[3].chord == "Ctrl + 4指滑动 左");
    CHECK(result[2].description.find("切换窗口概览") != std::string::npos);
}
TEST_CASE("mouse actions and unknown scratchpads keep readable descriptions") {
    const auto result = model({binding("default", "mousebind", "SUPER,btn_left,moveresize,curmove"), binding("default", "bind", "SUPER,X,toggle_named_scratchpad,custom-tool,none,run custom"), binding("default", "bind", "SUPER,F1,spawn,${kitty} --title Mango-keybindings less keys.txt")});
    CHECK(result[0].description == "按住拖动窗口");
    CHECK(result[1].description.find("toggle_named_scratchpad custom-tool") != std::string::npos);
    CHECK(result[2].description == "查看 Mango 快捷键说明");
}
TEST_CASE("search ports: literal, pinyin, subsequence limits and scoring") {
    const Ranges hk{{2, 3}};
    CHECK(Matcher("港").find_in(SearchText("香香港"))->ranges == hk);
    const Ranges region{{2, 4}};
    CHECK(Matcher("xianggang").find_in(SearchText("地区香港"))->ranges == region);
    CHECK(Matcher("xg").find_in(SearchText("地区香港"))->ranges == region);
    const Ranges all{{0, 4}};
    CHECK(Matcher("xiangganghk").find_in(SearchText("香港HK"))->ranges == all);
    CHECK_FALSE(Matcher("xg").matches("xyz"));
    CHECK_FALSE(Matcher("xggs").matches("香" + std::string(27, '-') + "港" + std::string(27, '-') + "高" + std::string(27, '-') + "速"));
    CHECK(Matcher("xggs").matches("🇭🇰 香港 HK 高速 01"));
    CHECK(Matcher("xiang 01").matches("香港节点 01"));
    CHECK_FALSE(Matcher("xiang missing").matches("香港节点 01"));
    CHECK(Matcher("alpha").find_in(SearchText("alpha"))->score > Matcher("ap").find_in(SearchText("alpha"))->score);
    CHECK(Matcher("abc").matches("a_b_c"));
    CHECK_FALSE(Matcher("abc").matches("a" + std::string(39, '-') + "b" + std::string(39, '-') + "c"));
    CHECK_FALSE(Matcher("apple tokyo").matches("Apple node"));
    CHECK_FALSE(Matcher("apple tokyo").highlight("Apple node").empty());
    // One letter never falls back to a subsequence.
    CHECK_FALSE(Matcher("z").matches("abc"));
}
TEST_CASE("a single filtered group uses one full width column") {
    KeysPage page(sample());
    set_query(page, "未知动作中文测试");
    auto screen = render(page, 160, 24);
    CHECK(page.visible().size() == 1);
    CHECK(page.columns() == 1);
}
TEST_CASE("all sizes, search and raw detail render") {
    for (const int width : {35, 60, 90, 140}) {
        KeysPage page(sample());
        auto screen = render(page, width, 30);
        CHECK(screen.PixelAt(1, 0).character == "快");
        CHECK(any_cell_with_fg(screen, tui::kRed));
        CHECK(text_of(screen).find("Super") != std::string::npos);
        page.handle(key(KeyCode::Enter));
        CHECK(page.details());
        render(page, width, 30);
        page.handle(key(KeyCode::Escape));
        set_query(page, "没有任何匹配");
        render(page, width, 30);
        CHECK(page.visible().empty());
    }
}
TEST_CASE("the filter keeps identity and reports empty") {
    KeysPage page(sample());
    // Rows sort by group, so binding 1 (a spawn) comes last.
    page.handle(ch(U'G'));
    REQUIRE(page.visible()[page.selected()] == 1);
    page.handle(ch(U'/'));
    page.handle(paste("zhongwen"));
    CHECK(page.visible().size() == 1);
    CHECK(page.visible()[page.selected()] == 1);
    page.handle(key(KeyCode::Enter));
    set_query(page, "zzzzzzzzzz");
    CHECK(page.selected() == 0);
    auto screen = render(page, 90, 30);
    std::string text = text_of(screen);
    text.erase(std::remove(text.begin(), text.end(), ' '), text.end());
    CHECK(text.find("没有匹配") != std::string::npos);
    CHECK(text.find("Esc") != std::string::npos);
}
TEST_CASE("tiny windows render without crashing, in every state") {
    for (const int width : {1, 2, 8, 20}) {
        for (const int height : {1, 2, 5}) {
            KeysPage page(sample());
            render(page, width, height);
            page.handle(ch(U'/'));
            render(page, width, height);
            page.handle(key(KeyCode::Enter));
            page.handle(key(KeyCode::Enter));
            render(page, width, height);
            page.handle(key(KeyCode::Escape));
            page.handle(ch(U'?'));
            render(page, width, height);
        }
    }
}
TEST_CASE("the group layout covers every binding once") {
    const auto items = sample();
    KeysPage page(items);
    const auto visible = page.visible();
    for (size_t columns = 1; columns <= 3; ++columns) {
        std::vector<size_t> seen;
        for (const Position& position : layout_rows(items, visible, columns).positions) {
            if (position.selection) seen.push_back(*position.selection);
        }
        std::sort(seen.begin(), seen.end());
        std::vector<size_t> wanted(items.size());
        std::iota(wanted.begin(), wanted.end(), 0);
        CHECK(seen == wanted);
    }
}
TEST_CASE("column count follows the width thresholds") {
    CHECK(columns_for(87, 7) == 1);
    CHECK(columns_for(88, 7) == 2);
    CHECK(columns_for(137, 7) == 2);
    CHECK(columns_for(138, 7) == 3);
    CHECK(columns_for(138, 1) == 1);
    CHECK(columns_for(138, 0) == 1);
}
TEST_CASE("keys: groups, movement and quit") {
    const auto items = entries(parse_export(slurp(kFixtures + "/bindings.json")));
    KeysPage page(items);
    render(page, 90, 30);
    for (char32_t digit = U'1'; digit <= U'7'; ++digit) {
        page.handle(ch(digit));
        REQUIRE(page.group() == static_cast<size_t>(digit - U'1'));
        for (const size_t i : page.visible()) CHECK(items[i].group == *page.group());
    }
    page.handle(ch(U'8'));
    CHECK(page.group() == 6U);
    page.handle(ch(U'0'));
    CHECK_FALSE(page.group().has_value());
    const size_t last = page.visible().size() - 1;
    page.handle(ch(U'j'));
    CHECK(page.selected() == 1);
    page.handle(ch(U'k'));
    page.handle(ch(U'k'));
    CHECK(page.selected() == 0);
    page.handle(ch(U'G'));
    CHECK(page.selected() == last);
    page.handle(key(KeyCode::Down));
    CHECK(page.selected() == last);
    page.handle(key(KeyCode::Home));
    CHECK(page.selected() == 0);
    page.handle(key(KeyCode::End));
    CHECK(page.selected() == last);
    page.handle(ch(U'g'));
    CHECK(page.selected() == 0);
    render(page, 90, 12);
    page.handle(key(KeyCode::PageDown));
    render(page, 90, 12);
    CHECK(page.scroll() > 0);
    page.handle(key(KeyCode::PageUp));
    render(page, 90, 12);
    CHECK(page.scroll() == 0);
    // Scrolling does not move the selection and modifiers do nothing on the list.
    CHECK(page.selected() == 0);
    CHECK_FALSE(page.handle(ch(U'q', false, true)));
    CHECK_FALSE(page.handle(ch(U'j', true)));
    CHECK(page.selected() == 0);
    CHECK(page.handle(ch(U'c', true)));
    CHECK(page.handle(ch(U'q')));
    CHECK(page.handle(key(KeyCode::Escape)));
}
TEST_CASE("search: q is text, Esc restores, Enter keeps, list Esc clears before quitting") {
    KeysPage page(sample());
    set_query(page, "super");
    const size_t kept = page.visible().size();
    page.handle(ch(U'/'));
    CHECK(page.editing());
    CHECK_FALSE(page.handle(ch(U'q')));
    CHECK(page.query() == "superq");
    page.handle(key(KeyCode::Backspace));
    page.handle(ch(U'w', true));
    CHECK(page.query().empty());
    page.handle(key(KeyCode::Escape));
    CHECK_FALSE(page.editing());
    CHECK(page.query() == "super");
    CHECK(page.visible().size() == kept);
    CHECK_FALSE(page.handle(key(KeyCode::Escape)));
    CHECK(page.query().empty());
    CHECK(page.handle(key(KeyCode::Escape)));
}
TEST_CASE("search: arrows select while typing, and the cursor exists only while editing") {
    KeysPage page(sample());
    render(page, 90, 30);
    CHECK_FALSE(page.cursor().has_value());
    page.handle(ch(U'/'));
    render(page, 90, 30);
    REQUIRE(page.cursor().has_value());
    CHECK(page.cursor()->second == 2);
    const int empty_x = page.cursor()->first;
    page.handle(ch(U'中'));
    render(page, 90, 30);
    CHECK(page.cursor()->first == empty_x + 2);
    page.handle(key(KeyCode::Enter));
    page.handle(ch(U'0'));
    page.handle(ch(U'/'));
    page.handle(ch(U'k', true));
    page.handle(ch(U'u', true));
    CHECK(page.query().empty());
    const size_t at = page.selected();
    page.handle(key(KeyCode::Up));
    CHECK(page.selected() == at - 1);
    page.handle(key(KeyCode::Down));
    CHECK(page.selected() == at);
    // A long query keeps the cursor inside a narrow row.
    page.handle(paste(std::string(200, 'x')));
    render(page, 40, 30);
    CHECK(page.cursor()->first < 40);
}
TEST_CASE("paste only reaches the query while editing and joins lines") {
    KeysPage page(sample());
    page.handle(paste("ignored"));
    CHECK(page.query().empty());
    page.handle(ch(U'/'));
    page.handle(paste("a\nb"));
    CHECK(page.query() == "a b");
    page.handle(ch(U'u', true));
    page.handle(key(KeyCode::Enter));
    page.handle(ch(U'?'));
    page.handle(paste("ignored"));
    CHECK(page.query().empty());
}
TEST_CASE("help and details own their keys") {
    KeysPage page(sample());
    render(page, 90, 30);
    page.handle(ch(U'?'));
    CHECK(page.help());
    auto help = render(page, 90, 30);
    CHECK(text_of(help).find("数据文件") != std::string::npos);
    page.handle(ch(U'j'));
    CHECK(page.selected() == 0);
    page.handle(mouse(InputEvent::Type::WheelDown));
    CHECK(page.scroll() == 0);
    page.handle(key(KeyCode::Escape));
    CHECK_FALSE(page.help());
    page.handle(ch(U'?'));
    page.handle(ch(U'?'));
    CHECK_FALSE(page.help());
    page.handle(ch(U'?'));
    CHECK(page.handle(ch(U'q')));
    page.handle(key(KeyCode::Escape));

    page.handle(key(KeyCode::Enter));
    CHECK(page.details());
    auto details = render(page, 90, 30);
    CHECK(text_of(details).find("SUPER+SHIFT,K,focusdir,up") != std::string::npos);
    page.handle(key(KeyCode::Down));
    CHECK(page.detail_scroll() == 1);
    page.handle(mouse(InputEvent::Type::WheelDown));
    CHECK(page.detail_scroll() == 3);
    page.handle(mouse(InputEvent::Type::WheelUp));
    page.handle(key(KeyCode::Up));
    page.handle(key(KeyCode::Up));
    CHECK(page.detail_scroll() == 0);
    page.handle(key(KeyCode::Enter));
    CHECK_FALSE(page.details());
    page.handle(key(KeyCode::Enter));
    CHECK(page.handle(ch(U'q')));
}
TEST_CASE("a long raw action wraps completely in the details") {
    const std::string tail(150, 'z');
    KeysPage page(model({binding("default", "bind", "SUPER,A,spawn," + tail + "END")}));
    page.handle(key(KeyCode::Enter));
    auto screen = render(page, 60, 30);
    CHECK(text_of(screen).find("END") != std::string::npos);
}
TEST_CASE("mouse: tabs and rows are clickable, the wheel scrolls without following") {
    const auto items = entries(parse_export(slurp(kFixtures + "/bindings.json")));
    KeysPage page(items);
    auto screen = render(page, 90, 14);
    // Tab row is y=1, tabs start at x=1: "0 全部" then "1 窗口".
    const int second_tab = 1 + tui::width_of("0 全部") + 2;
    page.handle(mouse(InputEvent::Type::MouseClick, second_tab, 1));
    CHECK(page.group() == 0U);
    render(page, 90, 14);
    page.handle(mouse(InputEvent::Type::MouseClick, 1, 1));
    CHECK_FALSE(page.group().has_value());
    render(page, 90, 14);
    // y=3 is the first group label, y=5 the second row of that group.
    page.handle(mouse(InputEvent::Type::MouseClick, 5, 5));
    CHECK(page.selected() == 1);
    page.handle(mouse(InputEvent::Type::WheelDown));
    render(page, 90, 14);
    CHECK(page.scroll() == 3);
    CHECK(page.selected() == 1);
    page.handle(mouse(InputEvent::Type::WheelUp));
    render(page, 90, 14);
    CHECK(page.scroll() == 0);
}
TEST_CASE("a resize brings the selection back into view") {
    const auto items = entries(parse_export(slurp(kFixtures + "/bindings.json")));
    KeysPage page(items);
    render(page, 60, 40);
    page.handle(ch(U'j'));
    page.handle(ch(U'j'));
    page.handle(ch(U'j'));
    page.handle(ch(U'j'));
    render(page, 60, 40);
    CHECK(page.scroll() == 0);
    render(page, 60, 10);
    CHECK(page.scroll() > 0);
}
TEST_CASE("the list command matches output recorded from the Rust tool, byte for byte") {
    const std::string data = kFixtures + "/bindings.json";
    const Cli json = cli({"--data", data, "list", "--json"});
    CHECK(json.code == 0);
    CHECK(json.err.empty());
    CHECK(json.out == slurp(kFixtures + "/list.json"));
    const Cli text = cli({"list", "--data", data});
    CHECK(text.code == 0);
    CHECK(text.out == slurp(kFixtures + "/list.txt"));
    // Flag order is free and the last --data wins for the listing.
    CHECK(cli({"--json", "--data", "/nonexistent", "--data", data, "list"}).out == json.out);
    const std::string empty = scratch_file("empty.json", R"({"version":1,"bindings":[]})");
    CHECK(cli({"--data", empty, "list", "--json"}).out == "[]\n");
    CHECK(cli({"--data", empty, "list"}).out == "\n窗口\n\n工作区\n\n应用\n\nTUI 工具\n\n截图\n\n媒体\n\n系统\n");
}
TEST_CASE("errors use the Rust tool's text and exit 1") {
    const auto expect = [](const std::vector<std::string>& args, const std::string& err) {
        const Cli result = cli(args);
        CHECK(result.code == 1);
        CHECK(result.out.empty());
        CHECK(result.err == err);
    };
    expect({"--bogus"}, "Error: 未知参数 --bogus，请运行 mayon-tools keys --help\n");
    expect({"--data"}, "Error: --data 需要路径\n");
    expect({"--json"}, "Error: --json 需要 list 子命令\n");
    expect({"list", "list"}, "Error: 未知参数 list，请运行 mayon-tools keys --help\n");
    expect({"--data", "/nonexistent/keys.json", "list"}, "Error: 无法读取 /nonexistent/keys.json；请先构建并安装 Mango 导出的 JSON，或指定 --data\n\nCaused by:\n    No such file or directory (os error 2)\n");
    expect({"--data", scratch_file("v2.json", R"({"version":2,"bindings":[]})"), "list"}, "Error: unsupported keybinding export version 2\n");
    expect({"--data", scratch_file("short.json", R"({"version":1,"bindings":[{"mode":"default","kind":"bind","raw":"a,b"}]})"), "list"}, "Error: invalid bind binding: a,b\n");
    for (const char* bad : {"nope", "", "[]", R"({"version":1})", R"({"bindings":[]})", R"({"version":-1,"bindings":[]})", R"({"version":1.5,"bindings":[]})", R"({"version":4294967296,"bindings":[]})", R"({"version":1,"bindings":[{"mode":"a","kind":"b"}]})", R"({"version":1,"bindings":[{"mode":1,"kind":"b","raw":"c"}]})"}) {
        const Cli result = cli({"--data", scratch_file("bad.json", bad), "list"});
        CHECK(result.code == 1);
        CHECK(result.err.starts_with("Error: 快捷键 JSON 格式无效\n\nCaused by:\n    "));
    }
    // The gesture form needs one field more.
    expect({"--data", scratch_file("g.json", R"({"version":1,"bindings":[{"mode":"default","kind":"gesturebind","raw":"none,left,4"}]})"), "list"}, "Error: invalid gesturebind binding: none,left,4\n");
}
TEST_CASE("help and version exit 0 at their place in the arguments") {
    CHECK(cli({"--version"}).out == "keys-mayon 0.1.0\n");
    CHECK(cli({"-V"}).code == 0);
    CHECK(cli({"--help"}).out.starts_with("mayon-tools keys [--data PATH] [list [--json]]\n"));
    CHECK(cli({"-h", "--bogus"}).code == 0);
    CHECK(cli({"--bogus", "-h"}).code == 1);
}
TEST_CASE("the default path honours the environment order") {
    setenv("KEYS_MAYON_DATA", "/fixture/data.json", 1);
    CHECK(default_data_path() == "/fixture/data.json");
    unsetenv("KEYS_MAYON_DATA");
    setenv("XDG_CONFIG_HOME", "/fixture/config", 1);
    CHECK(default_data_path() == "/fixture/config/keys-mayon/bindings.json");
    unsetenv("XDG_CONFIG_HOME");
    setenv("HOME", "/fixture/home", 1);
    CHECK(default_data_path() == "/fixture/home/.config/keys-mayon/bindings.json");
    unsetenv("HOME");
    CHECK_THROWS_AS(default_data_path(), Error);
    // Never reach the real config below.
    setenv("KEYS_MAYON_DATA", "/nonexistent/keys.json", 1);
}
TEST_CASE("the page shows a load failure and retries with R") {
    const std::string path = scratch_file("retry.json", "nope");
    KeysPage page{std::optional<std::string>(path)};
    REQUIRE(page.error().has_value());
    auto failed = render(page, 90, 20);
    CHECK(text_of(failed).find("快捷键 JSON 格式无效") != std::string::npos);
    tui::Page& base = page;
    CHECK_FALSE(base.handle(ch(U'/')));
    scratch_file("retry.json", R"({"version":1,"bindings":[{"mode":"default","kind":"bind","raw":"SUPER,A,zoom"}]})");
    CHECK_FALSE(page.handle(ch(U'R')));
    CHECK_FALSE(page.error().has_value());
    CHECK(page.visible().size() == 1);
    KeysPage missing{std::optional<std::string>("/nonexistent/keys.json")};
    REQUIRE(missing.error().has_value());
    CHECK(missing.error()->find("无法读取 /nonexistent/keys.json；请先安装 Mango 快捷键数据") != std::string::npos);
    CHECK(missing.handle(ch(U'q')));
    CHECK(missing.handle(key(KeyCode::Escape)));
    CHECK(missing.handle(ch(U'c', true)));
}
TEST_CASE("the public factories build pages and idle costs nothing") {
    const auto page = make_keys_page(kFixtures + "/bindings.json");
    CHECK_FALSE(page->next_deadline().has_value());
    page->set_active(false);
    CHECK_FALSE(page->next_deadline().has_value());
}
