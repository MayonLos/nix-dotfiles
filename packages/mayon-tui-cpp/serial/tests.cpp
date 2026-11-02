
// Ports the Rust crate's unit and integration tests: codec, store, transport state machine,
// capture limits, ANSI safety, the CLI contract, real PTY round trips and flash cancellation.
// Everything runs offline with private HOME/XDG directories; no real serial port is opened.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <ftxui/screen/color.hpp>
#include <ftxui/screen/screen.hpp>
#include <ftxui/screen/string.hpp>
#include <functional>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "app.hpp"
#include "codec.hpp"
#include "page.hpp"
#include "screen.hpp"
#include "store.hpp"
#include "transport.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"

using namespace serial;
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;

namespace {
const std::string kFixtures = FIXTURES;
using Clock = std::chrono::steady_clock;
using std::chrono::milliseconds;
using std::chrono::seconds;

Bytes bytes_of(std::string_view text) { return Bytes(text.begin(), text.end()); }

// ---------------------------------------------------------------------------------------
// Isolated filesystem and environment helpers.
// ---------------------------------------------------------------------------------------
struct TempDir {
    TempDir() {
        std::string name = (std::filesystem::temp_directory_path() / "serial-test-XXXXXX").string();
        if (mkdtemp(name.data()) == nullptr) throw std::runtime_error("mkdtemp failed");
        path = name;
    }
    ~TempDir() {
        std::error_code ignored;
        std::filesystem::remove_all(path, ignored);
    }
    TempDir(const TempDir&) = delete;
    TempDir& operator=(const TempDir&) = delete;
    std::filesystem::path path;
};
// Points HOME and the three XDG variables at a private tree, then restores them.
class PrivateHome {
public:
    explicit PrivateHome(const std::filesystem::path& root) {
        set("HOME", (root / "home").string());
        set("XDG_CONFIG_HOME", (root / "config").string());
        set("XDG_DATA_HOME", (root / "data").string());
        set("XDG_CACHE_HOME", (root / "cache").string());
    }
    ~PrivateHome() {
        for (size_t i = 0; i < names_.size(); ++i) {
            if (old_[i]) {
                setenv(names_[i], old_[i]->c_str(), 1);
            } else {
                unsetenv(names_[i]);
            }
        }
    }
    PrivateHome(const PrivateHome&) = delete;
    PrivateHome& operator=(const PrivateHome&) = delete;

private:
    void set(const char* name, const std::string& value) {
        const char* old = std::getenv(name);
        names_.emplace_back(name);
        old_.emplace_back(old == nullptr ? std::nullopt : std::optional<std::string>(old));
        setenv(name, value.c_str(), 1);
    }
    std::vector<const char*> names_;
    std::vector<std::optional<std::string>> old_;
};
mode_t mode_of(const std::filesystem::path& path) {
    struct stat info {};
    REQUIRE(::stat(path.c_str(), &info) == 0);
    return info.st_mode & 0777;
}
// ---------------------------------------------------------------------------------------
// Input and screen helpers for page tests.
// ---------------------------------------------------------------------------------------
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
// Same extraction rule as the Rust TestBackend helper: one glyph per cell, wide glyphs skip
// their continuation cell, every row ends with a newline.
std::string screen_text(ftxui::Screen& screen) {
    std::string out;
    for (int y = 0; y < screen.dimy(); ++y) {
        int skip = 0;
        for (int x = 0; x < screen.dimx(); ++x) {
            if (skip > 0) {
                --skip;
                continue;
            }
            const std::string& glyph = screen.PixelAt(x, y).character;
            out += glyph;
            skip = std::max(ftxui::string_width(glyph) - 1, 0);
        }
        out += '\n';
    }
    return out;
}
std::string render(SerialPage& page, int width, int height) {
    ftxui::Screen screen(width, height);
    page.draw(screen, tui::Rect{0, 0, width, height});
    return screen_text(screen);
}
struct PageFixture {
    TempDir dir;
    PrivateHome home{dir.path};
    SerialPage page;
    PageFixture() {
        page.app()->page = 0;
        page.app()->graph = false;
    }
};
std::string slurp(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    REQUIRE(file.good());
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}
Record record_of(const std::string& text, Bytes raw = {}) {
    Record record;
    record.clock = "12:00:00.000";
    record.stamp = "2026-01-01T12:00:00.000000+08:00";
    record.kind = "RX";
    record.raw = std::move(raw);
    record.text = text;
    return record;
}
// ---------------------------------------------------------------------------------------
// PTY helpers: posix_openpt avoids linking libutil.
// ---------------------------------------------------------------------------------------
struct Pty {
    int master = -1;
    std::filesystem::path slave;
};
Pty open_pty() {
    Pty pty;
    pty.master = ::posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    REQUIRE(pty.master >= 0);
    REQUIRE(::grantpt(pty.master) == 0);
    REQUIRE(::unlockpt(pty.master) == 0);
    const char* name = ::ptsname(pty.master);
    REQUIRE(name != nullptr);
    pty.slave = name;
    const int flags = ::fcntl(pty.master, F_GETFL);
    REQUIRE(::fcntl(pty.master, F_SETFL, flags | O_NONBLOCK) == 0);
    struct termios options {};
    REQUIRE(::tcgetattr(pty.master, &options) == 0);
    ::cfmakeraw(&options);
    REQUIRE(::tcsetattr(pty.master, TCSANOW, &options) == 0);
    return pty;
}
void link_pty(const std::filesystem::path& alias, const std::filesystem::path& slave) {
    std::error_code ignored;
    std::filesystem::remove(alias, ignored);
    std::filesystem::create_symlink(slave, alias);
}
Device pty_device(const std::filesystem::path& path) {
    Device device;
    device.path = path.string();
    device.product = "PTY test device";
    device.topology = path.string();
    return device;
}
std::optional<Event> await_event(Worker& worker, milliseconds timeout, const std::function<bool(const Event&)>& predicate) {
    const auto deadline = Clock::now() + timeout;
    while (Clock::now() < deadline) {
        const auto left = std::chrono::duration_cast<milliseconds>(deadline - Clock::now());
        if (left.count() <= 0) break;
        if (auto event = worker.rx->recv_timeout(left)) {
            if (predicate(*event)) return event;
        }
    }
    return std::nullopt;
}
bool await_connected(Worker& worker, const std::string& path, milliseconds timeout = seconds(3)) {
    return await_event(worker, timeout, [&](const Event& event) { return event.kind == Event::Kind::Connected && event.text == path; }).has_value();
}
Bytes await_rx(Worker& worker, size_t count, milliseconds timeout = seconds(3)) {
    Bytes received;
    const auto deadline = Clock::now() + timeout;
    while (received.size() < count && Clock::now() < deadline) {
        const auto left = std::chrono::duration_cast<milliseconds>(deadline - Clock::now());
        if (left.count() <= 0) break;
        if (auto event = worker.rx->recv_timeout(left); event && event->kind == Event::Kind::Rx) {
            received.insert(received.end(), event->bytes.begin(), event->bytes.end());
        }
    }
    received.resize(std::min(received.size(), count));
    return received;
}
Bytes read_master(int fd, size_t count, milliseconds timeout) {
    Bytes received;
    const auto deadline = Clock::now() + timeout;
    while (received.size() < count && Clock::now() < deadline) {
        const auto left = std::chrono::duration_cast<milliseconds>(deadline - Clock::now());
        pollfd descriptor{fd, POLLIN, 0};
        const int ready = ::poll(&descriptor, 1, static_cast<int>(std::max<long long>(left.count(), 1)));
        if (ready <= 0) continue;
        uint8_t buffer[4096];
        const ssize_t got = ::read(fd, buffer, std::min(sizeof buffer, count - received.size()));
        if (got > 0) received.insert(received.end(), buffer, buffer + got);
    }
    return received;
}
// Minimal RFC 4180 reader, the same helper the Rust app_flow test uses.
std::vector<std::string> parse_csv_row(const std::string& line) {
    std::vector<std::string> fields;
    std::string field;
    bool quoted = false;
    for (size_t i = 0; i < line.size(); ++i) {
        const char c = line[i];
        if (c == '"' && quoted && i + 1 < line.size() && line[i + 1] == '"') {
            field += '"';
            ++i;
        } else if (c == '"') {
            quoted = !quoted;
        } else if (c == ',' && !quoted) {
            fields.push_back(field);
            field.clear();
        } else {
            field += c;
        }
    }
    CHECK_FALSE(quoted);
    fields.push_back(field);
    return fields;
}
std::vector<std::string> split_lines(const std::string& text) {
    std::vector<std::string> lines;
    std::istringstream stream(text);
    for (std::string line; std::getline(stream, line);) lines.push_back(line);
    return lines;
}
}  // namespace

