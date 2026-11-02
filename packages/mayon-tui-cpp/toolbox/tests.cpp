// Ports the Rust toolbox tests (tools/src/main.rs, tools/src/voice.rs) and covers the
// shell's lazy loading, tab geometry, error retry and the voice page against a private
// mock daemon socket. No real daemon, model or user data is touched: HOME, XDG_* and
// the control socket all live in a temporary directory.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include <ftxui/screen/screen.hpp>

#include "shell.hpp"
#include "ui/page.hpp"
#include "ui/text.hpp"
#include "voice.hpp"
#include "voice_internal.hpp"

namespace {
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;

const std::string kFixtures = FIXTURES;
constexpr auto kSteady = std::chrono::steady_clock::now;

std::string text_of(ftxui::Screen& screen) {
    std::string out;
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) out += screen.PixelAt(x, y).character;
        out += "\n";
    }
    return out;
}
std::string squash(std::string text) {
    text.erase(std::remove_if(text.begin(), text.end(), [](unsigned char ch) { return ch == ' ' || ch == '\n'; }), text.end());
    return text;
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
InputEvent mouse(InputEvent::Type type, int x, int y) {
    InputEvent event;
    event.type = type;
    event.x = x;
    event.y = y;
    return event;
}
InputEvent paste(const std::string& text) {
    InputEvent event;
    event.type = InputEvent::Type::Paste;
    event.paste = text;
    return event;
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
bool any_underlined(ftxui::Screen& screen) {
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) {
            if (screen.PixelAt(x, y).underlined && screen.PixelAt(x, y).character != " ") return true;
        }
    }
    return false;
}

// Private HOME/XDG for every test; the real configuration and runtime are never read.
class PrivateEnv {
public:
    PrivateEnv() {
        char pattern[] = "/tmp/toolbox-test-XXXXXX";
        char* created = ::mkdtemp(pattern);
        REQUIRE(created != nullptr);
        root_ = created;
        save("HOME", home_);
        save("XDG_CONFIG_HOME", config_);
        save("XDG_DATA_HOME", data_);
        save("XDG_RUNTIME_DIR", runtime_);
        ::setenv("HOME", root_.c_str(), 1);
        ::setenv("XDG_CONFIG_HOME", (root_ + "/config").c_str(), 1);
        ::setenv("XDG_DATA_HOME", (root_ + "/data").c_str(), 1);
        ::setenv("XDG_RUNTIME_DIR", root_.c_str(), 1);
        std::filesystem::create_directories(root_ + "/config/mayon-voice");
        std::filesystem::create_directories(root_ + "/data");
        ::chmod(root_.c_str(), 0700);
    }
    ~PrivateEnv() {
        restore("HOME", home_);
        restore("XDG_CONFIG_HOME", config_);
        restore("XDG_DATA_HOME", data_);
        restore("XDG_RUNTIME_DIR", runtime_);
        std::error_code ignored;
        std::filesystem::remove_all(root_, ignored);
    }
    PrivateEnv(const PrivateEnv&) = delete;
    PrivateEnv& operator=(const PrivateEnv&) = delete;
    const std::string& root() const { return root_; }
    void write_config(const std::string& body) const {
        std::ofstream file(root_ + "/config/mayon-voice/config.toml", std::ios::binary);
        REQUIRE(file.good());
        file << body;
    }

private:
    struct Saved {
        bool had = false;
        std::string value;
    };
    static void save(const char* name, Saved& slot) {
        if (const char* value = std::getenv(name)) {
            slot.had = true;
            slot.value = value;
        }
    }
    static void restore(const char* name, const Saved& slot) {
        if (slot.had) ::setenv(name, slot.value.c_str(), 1);
        else ::unsetenv(name);
    }
    std::string root_;
    Saved home_, config_, data_, runtime_;
};

