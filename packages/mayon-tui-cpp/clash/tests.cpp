// Ports the Rust unit tests of packages/mayon-tui/crates/clash/src/{model,api,profiles,settings,native,app,ui}.rs
// and exercises the page and CLI against a private HOME and the Python mock controller.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <ftxui/screen/screen.hpp>
#include <iostream>
#include <mutex>
#include <nlohmann/json.hpp>
#include <set>
#include <sstream>
#include <thread>

#include "app.hpp"
#include "page.hpp"
#include "ui/text.hpp"
#include "yaml.hpp"

using namespace clash;
namespace fs = std::filesystem;
using nlohmann::json;

namespace {
const std::string kFixtures = FIXTURES;
constexpr auto kTimeout = std::chrono::seconds(10);

std::string slurp(const fs::path& path) {
    std::ifstream in(path, std::ios::binary);
    std::ostringstream out;
    out << in.rdbuf();
    return out.str();
}
void spit(const fs::path& path, std::string_view body, mode_t mode = 0600) {
    std::error_code code;
    fs::create_directories(path.parent_path(), code);
    std::ofstream out(path, std::ios::binary);
    out << body;
    out.close();
    ::chmod(path.c_str(), mode);
}
struct TempDir {
    fs::path path;
    TempDir() {
        std::string pattern = "/tmp/clash-test-XXXXXX";
        std::vector<char> buffer(pattern.begin(), pattern.end());
        buffer.push_back('\0');
        path = ::mkdtemp(buffer.data());
    }
    ~TempDir() {
        std::error_code code;
        fs::remove_all(path, code);
    }
    TempDir(const TempDir&) = delete;
    TempDir& operator=(const TempDir&) = delete;
};
std::string screen_text(ftxui::Screen& screen) {
    std::string out;
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) out += screen.PixelAt(x, y).character;
        out += '\n';
    }
    return out;
}
tui::Key char_key(char32_t ch, bool ctrl = false, bool alt = false) { return tui::Key{tui::KeyCode::Char, ch, ctrl, alt}; }
tui::Key code_key(tui::KeyCode code) { return tui::Key{code, 0, false, false}; }
struct PostQueue {
    std::mutex mutex;
    std::vector<std::function<void()>> jobs;
    void post(std::function<void()> job) {
        const std::lock_guard lock(mutex);
        jobs.push_back(std::move(job));
    }
    void drain() {
        std::vector<std::function<void()>> moved;
        {
            const std::lock_guard lock(mutex);
            moved.swap(jobs);
        }
        for (auto& job : moved) job();
    }
};
bool wait_until(App& app, PostQueue& queue, const std::function<bool()>& done, std::chrono::milliseconds limit = std::chrono::duration_cast<std::chrono::milliseconds>(kTimeout)) {
    const auto deadline = std::chrono::steady_clock::now() + limit;
    while (std::chrono::steady_clock::now() < deadline) {
        queue.drain();
        app.tick();
        if (done()) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    queue.drain();
    app.tick();
    return done();
}
struct Mock {
    TempDir dir;
    fs::path socket;
    fs::path actions;
    fs::path port_file;
    pid_t pid = -1;
    int http_port = -1;
    explicit Mock(const std::string& extra = {}) {
        socket = dir.path / "api.sock";
        actions = dir.path / "actions.jsonl";
        port_file = dir.path / "port.txt";
        std::vector<std::string> args{"python3", kFixtures + "/mock_controller.py", "--socket", socket.string(), "--fixture", kFixtures + "/controller.json",
                                      "--actions", actions.string(), "--port-file", port_file.string()};
        if (!extra.empty()) {
            std::istringstream stream(extra);
            for (std::string part; stream >> part;) args.push_back(part);
        }
        pid = ::fork();
        REQUIRE(pid >= 0);
        if (pid == 0) {
            const int null = ::open("/dev/null", O_RDWR);
            ::dup2(null, 1);
            ::dup2(null, 2);
            std::vector<char*> argv;
            for (auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
            argv.push_back(nullptr);
            ::execvp(argv[0], argv.data());
            ::_exit(127);
        }
        for (int i = 0; i < 500; ++i) {
            if (fs::exists(port_file) && fs::exists(socket)) {
                std::istringstream stream(slurp(port_file));
                for (std::string line; std::getline(stream, line);) {
                    if (line.rfind("PORT ", 0) == 0) http_port = std::stoi(line.substr(5));
                }
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }
    ~Mock() {
        if (pid > 0) {
            ::kill(pid, SIGTERM);
            int status = 0;
            ::waitpid(pid, &status, 0);
        }
    }
    std::vector<json> recorded() const {
        std::vector<json> out;
        std::istringstream stream(slurp(actions));
        for (std::string line; std::getline(stream, line);) {
            try {
                out.push_back(json::parse(line));
            } catch (const std::exception&) {
            }
        }
        return out;
    }
};
struct Env {
    std::map<std::string, std::string> old;
    std::set<std::string> keys;
    void set(const std::string& key, const std::string& value) {
        if (!keys.contains(key)) {
            const char* previous = std::getenv(key.c_str());
            if (previous) old[key] = previous;
            keys.insert(key);
        }
        ::setenv(key.c_str(), value.c_str(), 1);
    }
    ~Env() {
        for (const auto& key : keys) {
            if (const auto found = old.find(key); found != old.end()) ::setenv(key.c_str(), found->second.c_str(), 1);
            else ::unsetenv(key.c_str());
        }
    }
};
void make_script(const fs::path& path, const std::string& body) { spit(path, "#!/bin/sh\n" + body + "\n", 0700); }
bool python_available() {
    static const bool value = std::system("python3 -c 'import sys' >/dev/null 2>&1") == 0;
    return value;
}
#define REQUIRE_PYTHON()                                                                                    \
    do {                                                                                                    \
        if (!python_available()) {                                                                          \
            MESSAGE("python3 is unavailable; skipping the mock controller test");                            \
            return;                                                                                         \
        }                                                                                                   \
    } while (false)
Native native_for(const Mock& mock, const fs::path& data, const fs::path& mihomo, const fs::path& systemctl) {
    Native native;
    native.data = data;
    native.socket = mock.socket.string();
    native.mihomo = mihomo.string();
    native.systemctl = systemctl.string();
    return native;
}
void seed_subscription(const Native& native) {
    REQUIRE(private_dir(native.data).has_value());
    REQUIRE(private_dir(native.data / "subscriptions").has_value());
    Store store;
    store.current = "a";
    Subscription item;
    item.id = "a";
    item.name = "A";
    item.url = "http://example.invalid/a";
    item.updated = 0;
    item.interval_hours = 24;
    item.nodes = 1;
    store.items.push_back(item);
    REQUIRE(replace_file(native.data / "subscriptions/a.yaml", slurp(kFixtures + "/native-subscription.yaml")).has_value());
    const auto encoded = encode_store(store);
    REQUIRE(encoded.has_value());
    REQUIRE(replace_file(native.data / "subscriptions.toml", *encoded).has_value());
}
std::unique_ptr<App> fixture_app() {
    Options options;
    options.socket = "/nonexistent.sock";
    options.native.data = "/nonexistent";
    auto app = std::make_unique<App>(std::move(options));
    const json fixture = json::parse(slurp(kFixtures + "/controller.json"));
    SnapshotReady snapshot;
    snapshot.ok = true;
    snapshot.data.proxies = parse_proxies(fixture.dump());
    snapshot.data.config = parse_config(fixture.at("configs").dump());
    snapshot.data.version = "1.19.24";
    app->inject(std::move(snapshot));
    app->inject(ConnectionsReady{parse_connections(fixture.at("connections").dump())});
    app->tick();
    return app;
}
void set_filter(App& app, PageKind page, const std::string& text) { app.filters[static_cast<size_t>(page)].set(text); }
struct CliResult {
    int code = 0;
    std::string out;
    std::string err;
};
CliResult cli(const std::vector<std::string>& args, const std::string& stdin_text = {}) {
    std::istringstream input(stdin_text);
    std::ostringstream out, err;
    CliResult result;
    result.code = run_cli(args, input, out, err);
    result.out = out.str();
    result.err = err.str();
    return result;
}
// One-shot loopback HTTP server used to prove usage requests go through the
// explicit proxy and stop after headers instead of downloading the body.
struct ProxyServer {
    int fd = -1;
    int port = 0;
    std::thread worker;
    std::string first_line;
    ProxyServer(std::vector<std::string> responses) {
        fd = ::socket(AF_INET, SOCK_STREAM, 0);
        REQUIRE(fd >= 0);
        int one = 1;
        ::setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = 0;
        REQUIRE(::bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof address) == 0);
        REQUIRE(::listen(fd, 4) == 0);
        socklen_t length = sizeof address;
        REQUIRE(::getsockname(fd, reinterpret_cast<sockaddr*>(&address), &length) == 0);
        port = ntohs(address.sin_port);
        worker = std::thread([this, responses = std::move(responses)] {
            for (const std::string& response : responses) {
                const int conn = ::accept(fd, nullptr, nullptr);
                if (conn < 0) return;
                char buffer[4096];
                const ssize_t got = ::read(conn, buffer, sizeof buffer);
                if (got > 0 && first_line.empty()) first_line.assign(buffer, static_cast<size_t>(got));
                const ssize_t ignored = ::write(conn, response.data(), response.size());
                (void)ignored;
                ::close(conn);
            }
        });
    }
    ~ProxyServer() {
        if (worker.joinable()) worker.join();
        if (fd >= 0) ::close(fd);
    }
};
std::vector<std::string> command_with(const std::vector<std::string>& command, const std::vector<std::string>& flags) {
    std::vector<std::string> out(command);
    out.insert(out.end(), flags.begin(), flags.end());
    return out;
}
}  // namespace

TEST_CASE("parses and redacts subscription URLs like reqwest") {
    const auto url = parse_url("https://user:password@example.invalid/private?token=hidden#foo");
    REQUIRE(url.has_value());
    CHECK(url->scheme == "https");
    CHECK(url->host == "example.invalid");
    CHECK(redact_url("https://user:password@example.invalid/private?token=hidden#foo") == "https://example.invalid/…");
    CHECK(redact_url("bad token") == "地址内容隐藏");
    CHECK(redact_url("") == "等待粘贴");
    CHECK_FALSE(parse_url("http://"));
    CHECK_FALSE(parse_url("ftp://example.invalid/a"));
    CHECK_FALSE(parse_url("example.invalid/a"));
    CHECK(parse_url("HTTP://Example.INVALID:80/a")->text == "http://example.invalid/a");
    CHECK(parse_url("https://example.invalid:443/a")->text == "https://example.invalid/a");
    CHECK(encode_path({"proxies", "Group / 测试?", "delay"}) == "/proxies/Group%20%2F%20%E6%B5%8B%E8%AF%95%3F/delay");
    CHECK(encode_query("a b&c") == "a+b%26c");
    CHECK(encode_segment("A/B") == "A%2FB");
}

TEST_CASE("subscription usage headers and quotas") {
    CHECK(Usage::from_header("upload=5; download=20; total=10; expire=1893456000; source=example").has_value());
    CHECK_FALSE(Usage::from_header("upload=nope").has_value());
    CHECK_FALSE(Usage::from_header("upload").has_value());
    CHECK_FALSE(Usage::from_header("").has_value());
    CHECK_FALSE(Usage::from_header("source=example").has_value());
    Usage usage;
    usage.upload = 200;
    usage.download = 300;
    usage.total = 1000;
    usage.expire = 1893456000;
    CHECK(usage.used_bytes() == 500);
    CHECK(usage.remaining_bytes() == std::optional<uint64_t>(500));
    CHECK(usage.progress() == doctest::Approx(0.5));
    CHECK(usage.expires_at().has_value());
    Usage clamped{5, 20, 10, 0};
    CHECK(clamped.remaining_bytes() == std::optional<uint64_t>(0));
    CHECK(clamped.progress() == doctest::Approx(1.0));
    CHECK_FALSE(Usage{}.remaining_bytes().has_value());
    CHECK_FALSE(Usage{}.expires_at().has_value());
    Usage huge;
    huge.expire = UINT64_MAX;
    CHECK_FALSE(huge.expires_at().has_value());
}

TEST_CASE("index and settings round-trip Rust TOML without changing the schema") {
    const auto decoded = decode_store("current = 'a'\n[[items]]\nid = 'a'\nname = 'A'\nurl = 'https://example.invalid'\nupdated = 0\ninterval_hours = 24\nnodes = 0\nverge_current = true\n");
    REQUIRE(decoded.has_value());
    CHECK(decoded->current == std::optional<std::string>("a"));
    CHECK(decoded->items[0].legacy_current_marker);
    const auto encoded = encode_store(*decoded);
    REQUIRE(encoded.has_value());
    CHECK(encoded->find("verge_current = true") != std::string::npos);
    const auto restored = decode_store(*encoded);
    REQUIRE(restored.has_value());
    CHECK(restored->items[0].url == "https://example.invalid");
    CHECK_FALSE(decode_store("[[items]]\nid = 'a'\n").has_value());
    CHECK_FALSE(decode_store("current = 3\n").has_value());
    CHECK_FALSE(valid_id("../secret"));
    CHECK_FALSE(valid_id(""));
    CHECK(valid_id("s-1_2"));

    Settings settings;
    settings.mode = "global";
    settings.mixed_port = 32100;
    settings.baseline = "tun: {stack: system}\n";
    const auto text = encode_settings(settings);
    REQUIRE(text.has_value());
    const auto loaded = decode_settings(*text);
    REQUIRE(loaded.has_value());
    CHECK(loaded->mode == "global");
    CHECK(loaded->mixed_port == 32100);
    CHECK(loaded->baseline.find("stack: system") != std::string::npos);
    const auto defaults = decode_settings("tun = true\nmode = 'rule'\n");
    REQUIRE(defaults.has_value());
    CHECK(defaults->mixed_port == 7897);
    CHECK_FALSE(decode_settings("tun = 'yes'\n").has_value());
    CHECK_FALSE(decode_settings("mixed_port = 70000\n").has_value());
    CHECK_FALSE(decode_settings("this is not toml\n").has_value());
}

TEST_CASE("merge keeps outbounds and drops remote control and listeners") {
    Settings settings;
    settings.baseline = "tun: {stack: mixed, strict-route: false}\ndns: {nameserver: [1.1.1.1], enhanced-mode: fake-ip}\nprofile: {store-fake-ip: true}\nsniffer: {enable: false}";
    const std::string subscription = slurp(kFixtures + "/native-subscription.yaml");
    const auto merged = merge(subscription, settings, "/private/api.sock");
    REQUIRE(merged.has_value());
    const auto value = yaml::parse(*merged);
    REQUIRE(value.has_value());
    const auto original = yaml::parse(subscription);
    REQUIRE(original.has_value());
    for (const char* key : {"proxies", "proxy-groups", "rules", "proxy-providers", "rule-providers"}) {
        REQUIRE(value->find(key));
        REQUIRE(original->find(key));
        CHECK(yaml::emit(*value->find(key)) == yaml::emit(*original->find(key)));
    }
    CHECK_FALSE(value->find("external-controller"));
    CHECK_FALSE(value->find("external-controller-tls"));
    CHECK_FALSE(value->find("secret"));
    REQUIRE(value->find("external-controller-unix"));
    CHECK(value->find("external-controller-unix")->value == "/private/api.sock");
    CHECK(value->find("mixed-port")->value == "7897");
    CHECK(value->find("allow-lan")->value == "false");
    CHECK(value->find("tun")->find("enable")->value == "true");
    CHECK(value->find("profile")->find("store-selected")->value == "true");
    CHECK_FALSE(merge("not a mapping", settings, "/api").has_value());
    CHECK_FALSE(merge("proxies: nope\n", settings, "/api").has_value());
    CHECK_FALSE(merge("proxies: []\nproxies: []\n", settings, "/api").has_value());
}

TEST_CASE("saved baselines are reused and absent ones fall back to defaults") {
    Settings saved;
    saved.baseline = "tun: {stack: system, strict-route: false}\ndns: {nameserver: [1.1.1.1], enhanced-mode: fake-ip}\nsniffer: {enable: false}\nprofile: {store-fake-ip: true}";
    const std::string subscription = slurp(kFixtures + "/native-subscription.yaml");
    const auto generated = merge(subscription, saved, "/private/api.sock");
    REQUIRE(generated.has_value());
    const auto value = yaml::parse(*generated);
    REQUIRE(value.has_value());
    CHECK(value->find("tun")->find("stack")->value == "system");
    Settings defaults;
    const auto fallback = merge(subscription, defaults, "/private/api.sock");
    REQUIRE(fallback.has_value());
    const auto fallback_value = yaml::parse(*fallback);
    REQUIRE(fallback_value.has_value());
    CHECK(fallback_value->find("tun")->find("stack")->value == "mixed");
    CHECK(fallback_value->find("dns")->find("nameserver")->items[0].value == "223.5.5.5");
}

TEST_CASE("header titles, usage and intervals") {
    Headers headers;
    headers.emplace_back("profile-title", "base64:RGVtbyB0aXRsZQ==");
    headers.emplace_back("profile-update-interval", "12");
    headers.emplace_back("x-amz-meta-subscription-userinfo", "upload=1; download=2; total=10; expire=2000000000");
    const HeaderMeta meta = header_meta(headers, "fallback.invalid");
    CHECK(meta.name == "Demo title");
    REQUIRE(meta.usage.has_value());
    CHECK(meta.usage->used_bytes() == 3);
    CHECK(meta.interval == 12);
    Headers filename;
    filename.emplace_back("content-disposition", "attachment; filename*=UTF-8''Demo%20B.yaml");
    CHECK(header_meta(filename, "fallback.invalid").name == "Demo B.yaml");
    Headers plain;
    plain.emplace_back("content-disposition", "attachment; filename=\"Plain.yaml\"");
    CHECK(header_meta(plain, "fallback.invalid").name == "Plain.yaml");
    Headers invalid;
    invalid.emplace_back("profile-update-interval", "invalid");
    CHECK(header_meta(invalid, "fallback.invalid").interval == 24);
    CHECK(header_meta({}, "fallback.invalid").name == "fallback.invalid");
}

TEST_CASE("log and name redaction never prints credentials") {
    CHECK(redact_log("load https://example.invalid/?token=x failed") == "load [链接/凭据已隐藏] failed");
    CHECK(redact_log("secret=abc token=def") == "[链接/凭据已隐藏] [链接/凭据已隐藏]");
    CHECK(redact_log("普通日志") == "普通日志");
    CHECK(safe_name(std::string("A\x01") + "B").find('\x01') == std::string::npos);
    const std::string long_name(200, 'x');
    CHECK(tui::decode(safe_name(long_name)).size() == 100);
    bool ok = false;
    CHECK(base64_decode("RGVtbyB0aXRsZQ==", ok) == "Demo title");
    CHECK(ok);
    base64_decode("RGVtbyB0aXRsZQ", ok);
    CHECK_FALSE(ok);
}

TEST_CASE("YAML parser refuses duplicates and keeps scalar styles") {
    const auto value = yaml::parse("proxies:\n  - {name: 'A: B', port: 1, ok: true}\nrules: [MATCH,DIRECT]\n");
    REQUIRE(value.has_value());
    REQUIRE(value->find("proxies"));
    REQUIRE(value->find("proxies")->items[0].find("name"));
    CHECK(value->find("proxies")->items[0].find("name")->value == "A: B");
    CHECK(value->find("proxies")->items[0].find("port")->quoted == false);
    const auto emitted = yaml::emit(*value);
    const auto round = yaml::parse(emitted);
    REQUIRE(round.has_value());
    CHECK(round->find("proxies")->items[0].find("name")->value == "A: B");
    CHECK_FALSE(yaml::parse("a: 1\na: 2\n").has_value());
    CHECK_FALSE(yaml::parse("a: [1, 2\n").has_value());
    CHECK_FALSE(yaml::parse(std::string("a: \xff\n")).has_value());
    CHECK_FALSE(yaml::parse("a: 1\n---\nb: 2\n").has_value());
    const auto anchored = yaml::parse("proxies:\n  - &base {name: A, port: 1}\n  - *base\n");
    REQUIRE(anchored.has_value());
    REQUIRE(anchored->find("proxies")->items.size() == 2);
    CHECK(anchored->find("proxies")->items[1].find("name")->value == "A");
}

TEST_CASE("remote text cannot inject terminal escapes") {
    auto app = fixture_app();
    const std::string evil = "evil\x1b[31mred";
    Proxy proxy;
    proxy.name = evil;
    proxy.kind = "Http";
    app->proxies[evil] = proxy;
    app->proxies["手动选择"].all.push_back(evil);
    app->page = PageKind::Proxies;
    app->group = static_cast<size_t>(std::find(app->group_names.begin(), app->group_names.end(), "手动选择") - app->group_names.begin());
    app->rebuild_nodes();
    ftxui::Screen screen(120, 34);
    app->draw(screen, tui::Rect{0, 0, 120, 34});
    CHECK(screen_text(screen).find('\x1b') == std::string::npos);
    app->page = PageKind::Logs;
    LogEntry entry;
    entry.level = "info";
    entry.payload = "payload\x1b[2Jcleared";
    app->inject(LogReady{entry});
    app->tick();
    app->draw(screen, tui::Rect{0, 0, 120, 34});
    CHECK(screen_text(screen).find('\x1b') == std::string::npos);
}

TEST_CASE("narrow fixtures draw every page without failing") {
    auto app = fixture_app();
    for (int n = 0; n < 360; ++n) {
        const std::string name = "🇭🇰 香港 合成节点 " + std::to_string(n) + " 👩‍💻";
        Proxy proxy;
        proxy.name = name;
        proxy.kind = "Http";
        app->proxies[name] = proxy;
        app->proxies["手动选择"].all.push_back(name);
    }
    for (int width : {44, 90, 109, 160}) {
        ftxui::Screen screen(width, 34);
        for (size_t page = 0; page < kPageCount; ++page) {
            app->page = static_cast<PageKind>(page);
            app->rebuild_views();
            app->draw(screen, tui::Rect{0, 0, width, 34});
        }
    }
    CHECK(app->connection_view.size() >= 2);
}

TEST_CASE("filters keep identity and Escape restores the snapshot") {
    auto app = fixture_app();
    app->page = PageKind::Proxies;
    const auto group = std::find(app->group_names.begin(), app->group_names.end(), "手动选择");
    REQUIRE(group != app->group_names.end());
    app->group = static_cast<size_t>(group - app->group_names.begin());
    app->rebuild_nodes();
    app->node = 1;
    const std::string selected = app->node_names[1];
    app->key(char_key(U'/'));
    app->paste_text(selected);
    CHECK(app->node_names[app->node] == selected);
    app->key(code_key(tui::KeyCode::Down));
    app->key(tui::Key{tui::KeyCode::Char, U'u', true, false});
    app->filters[1].set("");
    app->paste_text("绝对不存在的节点");
    CHECK(app->node_names.empty());
    CHECK(app->node == 0);
    ftxui::Screen screen(100, 30);
    app->draw(screen, tui::Rect{0, 0, 100, 30});
    CHECK(screen_text(screen).find("无匹配节点") != std::string::npos);
    app->key(code_key(tui::KeyCode::Escape));
    CHECK(app->filter_text().empty());
    app->key(char_key(U'/'));
    app->paste_text("xianggang");
    CHECK(std::all_of(app->node_names.begin(), app->node_names.end(), [](const std::string& name) { return name.find("香港") != std::string::npos; }));
    app->key(code_key(tui::KeyCode::Enter));
    app->key(char_key(U'/'));
    app->paste_text("bad");
    app->key(code_key(tui::KeyCode::Escape));
    CHECK(app->filter_text() == "xianggang");
    app->key(code_key(tui::KeyCode::Escape));
    CHECK(app->filter_text().empty());
    set_filter(*app, PageKind::Proxies, "xggs");
    app->rebuild_nodes();
    CHECK(app->node_names.size() == 1);
}

TEST_CASE("sorting, timeout hiding and stale delays") {
    auto app = fixture_app();
    app->page = PageKind::Proxies;
    app->group = static_cast<size_t>(std::find(app->group_names.begin(), app->group_names.end(), "手动选择") - app->group_names.begin());
    app->rebuild_nodes();
    const auto original = app->node_names;
    app->sort = Sort::Delay;
    app->rebuild_nodes();
    CHECK(app->node_names.back() == "超时节点");
    app->hide_timeout = true;
    app->rebuild_nodes();
    CHECK(app->node_names.size() == 2);
    app->hide_timeout = false;
    app->sort = Sort::Name;
    app->rebuild_nodes();
    CHECK(app->node_names.size() == 3);
    app->sort = Sort::Default;
    app->rebuild_nodes();
    CHECK(app->node_names == original);
    const uint64_t old = app->generation;
    app->cancel_measure();
    app->inject(DelayReady{old, "stale", 9});
    app->tick();
    CHECK(app->delays.find("stale") == app->delays.end());
    CHECK(app->chain().find("GLOBAL → 手动选择 → 🇭🇰") != std::string::npos);
}

TEST_CASE("connection selection and the confirmed close snapshot stay stable") {
    auto app = fixture_app();
    app->page = PageKind::Connections;
    app->connection_sort = 1;
    app->rebuild_views();
    const auto found = std::find_if(app->connection_view.begin(), app->connection_view.end(), [&](size_t index) { return app->connections[index].id == "b"; });
    REQUIRE(found != app->connection_view.end());
    app->connection = static_cast<size_t>(found - app->connection_view.begin());
    REQUIRE(app->selected_connection());
    CHECK(app->selected_connection()->id == "b");
    app->key(char_key(U'x'));
    REQUIRE(app->dialog.has_value());
    CHECK(app->dialog->kind == Dialog::Kind::Confirm);
    CHECK(app->dialog->action.ids == std::vector<std::string>{"b"});
    app->key(code_key(tui::KeyCode::Escape));
    CHECK_FALSE(app->dialog.has_value());
    set_filter(*app, PageKind::Connections, "firefox");
    app->rebuild_views();
    CHECK(app->connection_view.size() == 1);
    app->key(char_key(U'd'));
    REQUIRE(app->dialog.has_value());
    CHECK(app->dialog->action.ids == std::vector<std::string>{"b"});
    app->key(code_key(tui::KeyCode::Escape));
    ConnectionsResponse reversed;
    reversed.connections = app->connections;
    std::reverse(reversed.connections.begin(), reversed.connections.end());
    app->inject(ConnectionsReady{reversed});
    app->tick();
    REQUIRE(app->selected_connection());
    CHECK(app->selected_connection()->id == "b");
    app->page = PageKind::Profiles;
    Subscription current_item;
    current_item.id = "a";
    current_item.name = "A";
    app->store.current = "a";
    app->store.items = {current_item};
    app->profile = 0;
    app->key(char_key(U'd'));
    CHECK_FALSE(app->dialog.has_value());
    CHECK(app->status.find("当前订阅不能删除") != std::string::npos);
    CHECK(app->next_deadline() == std::nullopt);
}

TEST_CASE("identical snapshots release the refresh slot") {
    auto app = fixture_app();
    app->refresh_running = true;
    SnapshotReady snapshot;
    snapshot.ok = true;
    snapshot.data = Snapshot{app->proxies, app->config, app->version};
    app->inject(std::move(snapshot));
    app->tick();
    CHECK_FALSE(app->refresh_running);
    app->resources_running = true;
    ResourcesReady resources;
    resources.ok = true;
    resources.data = Resources{app->providers, app->rule_providers, app->rules};
    app->inject(std::move(resources));
    app->tick();
    CHECK_FALSE(app->resources_running);
}

TEST_CASE("log buffer is bounded, pause drops records and levels filter") {
    auto app = fixture_app();
    for (int i = 0; i < 2100; ++i) {
        LogEntry entry;
        entry.level = "info";
        entry.payload = "message " + std::to_string(i);
        app->inject(LogReady{entry});
        app->tick();
    }
    CHECK(app->logs.size() == 2000);
    CHECK(app->log == 1999);
    app->logs_paused = true;
    app->inject(LogReady{LogEntry{0, "info", "ignored"}});
    app->tick();
    CHECK(app->logs.size() == 2000);
    app->log_level = 3;
    app->rebuild_logs();
    CHECK(app->log_view.empty());
    app->dirty = false;
    app->tick();
    CHECK_FALSE(app->dirty);
}

TEST_CASE("usage requests use the explicit proxy and stop after headers") {
    ProxyServer server({"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        "HTTP/1.1 200 OK\r\nSubscription-Userinfo: upload=5; download=10; total=100\r\nContent-Length: 1000000000\r\nConnection: close\r\n\r\n"});
    const auto usage = usage_request("http://unresolvable.invalid/sub", "http://127.0.0.1:" + std::to_string(server.port));
    REQUIRE(usage.has_value());
    CHECK(usage->used_bytes() == 15);
    CHECK(usage->remaining_bytes() == std::optional<uint64_t>(85));
    CHECK(server.first_line.rfind("HEAD http://unresolvable.invalid/sub", 0) == 0);
    ProxyServer redirect({"HTTP/1.1 302 Found\r\nLocation: http://example.invalid/elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                          "HTTP/1.1 302 Found\r\nLocation: http://example.invalid/elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"});
    CHECK_FALSE(usage_request("http://unresolvable.invalid/sub", "http://127.0.0.1:" + std::to_string(redirect.port)).has_value());
}

TEST_CASE("options parse all supported flags and help") {
    std::ostringstream out;
    auto* previous = std::cout.rdbuf(out.rdbuf());
    Options options;
    std::string error;
    CHECK(parse_options({"--help"}, options, error) == ParseResult::Exit);
    CHECK(out.str().find("--data-dir PATH") != std::string::npos);
    CHECK(parse_options({"--version"}, options, error) == ParseResult::Exit);
    std::cout.rdbuf(previous);
    CHECK(parse_options({"--data-dir", "/tmp/x", "--socket", "/tmp/s", "--mihomo", "/tmp/m", "--systemctl", "/tmp/sys", "--test-url", "https://example.invalid/g", "--usage-proxy",
                         "http://127.0.0.1:1"},
                        options, error) == ParseResult::Run);
    CHECK(options.native.data == "/tmp/x");
    CHECK(options.native.socket == "/tmp/s");
    CHECK(options.usage_proxy == std::optional<std::string>("http://127.0.0.1:1"));
    CHECK(parse_options({"--data-dir"}, options, error) == ParseResult::Error);
    CHECK(error == "需要数据目录");
    CHECK(parse_options({"--socket"}, options, error) == ParseResult::Error);
    CHECK(error == "--socket 需要路径");
    CHECK(parse_options({"--bogus"}, options, error) == ParseResult::Error);
    CHECK(error == "未知参数，请用 --help 查看");
    CHECK(parse_options({"--test-url", "ftp://example.invalid"}, options, error) == ParseResult::Error);
    CHECK(error == "测速地址必须为 http(s) URL");
    CHECK(parse_options({"--test-url", "https://x.invalid", "--timeout"}, options, error) == ParseResult::Error);
}

TEST_CASE("preferences file is optional and unknown keys are rejected") {
    TempDir dir;
    Env env;
    env.set("HOME", dir.path.string());
    env.set("XDG_CONFIG_HOME", (dir.path / "config").string());
    Options options;
    std::string error;
    CHECK(parse_options({}, options, error) == ParseResult::Run);
    spit(dir.path / "config/mayon-tui/clash.toml", "backend = 'verge'\nconcurrency = 2\ndefault_sort = 'delay'\n", 0600);
    CHECK_MESSAGE(parse_options({}, options, error) == ParseResult::Run, error);
    CHECK(options.prefs.concurrency == 2);
    CHECK(options.prefs.default_sort == "delay");
    spit(dir.path / "config/mayon-tui/clash.toml", "secret = 'x'\n", 0600);
    CHECK(parse_options({}, options, error) == ParseResult::Error);
    CHECK(error == "Clash TUI 配置格式无效");
    spit(dir.path / "config/mayon-tui/clash.toml", "timeout_ms = 1\n", 0600);
    CHECK(parse_options({}, options, error) == ParseResult::Error);
    CHECK(error.find("配置范围无效") != std::string::npos);
    spit(dir.path / "config/mayon-tui/clash.toml", "test_url = 'ftp://x'\n", 0600);
    CHECK(parse_options({}, options, error) == ParseResult::Error);
    const fs::path custom = dir.path / "custom.toml";
    spit(custom, "concurrency = 7\n", 0600);
    CHECK(parse_options({"--config", custom.string()}, options, error) == ParseResult::Run);
    CHECK(options.prefs.concurrency == 7);
}

TEST_CASE("validator children cannot open Internet sockets") {
    const pid_t child = ::fork();
    REQUIRE(child >= 0);
    if (child == 0) {
        if (!validation_network_filter()) ::_exit(2);
        const int fd = ::socket(AF_INET, SOCK_STREAM, 0);
        const int code = errno;
        ::_exit(fd < 0 && code == ENETUNREACH ? 0 : 3);
    }
    int status = 0;
    ::waitpid(child, &status, 0);
    CHECK(WIFEXITED(status));
    CHECK(WEXITSTATUS(status) == 0);
}

TEST_CASE("validation failures never change the previous config") {
    REQUIRE_PYTHON();
    TempDir dir;
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    Mock mock;
    Native native = native_for(mock, dir.path / "data", validator, dir.path / "unused");
    seed_subscription(native);
    REQUIRE(native.generate().has_value());
    const std::string before = slurp(native.data / "config.yaml");
    make_script(validator, "exit 1");
    native.mihomo = validator.string();
    const auto changed = native.change("mode", "global", false);
    CHECK_FALSE(changed.has_value());
    CHECK(changed.error().find("校验") != std::string::npos);
    CHECK(slurp(native.data / "config.yaml") == before);
    CHECK(native.settings()->mode == "rule");
    bool temporary = false;
    for (const auto& entry : fs::directory_iterator(native.data)) temporary |= entry.path().filename().string().find("tmp-") != std::string::npos;
    CHECK_FALSE(temporary);
}

TEST_CASE("hot reload failures roll back files and inactive settings persist") {
    REQUIRE_PYTHON();
    TempDir dir;
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    const fs::path systemctl = dir.path / "systemctl";
    make_script(systemctl, "exit 0");
    Mock rejecting("--reload-fail-once --settings-configs");
    Native native = native_for(rejecting, dir.path / "data", validator, systemctl);
    seed_subscription(native);
    REQUIRE(native.generate().has_value());
    const std::string before = slurp(native.data / "config.yaml");
    const auto changed = native.change("mode", "global", true);
    REQUIRE_FALSE(changed.has_value());
    CHECK(changed.error().find("已回滚") != std::string::npos);
    CHECK(slurp(native.data / "config.yaml") == before);
    CHECK(native.settings()->mode == "rule");
    CHECK(native.change("mode", "direct", false).has_value());
    CHECK(native.settings()->mode == "direct");
}

TEST_CASE("successful reload with the wrong listener state also rolls back") {
    REQUIRE_PYTHON();
    TempDir dir;
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    Mock wrong("--settings-configs");
    Native native = native_for(wrong, dir.path / "data", validator, dir.path / "unused");
    seed_subscription(native);
    REQUIRE(native.generate().has_value());
    const auto changed = native.change("mixed-port", "12345", true);
    REQUIRE_FALSE(changed.has_value());
    CHECK(changed.error().find("已回滚") != std::string::npos);
    CHECK(native.settings()->mixed_port == 7897);
}

TEST_CASE("writer lock excludes concurrent transactions and ids stay in their directory") {
    REQUIRE_PYTHON();
    TempDir dir;
    Mock mock;
    Native native = native_for(mock, dir.path / "data", dir.path / "unused", dir.path / "unused");
    {
        const auto first = native.lock();
        REQUIRE(first.has_value());
        CHECK_FALSE(native.lock().has_value());
    }
    CHECK(native.lock().has_value());
    CHECK_FALSE(native.profile_path("../secret").has_value());
    for (const char* id : {"", "a/b", "a b"}) CHECK_FALSE(native.profile_path(id).has_value());
    CHECK_FALSE(native.profile_path(std::string(96, 'x')).has_value());
}

TEST_CASE("private files are 0600 and the data directory is 0700") {
    REQUIRE_PYTHON();
    TempDir dir;
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    Mock mock;
    Native native = native_for(mock, dir.path / "data", validator, dir.path / "unused");
    seed_subscription(native);
    struct stat info {};
    REQUIRE(::stat(native.data.c_str(), &info) == 0);
    CHECK((info.st_mode & 0777) == 0700);
    REQUIRE(::stat((native.data / "subscriptions.toml").c_str(), &info) == 0);
    CHECK((info.st_mode & 0777) == 0600);
    REQUIRE(::stat((native.data / "subscriptions/a.yaml").c_str(), &info) == 0);
    CHECK((info.st_mode & 0777) == 0600);
}

TEST_CASE("CLI validates arguments and leaves unknown commands to the TUI") {
    REQUIRE_PYTHON();
    CHECK(cli({}).code == -1);
    CHECK(cli({"--help"}).code == -1);
    TempDir dir;
    Env env;
    env.set("HOME", dir.path.string());
    const Mock mock;
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    const fs::path systemctl = dir.path / "systemctl";
    make_script(systemctl, "exit 0");
    const auto base = std::vector<std::string>{"--data-dir", (dir.path / "data").string(), "--socket", mock.socket.string(), "--mihomo", validator.string(), "--systemctl", systemctl.string()};
    auto args = command_with({"profile"}, base);
    CHECK(cli(args).code == 1);
    args.push_back("list");
    CHECK(cli(args).out.empty());
    args.pop_back();
    args.push_back("nope");
    const auto unknown = cli(args);
    CHECK(unknown.code == 1);
    CHECK(unknown.err == "Clash TUI：非交互命令无效，参见 README\n");
    CHECK(cli({"profile", "list", "--data-dir"}).err.find("缺少目录") != std::string::npos);
}

TEST_CASE("CLI profile transactions share the Rust data layout") {
    REQUIRE_PYTHON();
    TempDir dir;
    Env env;
    env.set("HOME", dir.path.string());
    env.set("XDG_CONFIG_HOME", (dir.path / "config").string());
    env.set("XDG_DATA_HOME", (dir.path / "xdg-data").string());
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    const fs::path systemctl = dir.path / "systemctl";
    make_script(systemctl, "echo \"$@\" >> " + (dir.path / "systemctl.log").string() + "\nexit 0");
    Mock mock("--http-port 0 --subscription " + kFixtures + "/native-subscription.yaml");
    REQUIRE(mock.http_port > 0);
    const std::string data = (dir.path / "data").string();
    const auto base = std::vector<std::string>{"--data-dir", data, "--socket", mock.socket.string(), "--mihomo", validator.string(), "--systemctl", systemctl.string()};
    // The mock runtime config must match the settings used for hot reload.
    Native seed = native_for(mock, data, validator, systemctl);
    Settings settings;
    settings.tun = true;
    settings.mode = "global";
    settings.mixed_port = 32100;
    const auto settings_text = encode_settings(settings);
    REQUIRE(settings_text.has_value());
    REQUIRE(private_dir(data).has_value());
    REQUIRE(replace_file(fs::path(data) / "settings.toml", *settings_text).has_value());
    const std::string url = "http://127.0.0.1:" + std::to_string(mock.http_port) + "/sub\n";
    const auto added = cli(command_with({"profile", "add"}, base), url);
    REQUIRE(added.code == 0);
    const auto listed = command_with({"profile", "list"}, base);
    const auto list = cli(listed);
    REQUIRE(list.code == 0);
    CHECK(list.out.find("Demo title") != std::string::npos);
    CHECK(list.out.find('\t') != std::string::npos);
    const std::string id = list.out.substr(0, list.out.find('\t'));
    const auto first_store = seed.store();
    REQUIRE(first_store.has_value());
    REQUIRE(first_store->items.size() == 1);
    CHECK(first_store->items[0].name == "Demo title");
    CHECK(first_store->items[0].interval_hours == 12);
    CHECK(first_store->items[0].nodes == 1);
    REQUIRE(first_store->items[0].usage.has_value());
    CHECK(first_store->items[0].usage->used_bytes() == 3);
    CHECK(fs::exists(fs::path(data) / "subscriptions" / (id + ".yaml")));
    CHECK(fs::exists(fs::path(data) / "config.yaml"));
    const auto config = yaml::parse(slurp(fs::path(data) / "config.yaml"));
    REQUIRE(config.has_value());
    REQUIRE(config->find("external-controller-unix"));
    CHECK(config->find("external-controller-unix")->value == mock.socket.string());
    CHECK(config->find("mixed-port")->value == "32100");
    CHECK_FALSE(config->find("secret"));
    CHECK(cli(command_with({"profile", "rename", id, "Renamed"}, base)).code == 0);
    CHECK(cli(listed).out.find("Renamed") != std::string::npos);
    CHECK(cli(command_with({"profile", "add", "Second"}, base), url).code == 0);
    const auto refused = cli(command_with({"profile", "delete", id, "--yes"}, base));
    CHECK(refused.code == 1);
    CHECK(refused.err.find("当前订阅不能删除") != std::string::npos);
    const auto guarded = cli(command_with({"profile", "delete", id, "--no"}, base));
    CHECK(guarded.code == 1);
    CHECK(guarded.err.find("删除需要 --yes") != std::string::npos);
    auto store = seed.store();
    REQUIRE(store.has_value());
    REQUIRE(store->items.size() == 2);
    const std::string second = store->items[1].id;
    CHECK(cli(command_with({"profile", "delete", second, "--yes"}, base)).code == 0);
    CHECK_FALSE(fs::exists(fs::path(data) / "subscriptions" / (second + ".yaml")));
    CHECK(cli(command_with({"profile", "url", id}, base), url).code == 0);
    CHECK(cli(command_with({"profile", "use", id}, base)).code == 0);
    CHECK(cli(command_with({"profile", "generate"}, base)).code == 0);
    const auto bad_add = command_with({"profile", "add"}, base);
    const auto bad = cli(bad_add, "not-a-url\n");
    CHECK(bad.code == 1);
    CHECK(bad.err.find("订阅 URL 无效") != std::string::npos);
    const auto oversized = cli(bad_add, std::string(20000, 'x') + "\n");
    CHECK(oversized.code == 1);
    CHECK(oversized.err.find("URL 过长") != std::string::npos);
    const auto invalid_utf8 = cli(bad_add, std::string("http://example.invalid/\xff\n"));
    CHECK(invalid_utf8.code == 1);
    CHECK(invalid_utf8.err.find("无法读取 URL") != std::string::npos);
    // Settings persist without a controller (running=false), so no hot reload is attempted.
    auto offline = base;
    offline[3] = (dir.path / "missing.sock").string();
    CHECK(cli(command_with({"settings", "mode", "direct"}, offline)).code == 0);
    auto settings_reloaded = seed.settings();
    REQUIRE(settings_reloaded.has_value());
    CHECK(settings_reloaded->mode == "direct");
    const auto invalid = cli(command_with({"settings", "mode", "bogus"}, offline));
    CHECK(invalid.code == 1);
    CHECK(invalid.err.find("设置名称或取值无效") != std::string::npos);
    CHECK(cli(command_with({"service", "start"}, offline)).code == 0);
    CHECK(cli(command_with({"service", "stop"}, offline)).code == 0);
    const std::string log = slurp(dir.path / "systemctl.log");
    CHECK(log.find("start mayon-clash.service") != std::string::npos);
    CHECK(log.find("stop mayon-clash.service") != std::string::npos);
}

TEST_CASE("App drives the mock controller for selection, delay and streams") {
    REQUIRE_PYTHON();
    TempDir dir;
    const fs::path validator = dir.path / "validator";
    make_script(validator, "exit 0");
    const fs::path systemctl = dir.path / "systemctl";
    make_script(systemctl, "exit 0");
    Mock mock;
    Options options;
    options.socket = mock.socket;
    options.native = native_for(mock, dir.path / "data", validator, systemctl);
    options.prefs.timeout_ms = 1000;
    auto app = std::make_unique<App>(std::move(options));
    PostQueue queue;
    app->attach([&queue](std::function<void()> job) { queue.post(std::move(job)); });
    app->set_active(true);
    REQUIRE(wait_until(*app, queue, [&] { return app->online && !app->proxies.empty(); }));
    CHECK(app->version == "Meta 1.19.24");
    CHECK(app->group_names.size() >= 5);
    REQUIRE(wait_until(*app, queue, [&] { return !app->connections.empty() && app->connections_live; }));
    REQUIRE(wait_until(*app, queue, [&] { return app->traffic.has_value(); }));
    CHECK(app->traffic->up > 0);
    app->key(char_key(U'2'));
    const auto group = std::find(app->group_names.begin(), app->group_names.end(), "手动选择");
    REQUIRE(group != app->group_names.end());
    app->group = static_cast<size_t>(group - app->group_names.begin());
    app->rebuild_nodes();
    app->node = 0;
    const std::string selected = app->node_names[0];
    app->key(code_key(tui::KeyCode::Enter));
    REQUIRE(wait_until(*app, queue, [&] {
        for (const auto& entry : mock.recorded()) {
            if (entry.value("method", "") == "PUT" && entry.value("path", "").find("/proxies/") == 0) return true;
        }
        return false;
    }));
    bool selected_ok = false;
    for (const auto& entry : mock.recorded()) {
        if (entry.value("method", "") == "PUT" && entry.value("path", "").rfind("/proxies/", 0) == 0) {
            const auto body = json::parse(entry.value("body", "{}"));
            selected_ok = body.value("name", "") == selected;
        }
    }
    CHECK(selected_ok);
    app->key(char_key(U't'));
    REQUIRE(wait_until(*app, queue, [&] { return app->delays.count(selected) > 0; }));
    CHECK(app->delays[selected] == std::optional<uint64_t>(42));
    app->key(char_key(U'4'));
    app->rebuild_views();
    app->connection = 0;
    app->key(char_key(U'x'));
    REQUIRE(app->dialog.has_value());
    app->key(code_key(tui::KeyCode::Enter));
    REQUIRE(wait_until(*app, queue, [&] {
        for (const auto& entry : mock.recorded()) {
            if (entry.value("method", "") == "DELETE" && entry.value("path", "").rfind("/connections", 0) == 0) return true;
        }
        return false;
    }));
    app->key(char_key(U'6'));
    REQUIRE(wait_until(*app, queue, [&] { return !app->logs.empty(); }));
    bool redacted = false;
    for (const auto& entry : app->logs) redacted |= entry.payload.find("[链接/凭据已隐藏]") != std::string::npos;
    CHECK(redacted);
    app->set_active(false);
    CHECK_FALSE(app->active());
    CHECK(app->next_deadline() == std::nullopt);
}