// ---------------------------------------------------------------------------------------
// codec.rs
// ---------------------------------------------------------------------------------------
TEST_CASE("utf8_and_gbk_round_trip") {
    const std::string chinese = "串口测试";
    for (const Encoding encoding : {Encoding::Utf8, Encoding::Gbk}) {
        const auto encoded = encode_text(encoding, chinese);
        REQUIRE(encoded.has_value());
        CHECK(decode_bytes(encoding, *encoded) == chinese);
    }
    CHECK_FALSE(encode_text(Encoding::Gbk, "🦀").has_value());
    CHECK(decode_bytes(Encoding::Utf8, Bytes{0xFF}) == "\xEF\xBF\xBD");
    CHECK(decode_bytes(Encoding::Gbk, Bytes{0x80}) == "€");
}
TEST_CASE("hex_accepts_groups_and_contiguous_bytes") {
    CHECK(*parse_hex("0x41 42, 0X43") == Bytes{'A', 'B', 'C'});
    CHECK(*parse_hex("414243") == Bytes{'A', 'B', 'C'});
    CHECK(parse_hex("abc").error() == "HEX 字节必须由偶数个十六进制数字组成");
    CHECK(parse_hex("0xGG").error() == "非法 HEX 字符：G");
    CHECK(parse_hex("   ").error() == "HEX 数据不能为空");
}
TEST_CASE("telemetry_requires_a_complete_finite_row") {
    const auto named = parse_values("a=1.2,b=3");
    REQUIRE(named.size() == 2);
    CHECK(named[0].first == "a");
    CHECK(named[0].second == doctest::Approx(1.2));
    CHECK(named[1].first == "b");
    CHECK(named[1].second == doctest::Approx(3.0));
    const auto positional = parse_values("1.5,-2");
    REQUIRE(positional.size() == 2);
    CHECK(positional[0].first == "ch1");
    CHECK(positional[1].first == "ch2");
    CHECK(parse_values("a=1,nan").empty());
    CHECK(parse_values("1,2,nope").empty());
    CHECK(parse_values("1,2,3").size() == 3);
    CHECK(parse_values("").empty());
    CHECK(parse_values("1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17").empty());
}
TEST_CASE("framing_handles_partial_crlf_and_caps_unterminated_lines") {
    Framer framer;
    const Bytes chinese = bytes_of("中文");
    CHECK(framer.push(std::span<const uint8_t>(chinese.data(), 3)).empty());
    CHECK(framer.push(std::span<const uint8_t>(chinese.data() + 3, chinese.size() - 3)).empty());
    const auto complete = framer.push(Bytes{'\r'});
    REQUIRE(complete.size() == 1);
    CHECK(std::string(complete[0].begin(), complete[0].end()) == "中文");
    const auto next = framer.push(bytes_of("\nnext\n"));
    REQUIRE(next.size() == 1);
    CHECK(std::string(next[0].begin(), next[0].end()) == "next");
    CHECK_FALSE(framer.flush().has_value());
    const auto tail = framer.push(bytes_of("tail\r"));
    REQUIRE(tail.size() == 1);
    CHECK(std::string(tail[0].begin(), tail[0].end()) == "tail");
    CHECK(framer.push(Bytes(Framer::kMaxLine + 100, 'x')).empty());
    CHECK(framer.pending().size() == Framer::kMaxLine);
    CHECK(framer.truncated());
}
TEST_CASE("ansi_keeps_sgr_and_drops_terminal_injection") {
    CHECK(plain("\x1b[31mERROR\x1b[0m\x1b]0;evil\x07\x1b[2J") == "ERROR");
    const auto spans = ansi_line("\x1b[38;2;1;2;3mvalue\x1b[0m");
    REQUIRE(spans.size() == 1);
    REQUIRE(spans[0].style.fg.has_value());
    CHECK(*spans[0].style.fg == 0x010203u);
    CHECK(spans[0].text == "value");
    // Cursor movement, OSC titles and C1 controls never reach the screen.
    CHECK(plain(std::string("a\x1b[2Jb\x1b]2;title" "\x07" "c")) == "abc");
    const auto emphasis = ansi_line("\x1b[1;4;31mhot\x1b[22;24;39m plain");
    REQUIRE(emphasis.size() == 2);
    CHECK(emphasis[0].style.bold);
    CHECK(emphasis[0].style.underline);
    CHECK_FALSE(emphasis[1].style.bold);
}