// Replies to one newline-terminated command per connection, like mayon-voice's daemon.
class MockDaemon {
public:
    using Handler = std::function<std::string(const std::string&)>;
    explicit MockDaemon(Handler handler) : handler_(std::move(handler)) {
        const char* runtime = std::getenv("XDG_RUNTIME_DIR");
        REQUIRE(runtime != nullptr);
        dir_ = std::string(runtime) + "/mayon-voice";
        std::filesystem::create_directories(dir_);
        ::chmod(dir_.c_str(), 0700);
        path_ = dir_ + "/control.sock";
        ::unlink(path_.c_str());
        fd_ = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        REQUIRE(fd_ >= 0);
        sockaddr_un address {};
        address.sun_family = AF_UNIX;
        std::memcpy(address.sun_path, path_.c_str(), path_.size() + 1);
        REQUIRE(::bind(fd_, reinterpret_cast<sockaddr*>(&address), sizeof address) == 0);
        REQUIRE(::listen(fd_, 8) == 0);
        thread_ = std::thread([this] { serve(); });
    }
    ~MockDaemon() { stop(); }
    MockDaemon(const MockDaemon&) = delete;
    MockDaemon& operator=(const MockDaemon&) = delete;
    int requests() const { return requests_.load(); }
    bool saw(const std::string& command) const {
        const std::lock_guard lock(mutex_);
        return seen_.count(command) > 0;
    }
    void stop() {
        if (stopping_.exchange(true)) return;
        if (thread_.joinable()) thread_.join();
        if (fd_ >= 0) ::close(fd_);
        ::unlink(path_.c_str());
    }

private:
    void serve() {
        while (!stopping_) {
            pollfd waiting{fd_, POLLIN, 0};
            const int ready = ::poll(&waiting, 1, 10);
            if (ready <= 0) continue;
            const int client = ::accept(fd_, nullptr, nullptr);
            if (client < 0) continue;
            std::string command;
            char buffer[256];
            while (command.find('\n') == std::string::npos) {
                const ssize_t got = ::read(client, buffer, sizeof buffer);
                if (got <= 0) break;
                command.append(buffer, static_cast<size_t>(got));
            }
            if (const auto newline = command.find('\n'); newline != std::string::npos) command.resize(newline);
            {
                const std::lock_guard lock(mutex_);
                seen_.insert(command);
                ++requests_;
            }
            const std::string reply = handler_(command) + "\n";
            ::send(client, reply.data(), reply.size(), MSG_NOSIGNAL);
            ::close(client);
        }
    }

    Handler handler_;
    std::thread thread_;
    std::string dir_;
    std::string path_;
    int fd_ = -1;
    std::atomic<bool> stopping_{false};
    std::atomic<int> requests_{0};
    mutable std::mutex mutex_;
    std::set<std::string> seen_;
};

struct FakePage : tui::Page {
    int draws = 0;
    int ticks = 0;
    bool active = true;
    bool quit = false;
    tui::Rect last_area;
    std::vector<InputEvent> events;
    std::optional<tui::TimePoint> deadline;
    std::optional<std::pair<int, int>> cursor_value;
    bool edit = false;

    void set_active(bool value) override { active = value; }
    void draw(ftxui::Screen&, tui::Rect area) override {
        ++draws;
        last_area = area;
    }
    bool handle(const InputEvent& event) override {
        events.push_back(event);
        return quit;
    }
    std::optional<tui::TimePoint> next_deadline() const override { return deadline; }
    void tick() override { ++ticks; }
    std::optional<std::pair<int, int>> cursor() const override { return cursor_value; }
    bool editing() const override { return edit || cursor_value.has_value(); }
};

// The shell owns its pages, so the fixture keeps the shared counters behind a forwarder.
struct ForwardPage : tui::Page {
    explicit ForwardPage(std::shared_ptr<FakePage> page) : inner(std::move(page)) {}
    void attach(tui::Post post) override { inner->attach(std::move(post)); }
    void set_active(bool value) override { inner->set_active(value); }
    void draw(ftxui::Screen& screen, tui::Rect area) override { inner->draw(screen, area); }
    bool handle(const InputEvent& event) override { return inner->handle(event); }
    std::optional<tui::TimePoint> next_deadline() const override { return inner->next_deadline(); }
    void tick() override { inner->tick(); }
    std::optional<std::pair<int, int>> cursor() const override { return inner->cursor(); }
    bool editing() const override { return inner->editing(); }
    std::shared_ptr<FakePage> inner;
};

struct ShellFixture {
    std::array<std::shared_ptr<FakePage>, 5> pages;
    std::array<int, 5> created{};
    std::string failure;
    std::array<toolbox::Factory, 5> factories() {
        std::array<toolbox::Factory, 5> out;
        for (size_t index = 0; index < out.size(); ++index) {
            out[index] = [this, index](const std::vector<std::string>&) -> std::unique_ptr<tui::Page> {
                ++created[index];
                if (!failure.empty()) {
                    const std::string message = failure;
                    failure.clear();
                    throw std::runtime_error(message);
                }
                if (!pages[index]) pages[index] = std::make_shared<FakePage>();
                return std::make_unique<ForwardPage>(pages[index]);
            };
        }
        return out;
    }
};

struct FakeClock {
    tui::TimePoint now = kSteady();
    voice::Clock clock() {
        return [this] { return now; };
    }
    void advance(std::chrono::milliseconds by) { now += by; }
};