// ---------------------------------------------------------------------------------------
// store.rs
// ---------------------------------------------------------------------------------------
TEST_CASE("persistence_permissions_and_invalid_config") {
    TempDir dir;
    Store store = Store::at(dir.path / "config", dir.path / "data");
    store.remember("中文 status");
    store.save();
    CHECK(mode_of(store.config_path) == 0600);
    CHECK(mode_of(store.data) == 0700);
    const auto config_path = store.config_path;
    const Store reloaded = Store::at(config_path.parent_path(), store.data);
    REQUIRE(reloaded.history.size() == 1);
    CHECK(reloaded.history[0] == "中文 status");
    REQUIRE(reloaded.config.highlights.size() == 3);
    CHECK(reloaded.config.highlights[0] == "ERROR");
    CHECK(reloaded.config.scrollback == 100000);
    {
        std::ofstream file(config_path);
        file << "invalid";
    }
    CHECK_THROWS(Store::at(config_path.parent_path(), store.data));
    CHECK(slurp(config_path) == "invalid");
}
TEST_CASE("profile_json_round_trips_through_the_shared_format") {
    TempDir dir;
    Store store = Store::at(dir.path / "config", dir.path / "data");
    Profile profile;
    profile.settings.baud = 921600;
    profile.settings.bits = 7;
    profile.settings.parity = "even";
    profile.settings.stop = 2;
    profile.settings.flow = "hardware";
    profile.settings.dtr = true;
    profile.encoding = Encoding::Gbk;
    profile.ending = "LF";
    profile.flash = "true";
    profile.flash_dir = "/tmp";
    store.config.favorites.push_back(Favorite{"启动", "0x7F", true});
    store.config.devices["0000:0000:/dev/ttyUSB0:00"] = profile;
    store.save();
    const Store reloaded = Store::at(dir.path / "config", dir.path / "data");
    REQUIRE(reloaded.config.devices.count("0000:0000:/dev/ttyUSB0:00") == 1);
    const Profile& back = reloaded.config.devices.at("0000:0000:/dev/ttyUSB0:00");
    CHECK(back.settings.baud == 921600);
    CHECK(back.settings.parity == "even");
    CHECK(back.settings.flow == "hardware");
    CHECK(back.settings.dtr);
    CHECK(back.encoding == Encoding::Gbk);
    CHECK(back.ending == "LF");
    CHECK(back.flash == "true");
    REQUIRE(reloaded.config.favorites.size() == 1);
    CHECK(reloaded.config.favorites[0].name == "启动");
    CHECK(reloaded.config.favorites[0].hex);
}

// ---------------------------------------------------------------------------------------
// transport.rs identity and settings
// ---------------------------------------------------------------------------------------
TEST_CASE("stable_identity_prefers_serial_and_interface") {
    const auto device = [](const char* path, std::optional<std::string> serial, const char* topology, const char* interface) {
        Device item;
        item.path = path;
        item.vid = 0x0483;
        item.pid = 0x3748;
        item.serial = std::move(serial);
        item.product = "ST-Link";
        item.interface = interface;
        item.topology = topology;
        return item;
    };
    CHECK(device("/dev/ttyACM0", "A1", "1-2", "00").key() == device("/dev/ttyACM4", "A1", "1-7", "00").key());
    CHECK(device("/dev/ttyACM0", "A1", "1-2", "00").key() != device("/dev/ttyACM4", "A1", "1-7", "01").key());
}
TEST_CASE("topology_fallback_survives_tty_renumbering") {
    Device first;
    first.path = "/dev/ttyUSB0";
    first.vid = 0x1A86;
    first.pid = 0x7523;
    first.topology = "1-2.3|ch341-uart";
    first.interface = "00";
    Device replugged = first;
    replugged.path = "/dev/ttyUSB8";
    Device other = first;
    other.path = "/dev/ttyUSB8";
    other.topology = "1-2.4|ch341-uart";
    CHECK(first.key() == replugged.key());
    CHECK(first.key() != other.key());
}
TEST_CASE("usb_resolution_rejects_another_device_reusing_the_old_tty_path") {
    Device selected;
    selected.path = "/dev/ttyACM0";
    selected.vid = 0x0483;
    selected.pid = 0x3748;
    selected.serial = "board-A";
    selected.interface = "00";
    selected.topology = "1-2";
    Device reused = selected;
    reused.serial = "board-B";
    reused.topology = "1-3";
    Device moved = selected;
    moved.path = "/dev/ttyACM4";
    moved.topology = "1-7";
    CHECK_FALSE(resolve_device(selected, {reused}).has_value());
    const auto found = resolve_device(selected, {moved});
    REQUIRE(found.has_value());
    CHECK(found->path == "/dev/ttyACM4");
    Device first = selected;
    first.path = "/dev/ttyACM1";
    first.topology = "1-3";
    Device second = selected;
    second.path = "/dev/ttyACM2";
    second.topology = "1-4";
    CHECK_FALSE(resolve_device(selected, {first, second}).has_value());
}
TEST_CASE("settings_defaults_are_8n1_without_flow_control") {
    const Settings settings;
    CHECK(settings.baud == 115200);
    CHECK(settings.bits == 8);
    CHECK(settings.parity == "none");
    CHECK(settings.stop == 1);
    CHECK(settings.flow == "none");
    CHECK_FALSE(settings.dtr);
    CHECK_FALSE(settings.rts);
}

// ---------------------------------------------------------------------------------------
// flash.rs
// ---------------------------------------------------------------------------------------
namespace {
std::optional<FlashEvent> next_event(Flash& flash, milliseconds timeout = seconds(3)) {
    if (!flash.rx) return std::nullopt;
    return flash.rx->recv_timeout(timeout);
}
}  // namespace
TEST_CASE("flash_captures_both_streams_and_completion") {
    auto started = Flash::start("printf 'one\\n'; printf 'two\\n' >&2", ".");
    REQUIRE(started.has_value());
    std::unique_ptr<Flash> flash = std::move(*started);
    std::vector<std::string> lines;
    std::string done;
    while (done.empty()) {
        auto event = next_event(*flash);
        REQUIRE(event.has_value());
        if (event->kind == FlashEvent::Kind::Line) {
            lines.push_back(event->text);
        } else {
            done = event->text;
        }
    }
    CHECK(done.find("状态码 0") != std::string::npos);
    CHECK(std::find(lines.begin(), lines.end(), "one") != lines.end());
    CHECK(std::find(lines.begin(), lines.end(), "two") != lines.end());
}
TEST_CASE("flash_rejects_empty_command_and_uses_current_directory_by_default") {
    CHECK_FALSE(Flash::start("  ", ".").has_value());
    auto started = Flash::start("true", " ");
    REQUIRE(started.has_value());
    (*started)->cancel();
}
TEST_CASE("flash_cancel_terminates_a_long_running_command") {
    auto started = Flash::start("sleep 30", ".");
    REQUIRE(started.has_value());
    const auto before = Clock::now();
    (*started)->cancel();
    CHECK(Clock::now() - before < seconds(2));
    CHECK_FALSE((*started)->running());
}
TEST_CASE("flash_output_line_is_bounded_and_marked_when_truncated") {
    auto channel = std::make_shared<Channel<FlashEvent>>(4);
    std::atomic<size_t> dropped{0};
    Bytes bytes(kFlashMaxLine, 'x');
    emit_flash_line(*channel, dropped, bytes, true);
    const auto event = channel->try_recv();
    REQUIRE(event.has_value());
    CHECK(event->kind == FlashEvent::Kind::Line);
    CHECK(event->text.size() <= kFlashMaxLine + std::strlen(kFlashTruncation));
    CHECK(event->text.ends_with(kFlashTruncation));
    for (int i = 0; i < 10; ++i) emit_flash_line(*channel, dropped, bytes, false);
    CHECK(dropped.load() >= 5);
}