// Runs tick until `done` or the timeout; the page has no mailbox in tests.
bool wait_for(voice::VoicePage& page, const std::function<bool()>& done, int milliseconds = 4000) {
    const auto until = kSteady() + std::chrono::milliseconds(milliseconds);
    while (kSteady() < until) {
        page.tick();
        if (done()) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    page.tick();
    return done();
}
}  // namespace

TEST_CASE("brackets switch pages unless the current page is editing") {
    const auto top = [](InputEvent event, size_t current, bool editing) { return toolbox::top_switch(event, current, editing); };
    CHECK(top(ch(U']'), 1, false) == std::optional<size_t>(2));
    CHECK(top(ch(U'['), 0, false) == std::optional<size_t>(4));
    CHECK(top(ch(U'['), 1, false) == std::optional<size_t>(0));
    CHECK(top(ch(U']'), 4, false) == std::optional<size_t>(0));
    CHECK_FALSE(top(ch(U'1'), 1, false).has_value());
    CHECK_FALSE(top(ch(U']'), 1, true).has_value());
    CHECK_FALSE(top(ch(U'['), 1, true).has_value());
    CHECK_FALSE(top(ch(U']', true), 1, false).has_value());
    CHECK_FALSE(top(ch(U']', false, true), 1, false).has_value());
    CHECK_FALSE(top(key(KeyCode::Right), 1, false).has_value());
}

TEST_CASE("tab hit testing follows the rendered 9-cell title and padded labels") {
    CHECK_FALSE(toolbox::tab_at(8).has_value());
    CHECK(toolbox::tab_at(9) == std::optional<size_t>(0));
    CHECK(toolbox::tab_at(17) == std::optional<size_t>(0));
    CHECK(toolbox::tab_at(18) == std::optional<size_t>(1));
    CHECK(toolbox::tab_at(25) == std::optional<size_t>(1));
    CHECK(toolbox::tab_at(26) == std::optional<size_t>(2));
    CHECK(toolbox::tab_at(34) == std::optional<size_t>(2));
    CHECK(toolbox::tab_at(35) == std::optional<size_t>(3));
    CHECK(toolbox::tab_at(41) == std::optional<size_t>(3));
    CHECK(toolbox::tab_at(42) == std::optional<size_t>(4));
    CHECK(toolbox::tab_at(49) == std::optional<size_t>(4));
    CHECK_FALSE(toolbox::tab_at(50).has_value());
    CHECK_FALSE(toolbox::tab_at(0).has_value());
    // The same geometry the bar draws: 9 + 9 + 8 + 9 + 7 + 8 cells before the hint text.
    ftxui::Screen screen(90, 3);
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    shell.draw(screen, tui::Rect{0, 0, 90, 3});
    std::vector<std::string> cells;
    for (int x = 0; x < 90; ++x) cells.push_back(screen.PixelAt(x, 0).character);
    CHECK(cells[0] == " ");
    CHECK(cells[1] == "工");
    CHECK(cells[7] == " ");
    CHECK(cells[9] == " ");
    CHECK(cells[10] == "D");
    CHECK(cells[16] == " ");
    CHECK(cells[18] == " ");
    CHECK(cells[19] == "P");
    CHECK(cells[26] == " ");
    CHECK(cells[27] == "S");
    CHECK(cells[35] == " ");
    CHECK(cells[36] == "K");
    CHECK(cells[42] == " ");
    CHECK(cells[43] == "V");
    CHECK(cells[50] == " ");
    CHECK(cells[51] == "[");
}

TEST_CASE("opening the initial page builds only that page") {
    ShellFixture fixture;
    std::vector<std::vector<std::string>> args(5);
    args[1] = {"--flag"};
    toolbox::Shell shell(fixture.factories(), 1, std::move(args));
    CHECK(fixture.created[1] == 1);
    for (const size_t page : {0, 2, 3, 4}) CHECK(fixture.created[page] == 0);
    CHECK(shell.opened(1));
    CHECK(shell.page() == 1);
    CHECK(fixture.pages[1]->active);
    shell.handle(ch(U']'));
    CHECK(shell.page() == 2);
    CHECK(fixture.created[2] == 1);
    CHECK_FALSE(fixture.pages[1]->active);
    CHECK(fixture.pages[2]->active);
    // Visiting every page and wrapping back keeps one instance per page.
    for (int step = 0; step < 3; ++step) shell.handle(ch(U']'));
    CHECK(shell.page() == 0);
    shell.handle(ch(U']'));
    CHECK(shell.page() == 1);
    CHECK(fixture.created[1] == 1);
    CHECK(fixture.pages[1]->active);
    shell.handle(ch(U'['));
    CHECK(shell.page() == 0);
    CHECK(fixture.created[0] == 1);
}

TEST_CASE("hidden pages stop ticking and drawing") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    shell.tick();
    CHECK(fixture.pages[1]->ticks == 1);
    shell.handle(ch(U']'));
    const int ports_ticks = fixture.pages[1]->ticks;
    const int ports_draws = fixture.pages[1]->draws;
    for (int step = 0; step < 3; ++step) {
        shell.tick();
        ftxui::Screen screen(80, 20);
        shell.draw(screen, tui::Rect{0, 0, 80, 20});
    }
    CHECK(fixture.pages[1]->ticks == ports_ticks);
    CHECK(fixture.pages[1]->draws == ports_draws);
    CHECK(fixture.pages[2]->ticks == 3);
    CHECK(fixture.pages[2]->draws == 3);
}

TEST_CASE("the bar sits above the page and the cursor is forwarded") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    ftxui::Screen screen(80, 20);
    shell.draw(screen, tui::Rect{0, 0, 80, 20});
    const std::string text = text_of(screen);
    CHECK(squash(text).find("工具箱") != std::string::npos);
    CHECK(squash(text).find("Docker") != std::string::npos);
    CHECK(squash(text).find("[/]切换") != std::string::npos);
    CHECK(fixture.pages[1]->last_area.x == 0);
    CHECK(fixture.pages[1]->last_area.y == 1);
    CHECK(fixture.pages[1]->last_area.width == 80);
    CHECK(fixture.pages[1]->last_area.height == 19);
    CHECK(any_underlined(screen));
    CHECK(any_cell_with_fg(screen, tui::kBlue));
    CHECK(any_cell_with_fg(screen, tui::kMuted));
    fixture.pages[1]->cursor_value = std::make_pair(7, 5);
    const std::optional<std::pair<int, int>> forwarded = shell.cursor();
    REQUIRE(forwarded.has_value());
    CHECK(forwarded->first == 7);
    CHECK(forwarded->second == 5);
}

TEST_CASE("a page that is editing keeps the brackets") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    fixture.pages[1]->cursor_value = std::make_pair(3, 3);
    shell.handle(ch(U']'));
    CHECK(shell.page() == 1);
    CHECK(fixture.created[2] == 0);
    CHECK(fixture.pages[1]->events.size() == 1);
}

TEST_CASE("a confirmation without a cursor still keeps the brackets") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    fixture.pages[1]->edit = true;
    shell.handle(ch(U']'));
    CHECK(shell.page() == 1);
    CHECK(fixture.created[2] == 0);
    CHECK(fixture.pages[1]->events.size() == 1);
}

TEST_CASE("clicks on the tab row switch and body clicks are translated") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    shell.handle(mouse(InputEvent::Type::MouseClick, 45, 0));
    CHECK(shell.page() == 4);
    CHECK(fixture.created[4] == 1);
    CHECK(fixture.pages[1]->events.empty());
    shell.handle(mouse(InputEvent::Type::MouseClick, 3, 6));
    REQUIRE(fixture.pages[4]->events.size() == 1);
    CHECK(fixture.pages[4]->events[0].y == 5);
    CHECK(fixture.pages[4]->events[0].x == 3);
    // A click on the title row that misses the labels is not forwarded.
    shell.handle(mouse(InputEvent::Type::MouseClick, 2, 0));
    CHECK(fixture.pages[4]->events.size() == 1);
    shell.handle(mouse(InputEvent::Type::WheelDown, 3, 6));
    CHECK(fixture.pages[4]->events.size() == 2);
    CHECK(fixture.pages[4]->events[1].y == 5);
}

TEST_CASE("a page that fails to start shows the error and retries with R") {
    ShellFixture fixture;
    std::vector<std::vector<std::string>> args(5);
    fixture.failure = "无法读取 /tmp/bindings.json";
    toolbox::Shell shell(fixture.factories(), 3, std::move(args));
    CHECK(shell.failed(3));
    CHECK(fixture.created[3] == 1);
    ftxui::Screen screen(80, 20);
    shell.draw(screen, tui::Rect{0, 0, 80, 20});
    const std::string text = squash(text_of(screen));
    CHECK(text.find("启动失败") != std::string::npos);
    CHECK(text.find("无法读取/tmp/bindings.json") != std::string::npos);
    CHECK(text.find("R重试") != std::string::npos);
    CHECK(text.find("q/Esc退出") != std::string::npos);
    CHECK_FALSE(shell.handle(ch(U'R')));
    CHECK_FALSE(shell.failed(3));
    CHECK(fixture.created[3] == 2);
    CHECK(shell.opened(3));
    CHECK_FALSE(shell.cursor().has_value());
    // The tab bar still works from the error page, like Rust's top_switch order.
    CHECK_FALSE(shell.handle(ch(U']')));
    CHECK(shell.page() == 4);
    CHECK_FALSE(shell.failed(4));
}