// ---------------------------------------------------------------------------------------
// app.rs
// ---------------------------------------------------------------------------------------
TEST_CASE("payload_endings_and_binary") {
    const std::pair<const char*, Bytes> cases[]{{"CR", {0x0D}}, {"LF", {0x0A}}, {"CRLF", {0x0D, 0x0A}}, {"无", {}}};
    for (const auto& [ending, suffix] : cases) {
        Bytes expected{'a'};
        expected.insert(expected.end(), suffix.begin(), suffix.end());
        CHECK(*payload("a", false, Encoding::Utf8, ending) == expected);
    }
    CHECK(*payload("00 ff", true, Encoding::Gbk, "CRLF") == Bytes{0x00, 0xFF});
    CHECK(*payload("中文", false, Encoding::Gbk, "无") == Bytes{0xD6, 0xD0, 0xCE, 0xC4});
}
TEST_CASE("capture_pause_anchor_survives_new_data_and_reports_eviction") {
    Capture capture(100);
    for (int n = 0; n < 150; ++n) {
        Record record = record_of(std::to_string(n), Bytes{1});
        record.elapsed = n;
        capture.push(std::move(record));
    }
    CHECK(capture.evicted == 50);
    REQUIRE(capture.records.size() == 100);
    CHECK(capture.records.front().id == 50);
    CHECK(capture.records.back().id == 149);
}
TEST_CASE("capture_memory_is_capped_regardless_of_the_line_limit") {
    Capture capture(1000000);
    for (size_t i = 0; i < 33; ++i) capture.push(record_of("", Bytes(1024 * 1024, 'x')));
    CHECK(capture.size_bytes() <= kMaxCaptureBytes);
    CHECK(capture.records.size() <= 32);
    CHECK(capture.evicted >= 1);
}
TEST_CASE("invalid_settings_are_atomic") {
    Settings settings;
    CHECK(validate_settings(settings).has_value());
    settings.bits = 9;
    CHECK_FALSE(validate_settings(settings).has_value());
    CHECK(validate_settings(settings).error() == "参数无效：bits=5..8 parity=none/odd/even stop=1/2 flow=none/hardware/software");
    settings = Settings{};
    settings.baud = 0;
    CHECK_FALSE(validate_settings(settings).has_value());
    settings = Settings{};
    settings.parity = "mark";
    CHECK_FALSE(validate_settings(settings).has_value());
}

// ---------------------------------------------------------------------------------------
// app_flow.rs
// ---------------------------------------------------------------------------------------
namespace {
std::unique_ptr<App> app_at(const std::filesystem::path& root) { return std::make_unique<App>(Store::at(root / "config", root / "data")); }
}  // namespace
TEST_CASE("app_startup_discovers_without_connecting_and_receive_survives_pause") {
    TempDir dir;
    auto app = app_at(dir.path);
    CHECK_FALSE(app->connected);
    CHECK_FALSE(app->device.has_value());
    CHECK_FALSE(app->disconnected.has_value());
    const std::string first = "sensor=1.25,x=2.5\r\n";
    const std::string second = "sensor=3.5,x=4.5\n";
    app->receive(bytes_of(first));
    REQUIRE(app->capture.records.size() == 1);
    app->pause();
    const auto anchor = app->anchor;
    app->receive(bytes_of(second));
    CHECK(app->anchor == anchor);
    CHECK(app->capture.records.size() == 2);
    CHECK(app->rx_total == first.size() + second.size());
    CHECK(app->capture.records.back().text == "sensor=3.5,x=4.5");
}
TEST_CASE("search_and_filter_submission_follow_captured_records") {
    TempDir dir;
    auto app = app_at(dir.path);
    app->receive(bytes_of("boot=1\nWARN sensor=2\nready=1\n"));
    REQUIRE(app->submit(InputKind::Search, "WARN").has_value());
    CHECK(app->found == app->capture.records.at(1).id);
    CHECK(app->anchor == app->found);
    REQUIRE(app->submit(InputKind::Filter, "sensor").has_value());
    CHECK(app->filter == "sensor");
    CHECK(app->scroll == 0);
    app->search_next();
    CHECK(app->found == std::optional<uint64_t>(1));
}
TEST_CASE("logging_keeps_raw_bytes_timestamps_csv_quoting_and_private_permissions") {
    TempDir dir;
    auto app = app_at(dir.path);
    app->csv = true;
    app->logging();
    REQUIRE(app->logger.has_value());
    const auto stem = app->logger->path;
    const std::string input = "sen\"sor=1.25,x=2.5\r\nsen\"sor=3,x=4\n";
    app->pause();
    app->receive(bytes_of(input));
    CHECK(app->capture.records.size() == 2);
    CHECK(app->rx_total == input.size());
    app->logging();
    CHECK_FALSE(app->logger.has_value());
    auto bin = stem;
    bin += ".bin";
    auto log = stem;
    log += ".log";
    auto csv = stem;
    csv += ".csv";
    CHECK(slurp(bin) == input);
    const std::string log_text = slurp(log);
    for (const std::string& line : split_lines(log_text)) {
        CHECK(line.find('T') != std::string::npos);
        CHECK(line.find("[RX]") != std::string::npos);
    }
    CHECK(log_text.find("sen\"sor=1.25") != std::string::npos);
    CHECK(mode_of(log) == 0600);
    const auto rows = split_lines(slurp(csv));
    REQUIRE(rows.size() == 5);
    CHECK(parse_csv_row(rows[0]) == std::vector<std::string>{"timestamp", "seconds", "channel", "value"});
    const auto first_row = parse_csv_row(rows[1]);
    REQUIRE(first_row.size() == 4);
    CHECK(first_row[2] == "sen\"sor");
    CHECK(first_row[3] == "1.25");
    const auto second_row = parse_csv_row(rows[2]);
    CHECK(second_row[2] == "x");
    CHECK(second_row[3] == "2.5");
}
TEST_CASE("invalid_settings_are_atomic_and_timer_requires_connection_and_last_send") {
    TempDir dir;
    auto app = app_at(dir.path);
    const uint32_t original_baud = app->profile.settings.baud;
    const uint8_t original_bits = app->profile.settings.bits;
    CHECK_FALSE(app->submit(InputKind::Settings, "baud=230400 bits=9").has_value());
    CHECK(app->profile.settings.baud == original_baud);
    CHECK(app->profile.settings.bits == original_bits);
    CHECK_FALSE(app->submit(InputKind::Timer, "100").has_value());
    CHECK_FALSE(app->repeat.has_value());
    app->connected = true;
    app->last_sent = Bytes{0x41, 0x0D, 0x0A};
    REQUIRE(app->submit(InputKind::Timer, "100").has_value());
    REQUIRE(app->repeat.has_value());
    CHECK(app->repeat->bytes == Bytes{0x41, 0x0D, 0x0A});
    CHECK(app->repeat->every == milliseconds(100));
    CHECK(app->submit(InputKind::Timer, "0").has_value());
    CHECK_FALSE(app->repeat.has_value());
    CHECK(app->submit(InputKind::Timer, "10").error() == "最短间隔 20 ms");
}
TEST_CASE("oversized_file_is_rejected_before_queueing_and_payload_modes_are_exact") {
    TempDir dir;
    auto app = app_at(dir.path);
    auto file = dir.path / "too-large.bin";
    {
        std::ofstream out(file, std::ios::binary);
        out << std::string(1024 * 1024 + 1, 'Z');
    }
    app->connected = true;
    CHECK_FALSE(app->submit(InputKind::File, file.string()).has_value());
    CHECK(app->capture.records.empty());
    CHECK(app->last_sent.empty());
    CHECK(app->tx_total == 0);
    CHECK(*payload("41 42", true, Encoding::Gbk, "CRLF") == Bytes{'A', 'B'});
}
TEST_CASE("hex_capture_preserves_line_delimiters_and_encoding_switch_keeps_eviction_valid") {
    TempDir dir;
    Store store = Store::at(dir.path / "config", dir.path / "data");
    store.config.scrollback = 100;
    App app(std::move(store));
    const Bytes bytes{'A', '\r', '\n', 'B', 0x00, 0xFF, '\n'};
    app.receive(bytes);
    Bytes wire;
    for (const Record& record : app.wire.records) wire.insert(wire.end(), record.raw.begin(), record.raw.end());
    CHECK(wire == bytes);
    app.profile.encoding = Encoding::Gbk;
    const Bytes line{0xD6, 0xD0, '\n'};
    for (int i = 0; i < 110; ++i) app.receive(line);
    app.toggle_encoding();
    for (int i = 0; i < 110; ++i) app.receive(line);
    app.toggle_encoding();
    for (int i = 0; i < 110; ++i) app.receive(line);
    CHECK(app.capture.records.size() == 100);
    CHECK(app.capture.evicted > 200);
}
TEST_CASE("suspending_keeps_capture_filter_selection_and_stops_background_work") {
    TempDir dir;
    auto app = app_at(dir.path);
    app->receive(bytes_of("retained sensor=3\n"));
    REQUIRE(app->submit(InputKind::Filter, "sensor").has_value());
    app->pause();
    const auto anchor = app->anchor;
    const size_t records = app->capture.records.size();
    app->suspend();
    CHECK_FALSE(app->connected);
    CHECK_FALSE(app->repeat.has_value());
    CHECK(app->filter == "sensor");
    CHECK(app->capture.records.size() == records);
    CHECK(app->anchor == anchor);
    app->resume();
    CHECK(app->filter == "sensor");
    CHECK(app->capture.records.size() == records);
    CHECK(app->anchor == anchor);
    app->suspend();
}

// ---------------------------------------------------------------------------------------
// flash_flow.rs
// ---------------------------------------------------------------------------------------
namespace {
struct FlashFixture {
    TempDir dir;
    std::unique_ptr<App> app;
    std::shared_ptr<CommandChannel> commands;
    std::shared_ptr<EventChannel> events;
    explicit FlashFixture(const std::string& command = "printf original > output.txt; printf 'flash output\\n'") {
        app = std::make_unique<App>(Store::at(dir.path / "config", dir.path / "data"));
        app->worker = Worker::from_channels(std::make_shared<CommandChannel>(64), std::make_shared<EventChannel>(512));
        commands = app->worker.tx;
        events = app->worker.rx;
        app->device = explicit_device("/dev/pts/simulation-only");
        app->connected = true;
        app->profile.flash = command;
        app->profile.flash_dir = dir.path.string();
    }
};
uint64_t release_command(CommandChannel& commands) {
    auto command = commands.try_recv();
    REQUIRE(command.has_value());
    REQUIRE(command->kind == Command::Kind::Release);
    return command->id;
}
void tick_until_done(App& app) {
    const auto until = Clock::now() + seconds(3);
    while (app.flashing() && Clock::now() < until) {
        app.tick();
        std::this_thread::sleep_for(milliseconds(5));
    }
}
}  // namespace
TEST_CASE("flash_waits_for_own_release_ack_and_executes_snapshotted_command") {
    FlashFixture fixture;
    App& app = *fixture.app;
    app.request_flash();
    const uint64_t id = release_command(*fixture.commands);
    app.profile.flash = "printf wrong > output.txt";
    fixture.events->try_send(Event::disconnected("old event"));
    app.tick();
    CHECK_FALSE(app.flashing());
    CHECK_FALSE(std::filesystem::exists(fixture.dir.path / "output.txt"));
    fixture.events->try_send(Event::released(id - 1));
    app.tick();
    CHECK_FALSE(app.flashing());
    fixture.events->try_send(Event::released(id));
    app.tick();
    CHECK(app.flashing());
    // Parameter changes may be saved during flashing but must not reopen the port.
    app.apply();
    auto queued = fixture.commands->try_recv();
    CHECK_FALSE(queued.has_value());
    tick_until_done(app);
    CHECK_FALSE(app.flashing());
    CHECK(slurp(fixture.dir.path / "output.txt") == "original");
    CHECK(std::any_of(app.flash_lines.begin(), app.flash_lines.end(), [](const std::string& line) { return line.find("flash output") != std::string::npos; }));
    auto reconnect = fixture.commands->try_recv();
    REQUIRE(reconnect.has_value());
    CHECK(reconnect->kind == Command::Kind::Connect);
}
TEST_CASE("cancel_waiting_flash_ignores_stale_ack_even_after_a_second_request") {
    FlashFixture fixture;
    App& app = *fixture.app;
    app.request_flash();
    const uint64_t old = release_command(*fixture.commands);
    app.cancel_flash();
    auto reconnect = fixture.commands->try_recv();
    REQUIRE(reconnect.has_value());
    CHECK(reconnect->kind == Command::Kind::Connect);
    fixture.events->try_send(Event::released(old));
    app.tick();
    CHECK_FALSE(app.flashing());
    CHECK_FALSE(std::filesystem::exists(fixture.dir.path / "output.txt"));
    app.request_flash();
    const uint64_t fresh = release_command(*fixture.commands);
    CHECK(old != fresh);
    fixture.events->try_send(Event::released(old));
    app.tick();
    CHECK_FALSE(app.flashing());
    app.cancel_flash();
    fixture.events->try_send(Event::released(fresh));
    app.tick();
    CHECK_FALSE(app.flashing());
    CHECK_FALSE(std::filesystem::exists(fixture.dir.path / "output.txt"));
}
TEST_CASE("switching_away_while_waiting_for_release_cancels_the_pending_flash") {
    FlashFixture fixture;
    App& app = *fixture.app;
    app.request_flash();
    release_command(*fixture.commands);
    CHECK(app.status.rfind("等待串口关闭确认", 0) == 0);
    app.suspend();
    CHECK(app.status.find("已取消烧录") != std::string::npos);
    CHECK_FALSE(app.flashing());
    app.resume();
    CHECK(app.status.find("已取消烧录") != std::string::npos);
    CHECK(app.command(Command::disconnect()));
    app.request_flash();
    CHECK(app.status.rfind("等待串口关闭确认", 0) == 0);
    app.suspend();
    CHECK(app.status.find("已取消烧录") != std::string::npos);
    CHECK_FALSE(std::filesystem::exists(fixture.dir.path / "output.txt"));
}