TEST_CASE("the error page quits with q or Esc") {
    for (const InputEvent& quit : {ch(U'q'), key(KeyCode::Escape)}) {
        ShellFixture fixture;
        std::vector<std::vector<std::string>> args(5);
        fixture.failure = "boom";
        toolbox::Shell shell(fixture.factories(), 2, std::move(args));
        CHECK(shell.failed(2));
        CHECK(shell.handle(quit));
    }
}

TEST_CASE("Ctrl+C quits from any page") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    CHECK(shell.handle(ch(U'c', true)));
    shell.handle(ch(U']'));
    CHECK(shell.handle(ch(U'c', true)));
}

TEST_CASE("deadlines are delegated and coalesced to one frame per 70 ms") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    ftxui::Screen screen(80, 20);
    shell.draw(screen, tui::Rect{0, 0, 80, 20});
    CHECK_FALSE(shell.next_deadline().has_value());
    fixture.pages[1]->deadline = kSteady() + std::chrono::milliseconds(1);
    const auto now = kSteady();
    const auto throttled = shell.next_deadline();
    REQUIRE(throttled.has_value());
    CHECK(*throttled >= now + std::chrono::milliseconds(40));
    CHECK(*throttled <= now + std::chrono::milliseconds(90));
    fixture.pages[1]->deadline = kSteady() + std::chrono::milliseconds(1000);
    const auto later = shell.next_deadline();
    REQUIRE(later.has_value());
    CHECK(*later >= kSteady() + std::chrono::milliseconds(900));
    shell.set_active(false);
    CHECK_FALSE(shell.next_deadline().has_value());
    CHECK_FALSE(fixture.pages[1]->active);
    shell.set_active(true);
    CHECK(shell.next_deadline().has_value());
}

TEST_CASE("focus changes stop the current page") {
    ShellFixture fixture;
    toolbox::Shell shell(fixture.factories(), 1, std::vector<std::vector<std::string>>(5));
    shell.set_active(false);
    CHECK_FALSE(fixture.pages[1]->active);
    shell.tick();
    CHECK(fixture.pages[1]->ticks == 0);
    shell.set_active(true);
    CHECK(fixture.pages[1]->active);
    shell.tick();
    CHECK(fixture.pages[1]->ticks == 1);
}

TEST_CASE("home paths are shortened for display") {
    PrivateEnv env;
    CHECK(voice::display_path(env.root() + "/models") == "~/models");
    CHECK(voice::display_path("/opt/models") == "/opt/models");
    CHECK(voice::display_path(env.root()) == env.root());
}

TEST_CASE("config defaults match mayon-voice") {
    PrivateEnv env;
    const voice::Config config = voice::load_config();
    CHECK(config.engine == "sensevoice");
    CHECK(config.device == "cpu");
    CHECK(config.threads == 4);
    CHECK(config.idle_seconds == 600);
    CHECK(config.max_record_seconds == 120);
    CHECK(config.delivery == "auto");
    CHECK(config.input_device == "auto");
    CHECK_FALSE(config.polish);
    CHECK(config.model_dir == env.root() + "/data/mayon-voice/models/sensevoice");
    CHECK_FALSE(config.model_file.has_value());
}

TEST_CASE("config overrides, comments, multi-line arrays and quoted strings") {
    PrivateEnv env;
    env.write_config(
        "# user owned\n"
        "engine = \"paraformer\"   # inline comment\n"
        "model_dir = '/tmp/models'\n"
        "device = \"cuda\"\n"
        "threads = 6\n"
        "hotwords = [\n"
        "  \"Nix\",\n"
        "  \"Mango\",\n"
        "]\n"
        "polish = true\n"
        "idle_seconds = 120\n"
        "max_record_seconds = 300\n");
    const voice::Config config = voice::load_config();
    CHECK(config.engine == "paraformer");
    CHECK(config.model_dir == "/tmp/models");
    CHECK(config.device == "cuda");
    CHECK(config.threads == 6);
    CHECK((config.hotwords == std::vector<std::string>{"Nix", "Mango"}));
    CHECK(config.polish);
    CHECK(config.idle_seconds == 120);
    CHECK(config.max_record_seconds == 300);
}

TEST_CASE("config rejects unknown fields and out-of-range values like Rust") {
    PrivateEnv env;
    env.write_config("foo = 1\n");
    CHECK_THROWS_WITH_AS(voice::load_config(), doctest::Contains("unknown field `foo`"), std::runtime_error);
    env.write_config("threads = 0\n");
    CHECK_THROWS_WITH_AS(voice::load_config(), "配置值超出允许范围", std::runtime_error);
    env.write_config("engine = \"bogus\"\n");
    CHECK_THROWS_WITH_AS(voice::load_config(), "配置值超出允许范围", std::runtime_error);
    env.write_config("max_record_seconds = 601\n");
    CHECK_THROWS_WITH_AS(voice::load_config(), "配置值超出允许范围", std::runtime_error);
    env.write_config("delivery = \"wtype\"\n");
    CHECK(voice::load_config().delivery == "wtype");
}

TEST_CASE("the screenshot config fixture parses") {
    PrivateEnv env;
    std::ifstream source(kFixtures + "/config.toml", std::ios::binary);
    REQUIRE(source.good());
    std::string body((std::istreambuf_iterator<char>(source)), std::istreambuf_iterator<char>());
    env.write_config(body);
    const voice::Config config = voice::load_config();
    CHECK(config.threads == 6);
    CHECK(config.hotwords.size() == 2);
}

TEST_CASE("status parsing follows the daemon protocol") {
    const auto idle = voice::parse_status(R"({"phase":"idle","engine":"sensevoice","device":"cpu","delivery":"fcitx","error":null})");
    REQUIRE(idle.has_value());
    CHECK(idle->phase == "idle");
    CHECK(idle->delivery == std::optional<std::string>("fcitx"));
    CHECK_FALSE(idle->error.has_value());
    const auto envelope = voice::parse_status(R"({"error":"正在识别，请稍候","status":{"phase":"transcribing"}})");
    REQUIRE(envelope.has_value());
    CHECK(envelope->phase == "inactive");
    CHECK(envelope->error == std::optional<std::string>("正在识别，请稍候"));
    CHECK_FALSE(envelope->delivery.has_value());
    const auto minimal = voice::parse_status(R"({"phase":"recording"})");
    REQUIRE(minimal.has_value());
    CHECK(minimal->phase == "recording");
    CHECK_FALSE(voice::parse_status("not json").has_value());
    const auto other = voice::parse_status("[]");
    REQUIRE(other.has_value());
    CHECK(other->phase == "inactive");
    CHECK(voice::phase_text(*minimal) == "● 录音中");
    CHECK(voice::phase_color(*minimal) == tui::kGreen);
    CHECK(voice::phase_text(voice::Status{"error", std::nullopt, "x"}) == "! 操作失败");
    CHECK(voice::phase_text(voice::Status{}) == "○ 按需待命");
}

TEST_CASE("help keeps every line without changing the retained query") {
    const std::vector<voice::Line> lines{{"快捷键"}, {"Esc 关闭帮助"}};
    const auto filtered = voice::filter_lines(lines, "无匹配内容", true);
    CHECK((filtered.ids == std::vector<size_t>{0, 1}));
    CHECK(filtered.lines[0].text == "快捷键");
}

TEST_CASE("dashboard filtering is incremental, keeps the line and renders an empty state") {
    const std::vector<voice::Line> original{{" 模型 本地"}, {" 设备 CPU"}};
    const auto before = voice::filter_lines(original, "", false);
    CHECK((before.ids == std::vector<size_t>{0, 1}));
    const auto after = voice::filter_lines(original, "shebei", false);
    REQUIRE(after.ids.size() == 1);
    CHECK(after.ids[0] == 1);
    CHECK(voice::preserve_line(1, before.ids, after.ids) == 0);
    CHECK(after.lines[0].text.find("设备") != std::string::npos);
    const auto empty = voice::filter_lines(original, "不存在", false);
    CHECK(empty.ids.empty());
    CHECK(empty.empty);
    CHECK(empty.lines[0].text.find("没有匹配") != std::string::npos);
    CHECK(empty.lines[0].text.find("Esc") != std::string::npos);
    CHECK(voice::preserve_line(0, after.ids, empty.ids) == 0);
}