// ---------------------------------------------------------------------------------------
// tests/pty.rs
// ---------------------------------------------------------------------------------------
TEST_CASE("pty_utf8_gbk_and_hex_survive_chunked_streams") {
    Framer utf8;
    const Bytes line = bytes_of("串口温度=23.5");
    CHECK(utf8.push(std::span<const uint8_t>(line.data(), 3)).empty());
    CHECK(utf8.push(std::span<const uint8_t>(line.data() + 3, line.size() - 3)).empty());
    CHECK(utf8.push(Bytes{'\r', '\n'}).size() == 1);
    CHECK(utf8.push(bytes_of("next\r")).size() == 1);
    CHECK(utf8.push(Bytes{'\n'}).empty());
    const auto gbk = encode_text(Encoding::Gbk, "温度=23.5");
    REQUIRE(gbk.has_value());
    Framer framer;
    for (const uint8_t byte : *gbk) {
        const Bytes one{byte};
        CHECK(framer.push(one).empty());
    }
    const auto frames = framer.push(Bytes{'\r'});
    REQUIRE(frames.size() == 1);
    CHECK(decode_bytes(Encoding::Gbk, frames[0]) == "温度=23.5");
    CHECK(*parse_hex("0xDE AD, 00 ff") == Bytes{0xDE, 0xAD, 0x00, 0xFF});
}
TEST_CASE("pty_worker_round_trips_raw_hex_and_reports_unsupported_control_lines") {
    TempDir dir;
    Pty pty = open_pty();
    const auto alias = dir.path / "board-uart";
    link_pty(alias, pty.slave);
    Worker worker = Worker::start();
    REQUIRE(worker.tx->try_send(Command::connect(pty_device(alias), Settings{})) == CommandChannel::Result::Ok);
    REQUIRE(await_connected(worker, alias.string()));
    const Bytes raw{0xDE, 0xAD, 0x00, 0xFF};
    REQUIRE(::write(pty.master, raw.data(), raw.size()) == static_cast<ssize_t>(raw.size()));
    CHECK(await_rx(worker, raw.size()) == raw);
    REQUIRE(worker.tx->try_send(Command::write(raw)) == CommandChannel::Result::Ok);
    CHECK(read_master(pty.master, raw.size(), seconds(2)) == raw);
    worker.tx->try_send(Command::lines(true, true));
    const auto modem_error = [](const Event& event) {
        return event.kind == Event::Kind::Error && (event.text.find("DTR") != std::string::npos || event.text.find("RTS") != std::string::npos);
    };
    CHECK(await_event(worker, seconds(2), modem_error).has_value());
    worker.tx->try_send(Command::pulse(true, 30));
    // The pulse and its restore deadline both report that a PTY has no modem lines.
    CHECK(await_event(worker, seconds(2), modem_error).has_value());
    CHECK(await_event(worker, seconds(2), modem_error).has_value());
    worker.tx->try_send(Command::write(Bytes{0xA5}));
    CHECK(read_master(pty.master, 1, seconds(2)) == Bytes{0xA5});
    worker.tx->try_send(Command::disconnect());
    CHECK(await_event(worker, seconds(2), [&](const Event& event) { return event.kind == Event::Kind::Disconnected && event.text == alias.string(); }).has_value());
    const int reopened = ::open(alias.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    REQUIRE(reopened >= 0);
    ::close(reopened);
    REQUIRE(worker.tx->try_send(Command::connect(pty_device(alias), Settings{})) == CommandChannel::Result::Ok);
    REQUIRE(await_connected(worker, alias.string()));
    worker.tx->try_send(Command::release(41));
    CHECK(await_event(worker, seconds(2), [](const Event& event) { return event.kind == Event::Kind::Released && event.id == 41; }).has_value());
    ::close(pty.master);
}
TEST_CASE("pty_worker_reconnects_repointed_test_symlink_and_release_stays_responsive") {
    TempDir dir;
    const auto alias = dir.path / "uart-current";
    Pty first = open_pty();
    link_pty(alias, first.slave);
    Worker worker = Worker::start();
    REQUIRE(worker.tx->try_send(Command::connect(pty_device(alias), Settings{})) == CommandChannel::Result::Ok);
    REQUIRE(await_connected(worker, alias.string()));
    ::close(first.master);
    first.master = -1;
    // Hide the alias while the device is gone so a reconnect cannot race the repoint.
    std::filesystem::remove(alias);
    CHECK(await_event(worker, seconds(3), [&](const Event& event) { return event.kind == Event::Kind::Disconnected && event.text == alias.string(); }).has_value());
    Pty second = open_pty();
    link_pty(alias, second.slave);
    REQUIRE(await_connected(worker, alias.string()));
    const Bytes hello = bytes_of("reconnected\n");
    REQUIRE(::write(second.master, hello.data(), hello.size()) == static_cast<ssize_t>(hello.size()));
    CHECK(await_rx(worker, hello.size()) == hello);
    // Do not read the PTY master: its output buffer fills. Release must still close the fd,
    // discard the unsent tail, and acknowledge promptly.
    worker.tx->try_send(Command::write(Bytes(1024 * 1024, 0x5A)));
    const auto deadline = Clock::now() + seconds(3);
    size_t written = 0;
    while (Clock::now() < deadline && written < 8192) {
        if (auto event = worker.rx->recv_timeout(milliseconds(100)); event && event->kind == Event::Kind::Tx) written += event->count;
    }
    REQUIRE(written >= 8192);
    const auto started = Clock::now();
    worker.tx->try_send(Command::release(99));
    CHECK(await_event(worker, milliseconds(900), [](const Event& event) { return event.kind == Event::Kind::Released && event.id == 99; }).has_value());
    CHECK(Clock::now() - started < seconds(1));
    const int reopened = ::open(alias.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    REQUIRE(reopened >= 0);
    ::close(reopened);
    ::close(second.master);
}

// ---------------------------------------------------------------------------------------
// tui.rs: page key handling and narrow drawing
// ---------------------------------------------------------------------------------------
TEST_CASE("local_filter_is_live_cancelable_and_has_empty_state") {
    PageFixture fixture;
    SerialPage& page = fixture.page;
    App& app = *page.app();
    app.receive(bytes_of("Apple 香港\n北京\n"));
    app.filter = "apple";
    page.handle(ch(U'/'));
    page.handle(ch(U'u', true));
    for (const char32_t letter : std::u32string(U"xianggang")) page.handle(ch(letter));
    CHECK(app.filter == "xianggang");
    CHECK(render(page, 110, 24).find("1/2 行") != std::string::npos);
    page.handle(key(KeyCode::Escape));
    CHECK(app.filter == "apple");
    page.handle(ch(U'/'));
    page.handle(ch(U'u', true));
    page.handle(paste("不存在\nqq"));
    CHECK(app.filter == "不存在 qq");
    CHECK_FALSE(app.connected);
    CHECK(std::all_of(app.capture.records.begin(), app.capture.records.end(), [](const Record& record) { return record.kind == "RX"; }));
    page.handle(key(KeyCode::Enter));
    const std::string text = render(page, 110, 24);
    CHECK(text.find("没有匹配 · Esc 清除过滤") != std::string::npos);
    CHECK(text.find("0/2 行") != std::string::npos);
    page.handle(key(KeyCode::Escape));
    CHECK(app.filter.empty());
    page.handle(paste("q\n"));
    CHECK(app.filter.empty());
    const std::pair<int, int> sizes[]{{1, 1}, {10, 3}, {40, 10}};
    for (const auto& [width, height] : sizes) render(page, width, height);
}
TEST_CASE("n_and_uppercase_n_cycle_both_ways_and_keep_record_id") {
    PageFixture fixture;
    SerialPage& page = fixture.page;
    App& app = *page.app();
    app.receive(bytes_of("Apple 香港\n其他\nAPPLE 香港\n"));
    page.handle(ch(U'f', true));
    page.handle(paste("apple xg"));
    page.handle(ch(U'x', true));
    CHECK(app.search == "apple xg");
    page.handle(key(KeyCode::Enter));
    CHECK(app.found == std::optional<uint64_t>(0));
    page.handle(ch(U'n'));
    CHECK(app.found == std::optional<uint64_t>(2));
    CHECK(app.status.find("第 2/共 2 个") != std::string::npos);
    page.handle(ch(U'N'));
    CHECK(app.found == std::optional<uint64_t>(0));
    page.handle(ch(U'N'));
    CHECK(app.found == std::optional<uint64_t>(2));
    app.receive(bytes_of("Apple 香港\n"));
    CHECK(app.found == std::optional<uint64_t>(2));
    CHECK(render(page, 150, 24).find("第 2/共 3 个") != std::string::npos);
    // The matched Chinese term is drawn in the shared highlight colour.
    ftxui::Screen screen(150, 24);
    page.draw(screen, tui::Rect{0, 0, 150, 24});
    const ftxui::Color yellow = ftxui::Color::RGB((tui::kYellow >> 16) & 255, (tui::kYellow >> 8) & 255, tui::kYellow & 255);
    bool highlighted = false;
    for (int y = 0; y < screen.dimy() && !highlighted; ++y) {
        for (int x = 0; x < screen.dimx(); ++x) {
            const ftxui::Pixel& pixel = screen.PixelAt(x, y);
            if (pixel.character == "香" && pixel.foreground_color == yellow) highlighted = true;
        }
    }
    CHECK(highlighted);
}
TEST_CASE("preview_matches_case_insensitively_and_device_refresh_keeps_identity") {
    PageFixture fixture;
    SerialPage& page = fixture.page;
    App& app = *page.app();
    app.receive(bytes_of("Apple preview"));
    app.filter = "apple";
    CHECK(render(page, 110, 24).find("Apple preview") != std::string::npos);
    const auto device = [](const char* path, const char* serial) {
        Device item;
        item.path = path;
        item.vid = 1;
        item.pid = 2;
        item.serial = serial;
        item.product = "测试串口";
        item.interface = "0";
        return item;
    };
    app.devices = {device("/dev/ttyUSB0", "first"), device("/dev/ttyUSB1", "second")};
    app.selected = 1;
    app.replace_devices({device("/dev/ttyUSB2", "second"), device("/dev/ttyUSB0", "first")});
    CHECK(app.selected == 0);
    CHECK(app.devices[app.selected].path == "/dev/ttyUSB2");
    app.page = 1;
    page.handle(key(KeyCode::PageDown));
    CHECK(app.selected == 1);
    page.handle(key(KeyCode::PageUp));
    CHECK(app.selected == 0);
    page.handle(ch(U'/'));
    page.handle(key(KeyCode::Down));
    CHECK(app.selected == 1);
    CHECK(app.input.has_value());
}
TEST_CASE("page_switches_tabs_clicks_rows_and_toggles_capture_modes") {
    PageFixture fixture;
    SerialPage& page = fixture.page;
    App& app = *page.app();
    render(page, 110, 24);
    // The tab row is y=1; the second tab's number starts at x=9 and its label at x=11.
    page.handle(mouse(InputEvent::Type::MouseClick, 11, 1));
    CHECK(app.page == 1);
    page.handle(ch(U'1'));
    CHECK(app.page == 0);
    page.handle(ch(U'v'));
    CHECK(app.mode == 1);
    page.handle(ch(U'v'));
    CHECK(app.mode == 2);
    page.handle(ch(U'v'));
    CHECK(app.mode == 0);
    page.handle(ch(U'T'));
    CHECK(app.timestamp == 1);
    page.handle(ch(U'w'));
    CHECK(app.graph);
    page.handle(ch(U'x'));
    CHECK(app.tx_hex);
    page.handle(ch(U'e'));
    CHECK(app.profile.ending == "LF");
}
TEST_CASE("help_dialog_and_flash_confirmation_block_destructive_input") {
    PageFixture fixture;
    SerialPage& page = fixture.page;
    App& app = *page.app();
    page.handle(ch(U'?'));
    CHECK(app.help);
    CHECK(render(page, 110, 24).find("帮助") != std::string::npos);
    page.handle(key(KeyCode::Escape));
    CHECK_FALSE(app.help);
    // Without a device the Rust hint is shown and no confirmation appears.
    page.handle(ch(U'X'));
    CHECK_FALSE(page.confirm_flash());
    CHECK(app.status.find("先选择监视设备") != std::string::npos);
    app.device = explicit_device("/dev/pts/simulation-only");
    // Without a configured command the page points at the flash page instead.
    page.handle(ch(U'X'));
    CHECK_FALSE(page.confirm_flash());
    CHECK(app.page == 4);
    CHECK(app.status.find("先在 5 烧录 页设置命令") != std::string::npos);
    app.profile.flash = "true";
    page.handle(ch(U'X'));
    CHECK(page.confirm_flash());
    CHECK_FALSE(app.flash_waiting());
    page.handle(key(KeyCode::Escape));
    CHECK_FALSE(page.confirm_flash());
    CHECK_FALSE(app.flash_waiting());
}

// ---------------------------------------------------------------------------------------
// CLI contract (lib.rs command()/validate_args)
// ---------------------------------------------------------------------------------------
namespace {
struct CliResult {
    int code = 0;
    std::string out;
    std::string err;
};
CliResult run_cli_args(const std::vector<std::string>& args) {
    std::vector<std::string> owned{"serial"};
    for (const std::string& arg : args) owned.push_back(arg);
    std::vector<char*> argv;
    for (std::string& arg : owned) argv.push_back(arg.data());
    std::ostringstream out;
    std::ostringstream err;
    auto* old_out = std::cout.rdbuf(out.rdbuf());
    auto* old_err = std::cerr.rdbuf(err.rdbuf());
    const int code = serial_cli(static_cast<int>(argv.size()), argv.data());
    std::cout.rdbuf(old_out);
    std::cerr.rdbuf(old_err);
    return CliResult{code, out.str(), err.str()};
}
}  // namespace
TEST_CASE("cli_help_list_and_argument_errors_match_the_rust_tool") {
    const CliResult help = run_cli_args({"--help"});
    CHECK(help.code == 0);
    CHECK(help.out == "mayon-tools serial [<端口> [-b 波特率]]\nmayon-tools serial list\n配置和日志仍在 serial-mayon 的原目录。\n");
    CHECK(run_cli_args({"-h"}).code == 0);
    const CliResult listing = run_cli_args({"list"});
    CHECK(listing.code == 0);
    CHECK(listing.out.rfind("端口\tVID:PID\t产品\t序列号\t接口\n", 0) == 0);
    const CliResult extra = run_cli_args({"list", "--json"});
    CHECK(extra.code == 1);
    CHECK(extra.err == "Error: list 不接受额外参数\n");
    const CliResult missing = run_cli_args({"-b"});
    CHECK(missing.code == 1);
    CHECK(missing.err == "Error: -b 缺少波特率\n");
    CHECK(run_cli_args({"-b", "0"}).err == "Error: 波特率范围 1–12000000\n");
    CHECK(run_cli_args({"-b", "12000001"}).err == "Error: 波特率范围 1–12000000\n");
    CHECK(run_cli_args({"-b", "115200"}).code == -1);
    CHECK(run_cli_args({"-b", "abc"}).err == "Error: invalid digit found in string\n");
    CHECK(run_cli_args({"-b", ""}).err == "Error: cannot parse integer from empty string\n");
    CHECK(run_cli_args({"-b", "+"}).err == "Error: invalid digit found in string\n");
    CHECK(run_cli_args({"-b", "4294967296"}).err == "Error: number too large to fit in target type\n");
    CHECK(run_cli_args({"--baud", "9600", "/dev/ttyUSB0"}).code == -1);
    CHECK(run_cli_args({}).code == -1);
    CHECK(run_cli_args({"/dev/ttyUSB0"}).code == -1);
    CHECK(run_cli_args({"one", "two"}).err == "Error: 无效串口参数\n");
    CHECK(run_cli_args({"--bogus"}).err == "Error: 无效串口参数\n");
}
TEST_CASE("cli_device_row_uses_tabs_and_the_rust_column_order") {
    Device device;
    device.path = "/dev/ttyUSB0";
    device.vid = 0x1A86;
    device.pid = 0x7523;
    device.product = "CH340";
    device.interface = "00";
    CHECK(format_device_row(device) == "/dev/ttyUSB0\t1a86:7523\tCH340\t无\t00");
    device.serial = "A1B2";
    CHECK(format_device_row(device) == "/dev/ttyUSB0\t1a86:7523\tCH340\tA1B2\t00");
}

// ---------------------------------------------------------------------------------------
// Page wiring: private data directories, CLI-created page and the error state.
// ---------------------------------------------------------------------------------------
TEST_CASE("page_uses_private_xdg_directories_and_creates_the_rust_layout") {
    TempDir dir;
    PrivateHome home(dir.path);
    auto page = make_serial_page();
    auto* serial_page = dynamic_cast<SerialPage*>(page.get());
    REQUIRE(serial_page != nullptr);
    REQUIRE(serial_page->app() != nullptr);
    CHECK(serial_page->app()->store.config_path == dir.path / "config" / "serial-mayon" / "config.json");
    CHECK(serial_page->app()->store.data == dir.path / "data" / "serial-mayon");
    CHECK(mode_of(dir.path / "config" / "serial-mayon") == 0700);
    CHECK(mode_of(dir.path / "data" / "serial-mayon" / "logs") == 0700);
    serial_page->app()->persist();
    CHECK(mode_of(serial_page->app()->store.config_path) == 0600);
    serial_page->app()->suspend();
}
TEST_CASE("page_shows_the_error_state_for_a_broken_config") {
    TempDir dir;
    PrivateHome home(dir.path);
    const auto config = dir.path / "config" / "serial-mayon";
    std::filesystem::create_directories(config);
    {
        std::ofstream file(config / "config.json");
        file << "invalid";
    }
    SerialPage page;
    REQUIRE_FALSE(page.error().empty());
    ftxui::Screen screen(80, 20);
    page.draw(screen, tui::Rect{0, 0, 80, 20});
    const std::string text = screen_text(screen);
    CHECK(text.find("串口") != std::string::npos);
    CHECK(text.find("invalid") != std::string::npos);
    CHECK_FALSE(page.handle(ch(U'R')));
    CHECK_FALSE(page.error().empty());
    CHECK(page.handle(ch(U'q')));
}
TEST_CASE("pty_simulator_fixture_is_available") {
    CHECK(std::filesystem::exists(std::filesystem::path(kFixtures) / "feed.py"));
}