TEST_CASE("the voice page polls status every 500 ms and stays idle otherwise") {
    PrivateEnv env;
    env.write_config("threads = 6\n");
    std::atomic<int> phase{0};
    MockDaemon daemon([&](const std::string& command) {
        if (command == "toggle") return std::string(R"({"phase":"recording","delivery":"fcitx","error":null})");
        return phase.load() == 0 ? std::string(R"({"phase":"idle","delivery":"auto","error":null})") : std::string(R"({"phase":"transcribing","delivery":"auto","error":null})");
    });
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    page.set_active(true);
    CHECK(page.next_deadline().has_value());
    REQUIRE(wait_for(page, [&] { return page.status().phase == "idle"; }));
    CHECK(daemon.requests() == 1);
    CHECK(page.status().delivery == std::optional<std::string>("auto"));
    CHECK(page.next_deadline() == clock.now + std::chrono::milliseconds(500));
    // No elapsed time: no extra request.
    page.tick();
    CHECK(daemon.requests() == 1);
    phase = 1;
    clock.advance(std::chrono::milliseconds(600));
    page.tick();
    REQUIRE(wait_for(page, [&] { return page.status().phase == "transcribing"; }));
    CHECK(daemon.saw("status"));
    CHECK(daemon.requests() == 2);
    // Space toggles through the same socket.
    REQUIRE_FALSE(page.handle(ch(U' ')));
    REQUIRE(wait_for(page, [&] { return page.status().phase == "recording"; }));
    CHECK(daemon.saw("toggle"));
    CHECK(daemon.saw("status"));
}

TEST_CASE("an error status is kept for five seconds") {
    PrivateEnv env;
    std::atomic<int> mode{0};  // 0 idle, 1 error
    MockDaemon daemon([&](const std::string&) {
        return mode.load() == 0 ? std::string(R"({"phase":"idle","delivery":"auto","error":null})") : std::string(R"({"phase":"error","error":"录音设备不可用"})");
    });
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    page.set_active(true);
    REQUIRE(wait_for(page, [&] { return page.status().phase == "idle"; }));
    mode = 1;
    clock.advance(std::chrono::milliseconds(600));
    page.tick();
    REQUIRE(wait_for(page, [&] { return page.status().phase == "error"; }));
    CHECK(page.status().error == std::optional<std::string>("录音设备不可用"));
    ftxui::Screen screen(80, 24);
    page.draw(screen, tui::Rect{0, 0, 80, 24});
    CHECK(squash(text_of(screen)).find("录音设备不可用") != std::string::npos);
    // Back to idle: the error text stays for the rest of the five seconds.
    mode = 0;
    clock.advance(std::chrono::milliseconds(600));
    page.tick();
    REQUIRE(wait_for(page, [&] { return page.status().phase == "idle"; }));
    CHECK(page.status().error == std::optional<std::string>("录音设备不可用"));
    clock.advance(std::chrono::seconds(6));
    page.tick();
    REQUIRE(wait_for(page, [&] { return !page.status().error.has_value(); }));
}

TEST_CASE("a failed toggle becomes the retained error phase") {
    PrivateEnv env;
    MockDaemon daemon([](const std::string&) { return std::string(R"({"phase":"idle","delivery":"auto","error":null})"); });
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    page.set_active(true);
    REQUIRE(wait_for(page, [&] { return page.status().phase == "idle"; }));
    daemon.stop();  // like a daemon that is not running
    page.handle(ch(U' '));
    REQUIRE(wait_for(page, [&] { return page.status().phase == "error"; }));
    CHECK(page.status().error.has_value());
    CHECK(page.status().error->find("语音操作失败：") == 0);
    CHECK(voice::phase_text(page.status()) == "! 操作失败");
}

TEST_CASE("an inactive voice page stops polling and cancels work") {
    PrivateEnv env;
    MockDaemon daemon([](const std::string&) { return std::string(R"({"phase":"idle","delivery":"auto","error":null})"); });
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    page.set_active(true);
    REQUIRE(wait_for(page, [&] { return page.status().phase == "idle"; }));
    const int requests = daemon.requests();
    page.set_active(false);
    clock.advance(std::chrono::seconds(5));
    page.tick();
    CHECK_FALSE(page.next_deadline().has_value());
    CHECK(daemon.requests() == requests);
    page.set_active(true);
    CHECK(page.next_deadline().has_value());
    page.tick();
    REQUIRE(wait_for(page, [&] { return daemon.requests() == requests + 1; }));
}

TEST_CASE("dashboard pages, help and filtering keys match voice.rs") {
    PrivateEnv env;
    MockDaemon daemon([](const std::string&) { return std::string(R"({"phase":"idle","delivery":"fcitx","error":null})"); });
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    page.set_active(true);
    REQUIRE(wait_for(page, [&] { return page.status().phase == "idle"; }));
    ftxui::Screen screen(100, 30);
    page.draw(screen, tui::Rect{0, 0, 100, 30});
    std::string text = squash(text_of(screen));
    CHECK(text.find("语音输入·本地中文识别") != std::string::npos);
    CHECK(text.find("○就绪") != std::string::npos);
    CHECK(text.find("引擎") != std::string::npos);
    CHECK(text.find("sensevoice/cpu") != std::string::npos);
    CHECK(text.find("上屏") != std::string::npos);
    CHECK(text.find("提示") != std::string::npos);
    page.handle(ch(U'2'));
    CHECK(page.page() == 1);
    page.draw(screen, tui::Rect{0, 0, 100, 30});
    text = squash(text_of(screen));
    CHECK(text.find("用户配置·config.toml") != std::string::npos);
    CHECK(text.find("模型") != std::string::npos);
    CHECK(text.find("麦克风") != std::string::npos);
    CHECK(text.find("空闲退出") != std::string::npos);
    page.handle(ch(U'1'));
    CHECK(page.page() == 0);
    page.handle(ch(U'?'));
    CHECK(page.help());
    page.draw(screen, tui::Rect{0, 0, 100, 30});
    text = squash(text_of(screen));
    CHECK(text.find("快捷键") != std::string::npos);
    CHECK(text.find("空格开始/结束录音") != std::string::npos);
    CHECK_FALSE(page.cursor().has_value());
    page.handle(ch(U'?'));
    CHECK_FALSE(page.help());
    page.handle(ch(U'/'));
    CHECK(page.filtering());
    page.handle(paste("yinqing"));
    page.draw(screen, tui::Rect{0, 0, 100, 30});
    REQUIRE(page.cursor().has_value());
    CHECK(page.visible_ids().size() == 1);
    page.handle(key(KeyCode::Escape));
    CHECK_FALSE(page.filtering());
    CHECK_FALSE(page.cursor().has_value());
    CHECK(page.handle(ch(U'c', true)));
}

TEST_CASE("voice filtering restores the previous query on Esc and clears on Esc outside editing") {
    PrivateEnv env;
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    page.handle(ch(U'/'));
    page.handle(paste("abc"));
    page.handle(key(KeyCode::Escape));
    CHECK_FALSE(page.filtering());
    CHECK_FALSE(page.filtering());
    page.handle(ch(U'/'));
    page.handle(paste("x"));
    page.handle(key(KeyCode::Enter));
    CHECK_FALSE(page.filtering());
    // Esc outside editing clears the filter first, then quits.
    CHECK_FALSE(page.handle(key(KeyCode::Escape)));
    CHECK(page.handle(key(KeyCode::Escape)));
}

TEST_CASE("voice page tabs are clickable and wheels scroll") {
    PrivateEnv env;
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    ftxui::Screen screen(80, 24);
    page.draw(screen, tui::Rect{0, 0, 80, 24});
    CHECK_FALSE(page.handle(mouse(InputEvent::Type::MouseClick, 2, 1)));
    CHECK(page.page() == 0);
    page.handle(mouse(InputEvent::Type::MouseClick, 10, 1));
    CHECK(page.page() == 1);
    page.handle(mouse(InputEvent::Type::WheelDown, 10, 5));
    page.handle(mouse(InputEvent::Type::WheelUp, 10, 5));
    CHECK(page.scroll() == 0);
}

TEST_CASE("voice page draws at tiny and narrow sizes without crashing") {
    PrivateEnv env;
    FakeClock clock;
    voice::VoicePage page(voice::load_config(), clock.clock());
    for (const int width : {1, 2, 8, 20, 60}) {
        for (const int height : {1, 2, 5, 10}) {
            ftxui::Screen screen(width, height);
            page.draw(screen, tui::Rect{0, 0, width, height});
            page.handle(ch(U'2'));
            page.draw(screen, tui::Rect{0, 0, width, height});
            page.handle(ch(U'?'));
            page.draw(screen, tui::Rect{0, 0, width, height});
            page.handle(ch(U'?'));
            page.handle(ch(U'/'));
            page.draw(screen, tui::Rect{0, 0, width, height});
            page.handle(key(KeyCode::Escape));
            page.handle(ch(U'1'));
        }
    }
    ftxui::Screen narrow(60, 12);
    page.draw(narrow, tui::Rect{0, 0, 60, 12});
    const std::string text = squash(text_of(narrow));
    CHECK(text.find("语音输入") != std::string::npos);
    CHECK(text.find("状态") != std::string::npos);
}
