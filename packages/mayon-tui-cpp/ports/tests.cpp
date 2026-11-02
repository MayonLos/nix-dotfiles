// Ports the Rust tests of packages/mayon-tui/crates/ports/src/lib.rs and exercises the
// command line. Everything is offline: /proc is read, Docker is never contacted.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <ftxui/screen/color.hpp>
#include <ftxui/screen/screen.hpp>
#include <sstream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <utility>
#include <unistd.h>

#include "app.hpp"
#include "page.hpp"
#include "ui/text.hpp"

using namespace ports;
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;

namespace {
Listener make(uint16_t port, const std::string& process) {
    Listener row;
    row.protocol = "TCP";
    row.address = "127.0.0.1";
    row.port = port;
    row.pid = static_cast<int32_t>(port);
    row.process = process;
    row.command = process;
    row.user = "me";
    row.age = "1s";
    row.inode = port;
    row.start_ticks = 1;
    row.uid = 1000;
    row.cwd = "/tmp";
    return row;
}
std::string text_of(ftxui::Screen& screen) {
    std::string out;
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) out += screen.PixelAt(x, y).character;
        out += '\n';
    }
    return out;
}
ftxui::Screen render(App& app, int width, int height) {
    ftxui::Screen screen(width, height);
    draw(screen, app, tui::Rect{0, 0, width, height}, nullptr);
    return screen;
}
ftxui::Color rgb(uint32_t color) {
    return ftxui::Color::RGB((color >> 16) & 255, (color >> 8) & 255, color & 255);
}
bool any_cell_with_fg(ftxui::Screen& screen, const std::string& symbol, uint32_t color) {
    for (int y = 0; y < screen.dimy(); ++y) {
        for (int x = 0; x < screen.dimx(); ++x) {
            const auto& pixel = screen.PixelAt(x, y);
            if (pixel.character == symbol && pixel.foreground_color == rgb(color)) return true;
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
std::filesystem::path scratch(const std::string& name, const std::string& body) {
    const auto path = std::filesystem::temp_directory_path() / ("ports-" + name + "-" + std::to_string(::getpid()));
    std::ofstream(path, std::ios::binary | std::ios::trunc) << body;
    return path;
}

class MockDocker {
public:
    explicit MockDocker(std::string path) : path_(std::move(path)) {
        fd_ = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        REQUIRE(fd_ >= 0);
        sockaddr_un address{};
        address.sun_family = AF_UNIX;
        REQUIRE(path_.size() < sizeof(address.sun_path));
        std::memcpy(address.sun_path, path_.c_str(), path_.size() + 1);
        ::unlink(path_.c_str());
        REQUIRE(::bind(fd_, reinterpret_cast<sockaddr*>(&address), sizeof address) == 0);
        REQUIRE(::listen(fd_, 1) == 0);
    }
    ~MockDocker() {
        if (thread_.joinable()) thread_.join();
        if (fd_ >= 0) ::close(fd_);
        ::unlink(path_.c_str());
    }
    void serve(std::string response) {
        thread_ = std::thread([this, response = std::move(response)] {
            const int client = ::accept(fd_, nullptr, nullptr);
            if (client < 0) return;
            std::string request;
            char buffer[1024];
            while (request.find("\r\n\r\n") == std::string::npos) {
                const ssize_t got = ::read(client, buffer, sizeof buffer);
                if (got <= 0) break;
                request.append(buffer, static_cast<size_t>(got));
            }
            size_t sent = 0;
            while (sent < response.size()) {
                const ssize_t written = ::send(client, response.data() + sent, response.size() - sent, MSG_NOSIGNAL);
                if (written <= 0) break;
                sent += static_cast<size_t>(written);
            }
            ::close(client);
        });
    }
    void join() {
        if (thread_.joinable()) thread_.join();
    }

private:
    std::string path_;
    int fd_ = -1;
    std::thread thread_;
};

class EnvGuard {
public:
    EnvGuard(const char* name, const char* value) : name_(name) {
        const char* old = std::getenv(name);
        if (old) {
            had_ = true;
            old_ = old;
        }
        if (value) ::setenv(name, value, 1);
        else ::unsetenv(name);
    }
    ~EnvGuard() {
        if (had_) ::setenv(name_.c_str(), old_.c_str(), 1);
        else ::unsetenv(name_.c_str());
    }

private:
    std::string name_;
    std::string old_;
    bool had_ = false;
};
std::string http(std::string_view body) {
    return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(body.size()) +
           "\r\n\r\n" + std::string(body);
}
std::string chunked(std::string_view body, size_t step) {
    std::ostringstream out;
    for (size_t at = 0; at < body.size(); at += step) {
        const std::string_view part = body.substr(at, step);
        out << std::hex << part.size() << "\r\n" << part << "\r\n";
    }
    out << "0\r\n\r\n";
    return "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + out.str();
}
Ip ip(const char* text) {
    const auto parsed = parse_ip(text);
    REQUIRE(parsed.has_value());
    return *parsed;
}
}  // namespace

TEST_CASE("filter keeps selection, cancel restores it and the empty state is safe") {
    App app;
    app.rows = {make(1001, "alpha"), make(1002, "apple"), make(1003, "beta")};
    app.selected = 1;
    app.handle_key(Key{KeyCode::Char, U'G', false, false});
    REQUIRE(app.selected_row() != nullptr);
    CHECK(app.selected_row()->process == "beta");
    app.handle_key(Key{KeyCode::Char, U'g', false, false});
    app.handle_key(Key{KeyCode::Down, 0, false, false});
    app.handle_key(Key{KeyCode::Char, U'/', false, false});
    for (const char32_t value : {U'a', U'p', U'p', U'l', U'e'}) app.handle_key(Key{KeyCode::Char, value, false, false});
    CHECK(app.filtering);
    CHECK(app.visible().size() == 1);
    REQUIRE(app.selected_row() != nullptr);
    CHECK(app.selected_row()->process == "apple");
    app.handle_key(Key{KeyCode::Up, 0, false, false});
    app.handle_key(Key{KeyCode::Escape, 0, false, false});
    CHECK(app.filter.str().empty());
    CHECK_FALSE(app.filtering);
    REQUIRE(app.selected_row() != nullptr);
    CHECK(app.selected_row()->process == "apple");

    app.handle_key(Key{KeyCode::Char, U'/', false, false});
    app.filter.paste("no-such-listener");
    const Listener* current = app.selected_row();
    app.filter_changed(current ? std::optional<SelectionKey>(current->key()) : std::nullopt);
    auto screen = render(app, 90, 20);
    const std::string empty = text_of(screen);
    CHECK(app.visible().empty());
    CHECK(empty.find("没有匹配的监听项") != std::string::npos);
    CHECK(empty.find("Esc") != std::string::npos);
    CHECK(empty.find("清除过滤") != std::string::npos);
    app.handle_key(Key{KeyCode::Enter, 0, false, false});
    CHECK_FALSE(app.filtering);
    auto committed = render(app, 90, 20);
    CHECK(text_of(committed).find("no-such-listener") != std::string::npos);
}

TEST_CASE("ipv4 and ipv6 proc hex decode") {
    CHECK(decode_addr("0100007F", false) == std::optional<std::string>("127.0.0.1"));
    CHECK(decode_addr("00000000000000000000000001000000", true) == std::optional<std::string>("::1"));
    CHECK(decode_addr("00000000000000000000000000000000", true) == std::optional<std::string>("::"));
    CHECK_FALSE(decode_addr("0100", true).has_value());
    CHECK_FALSE(decode_addr("zzzzzzzz", false).has_value());
}

TEST_CASE("parses only listening tcp rows") {
    const auto path = scratch("tcp", "sl local_address rem_address st tx_queue tr tm->when retrnsmt uid timeout inode\n"
                                     " 0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1000 0 42\n"
                                     " 1: 0100007F:1F91 00000000:0000 01 00000000:00000000 00:00000000 00000000 1000 0 43\n");
    const auto rows = socket_rows(path, "TCP", false);
    std::filesystem::remove(path);
    REQUIRE(rows.has_value());
    REQUIRE(rows->size() == 1);
    CHECK((*rows)[0] == SocketRow{"TCP", "127.0.0.1", 8080, 42});
}

TEST_CASE("parses only unconnected udp bindings") {
    const auto path = scratch("udp",
                              "sl local_address rem_address st tx_queue tr tm->when retrnsmt uid timeout inode\n"
                              " 0: 0100007F:1F90 00000000:0000 07 00000000:00000000 00:00000000 00000000 1000 0 42\n"
                              " 1: 0100007F:1F91 00000000:0000 01 00000000:00000000 00:00000000 00000000 1000 0 43\n");
    const auto rows = socket_rows(path, "UDP", false);
    std::filesystem::remove(path);
    REQUIRE(rows.has_value());
    REQUIRE(rows->size() == 1);
    CHECK((*rows)[0] == SocketRow{"UDP", "127.0.0.1", 8080, 42});
    CHECK_FALSE(socket_rows("/nonexistent/proc-net", "TCP", false).has_value());
}

TEST_CASE("refuses uid or start time mismatch") {
    ProcDetails details{"x", "x", "x", "x", std::nullopt, 123, 1000};
    CHECK(same_process(details, 1000, 123));
    CHECK_FALSE(same_process(details, 1001, 123));
    CHECK_FALSE(same_process(details, 1000, 124));
}

TEST_CASE("exposure scope distinguishes loopback wildcard and interface") {
    CHECK(scope("0.0.0.0") == "对外");
    CHECK(scope("::") == "对外");
    CHECK(scope("127.0.0.1") == "本机");
    CHECK(scope("127.42.0.7") == "本机");
    CHECK(scope("::1") == "本机");
    CHECK(scope("192.168.1.8") == "指定接口");
    CHECK(scope("2001:db8::8") == "指定接口");
    CHECK(scope("not-an-ip") == "指定接口");
}

TEST_CASE("docker default does not activate the demand socket") {
    const auto runtime = std::filesystem::temp_directory_path() / ("ports-docker-" + std::to_string(::getpid()));
    std::filesystem::create_directories(runtime);
    const auto public_socket = runtime / "docker.sock";
    CHECK(docker_socket_path(std::nullopt, runtime, false) == std::nullopt);
    CHECK(docker_socket_path("unix://" + public_socket.string(), runtime, false) == std::nullopt);
    CHECK(docker_socket_path("tcp://127.0.0.1:2375", runtime, true) == std::nullopt);
    CHECK(docker_socket_path(std::nullopt, runtime, true) == public_socket);
    const auto private_socket = runtime / "docker-private.sock";
    std::ofstream(private_socket) << "fixture";
    CHECK(docker_socket_path(std::nullopt, runtime, false) == public_socket);
    CHECK(docker_socket_path("unix://" + public_socket.string(), runtime, false) == public_socket);
    const auto custom = runtime / "custom.sock";
    CHECK(docker_socket_path("unix://" + custom.string(), runtime, false) == custom);
    CHECK(docker_socket_path(std::nullopt, std::nullopt, true) == std::nullopt);
    std::filesystem::remove_all(runtime);
}

TEST_CASE("kill requires explicit escalation and the second confirmation is cancellable") {
    App app;
    Listener row = make(32001, "test");
    row.pid = 1;
    row.start_ticks = 1;
    row.uid = static_cast<uint32_t>(::geteuid());
    app.rows = {row};
    app.handle_key(Key{KeyCode::Char, U'x', false, false});
    REQUIRE(app.confirm.has_value());
    CHECK(*app.confirm == (Confirm{1, 1, false}));
    app.handle_key(Key{KeyCode::Char, U'k', false, false});
    REQUIRE(app.confirm.has_value());
    CHECK(*app.confirm == (Confirm{1, 1, true}));
    app.handle_key(Key{KeyCode::Escape, 0, false, false});
    CHECK_FALSE(app.confirm.has_value());

    App system;
    Listener foreign = make(32002, "foreign");
    foreign.uid = std::nullopt;
    system.rows = {foreign};
    system.handle_key(Key{KeyCode::Char, U'x', false, false});
    CHECK_FALSE(system.confirm.has_value());
    CHECK(system.message == "只允许结束当前用户的进程");

    App ownerless;
    Listener orphan = make(32003, "orphan");
    orphan.pid = std::nullopt;
    ownerless.rows = {orphan};
    ownerless.handle_key(Key{KeyCode::Char, U'x', false, false});
    CHECK_FALSE(ownerless.confirm.has_value());
    CHECK(ownerless.message == "没有可见的属主进程");
}

TEST_CASE("compact and wide tables keep address pid process and scope visible") {
    for (const int width : {90, 120}) {
        CAPTURE(width);
        App app;
        Listener row = make(5173, "vite");
        row.address = "0.0.0.0";
        row.pid = 4242;
        row.user = "mayon";
        row.age = "2m";
        row.command = "node";
        for (int i = 0; i < 250; ++i) row.command += " argument";
        row.command += " tail_marker";
        row.cwd = "/project";
        row.parent = 123;
        row.uid = static_cast<uint32_t>(::geteuid());
        app.rows = {row};
        auto screen = render(app, width, 32);
        const std::string table = text_of(screen);
        for (const std::string expected : {"0.0.0.0:5173", "4242", "vite", "对外"})
            CHECK(table.find(expected) != std::string::npos);
        CHECK(any_cell_with_fg(screen, "对", tui::kRed));
        CHECK(any_cell_with_fg(screen, "D", tui::kBlue));
        app.detail = true;
        auto details_screen = render(app, width, 32);
        const std::string details = text_of(details_screen);
        CHECK(details.find("完整命令行") != std::string::npos);
        CHECK(details.find("/project") != std::string::npos);
        CHECK(details.find("tail_marker") == std::string::npos);
        app.handle_key(Key{KeyCode::PageDown, 0, false, false});
        auto tail_screen = render(app, width, 32);
        CHECK(text_of(tail_screen).find("tail_marker") != std::string::npos);
    }
}

TEST_CASE("narrow terminals keep every essential column") {
    App app;
    Listener row = make(5173, "vite");
    row.address = "0.0.0.0";
    row.pid = 4242;
    row.user = "mayon";
    row.age = "2m";
    app.rows = {row};
    auto screen = render(app, 70, 30);
    const std::string text = text_of(screen);
    for (const std::string expected : {"0.0.0.0:5173", "4242", "vite", "对外"})
        CHECK(text.find(expected) != std::string::npos);
    CHECK(text.find("用户") == std::string::npos);
}

TEST_CASE("filtered first row gets the blue selected marker") {
    App app;
    app.rows = {make(1001, "other"), make(1002, "unique-filter")};
    app.selected = 0;
    app.filter.set("unique-filter");
    auto screen = render(app, 90, 20);
    REQUIRE(app.last_body.height > 0);
    const auto& marker = screen.PixelAt(app.last_body.x + 1, app.last_body.y + 2);
    CHECK(marker.character == "▌");
    CHECK(marker.foreground_color == rgb(tui::kBlue));
    const auto& selected = screen.PixelAt(app.last_body.x + 3, app.last_body.y + 2);
    CHECK(selected.background_color == rgb(tui::kSelection));
}

TEST_CASE("mouse clicks use the table offset and ignore header padding and overlay space") {
    const tui::Rect body{0, 3, 90, 15};
    CHECK(clicked_visible_row(body, 10, 40, 11, 3, 5) == std::optional<size_t>(10));
    CHECK(clicked_visible_row(body, 10, 40, 11, 3, 6) == std::optional<size_t>(11));
    CHECK(clicked_visible_row(body, 10, 40, 11, 3, 4) == std::nullopt);   // header
    CHECK(clicked_visible_row(body, 10, 40, 11, 3, 14) == std::optional<size_t>(19));
    CHECK(clicked_visible_row(body, 10, 40, 12, 3, 16) == std::optional<size_t>(21));
    CHECK(clicked_visible_row(body, 10, 40, 12, 3, 17) == std::nullopt);
    CHECK(clicked_visible_row(body, 10, 40, 12, 100, 6) == std::nullopt);
}

TEST_CASE("docker mapping respects protocol and published address") {
    DockerBindings bindings;
    bindings.entries[{"tcp", 8080}] = {{ip("127.0.0.1"), "web-local"}, {ip("192.0.2.10"), "web-public"}};
    bindings.entries[{"udp", 8080}] = {{ip("127.0.0.1"), "dns"}};
    CHECK(docker_for_listener(bindings, "tcp", 8080, "127.0.0.1") == "web-local");
    CHECK(docker_for_listener(bindings, "tcp", 8080, "192.0.2.10") == "web-public");
    CHECK(docker_for_listener(bindings, "tcp", 8080, "127.0.0.2").empty());
    CHECK(docker_for_listener(bindings, "udp", 8080, "127.0.0.1") == "dns");
    CHECK(docker_for_listener(bindings, "tcp", 8080, "::1").empty());
    bindings.entries[{"tcp", 9000}] = {{ip("0.0.0.0"), "web-wildcard"}};
    CHECK(docker_for_listener(bindings, "tcp", 9000, "192.0.2.10") == "web-wildcard");
    bindings.entries[{"tcp", 9001}] = {{ip("::"), "web-wildcard-v6"}};
    CHECK(docker_for_listener(bindings, "tcp", 9001, "192.0.2.10").empty());
    CHECK(docker_for_listener(bindings, "tcp", 9001, "::1") == "web-wildcard-v6");
}

TEST_CASE("docker response parsing handles plain and chunked bodies") {
    const std::string body =
        R"([{"Names":["/web"],"Ports":[{"PublicPort":8080,"IP":"127.0.0.1","Type":"tcp"},{"PrivatePort":80,"Type":"tcp"},{"PublicPort":5353,"IP":"0.0.0.0","Type":"udp"}]}])";
    for (const std::string& response : {http(body), chunked(body, 17)}) {
        const auto bindings = parse_docker_response(response);
        CHECK(bindings.entries.size() == 2);
        CHECK(docker_for_listener(bindings, "tcp", 8080, "127.0.0.1") == "web");
        CHECK(docker_for_listener(bindings, "udp", 5353, "0.0.0.0") == "web");
    }
    CHECK(parse_docker_response("not http").entries.empty());
    CHECK(parse_docker_response(http("[]")).entries.empty());
    CHECK(parse_docker_response(http("{}")).entries.empty());
    CHECK(parse_docker_response(http("[{\"Names\":[\"/web\"],\"Ports\":[{\"PublicPort\":\"8080\"}]}]")).entries.empty());
}

TEST_CASE("selected socket key is stable") {
    const Listener row = make(3000, "fixture");
    Listener copy = row;
    CHECK(row.key() == copy.key());
    copy.inode += 1;
    CHECK(row.key() != copy.key());
}

TEST_CASE("refresh and sort keep the selected socket") {
    App app;
    app.rows = {make(1001, "alpha"), make(1002, "apple"), make(1003, "beta")};
    app.selected = 1;
    app.merge({make(1003, "beta"), make(1001, "alpha"), make(1002, "apple")});
    REQUIRE(app.selected_row() != nullptr);
    CHECK(app.selected_row()->process == "apple");
    for (int step = 0; step < 5; ++step) {
        app.handle_key(Key{KeyCode::Char, U's', false, false});
        REQUIRE(app.selected_row() != nullptr);
        CHECK(app.selected_row()->process == "apple");
    }
    CHECK(std::string(sort_label(app.sort)) == "端口");
    auto screen = render(app, 90, 20);
    app.handle_key(Key{KeyCode::PageDown, 0, false, false});
    CHECK(app.selected == 2);
}

TEST_CASE("help, detail and confirm overlays use the Rust text") {
    App app;
    app.rows = {make(8080, "vite")};
    auto help_screen = render(app, 120, 40);
    CHECK(text_of(help_screen).find("端口监听") != std::string::npos);
    app.help = true;
    help_screen = render(app, 120, 40);
    CHECK(text_of(help_screen).find("SIGKILL") != std::string::npos);
    CHECK(text_of(help_screen).find("/proc/net") != std::string::npos);
    app.help = false;
    app.detail = true;
    auto detail_screen = render(app, 120, 40);
    CHECK(text_of(detail_screen).find("完整命令行") != std::string::npos);
    app.detail = false;
    app.confirm = Confirm{42, 1, false};
    auto confirm_screen = render(app, 120, 40);
    CHECK(text_of(confirm_screen).find("确认结束进程") != std::string::npos);
    CHECK(text_of(confirm_screen).find("SIGTERM") != std::string::npos);
    app.confirm = Confirm{42, 1, true};
    confirm_screen = render(app, 120, 40);
    CHECK(text_of(confirm_screen).find("二次确认 · SIGKILL") != std::string::npos);
}

TEST_CASE("cli prints the Rust help and version, and otherwise opens the page") {
    CHECK(cli({}).code == -1);
    CHECK(cli({}).out.empty());
    CHECK(cli({"--docker-map"}).code == -1);
    CHECK(cli({"--bogus"}).code == -1);  // the Rust command ignores unknown arguments and opens the page
    const Cli help = cli({"--help"});
    CHECK(help.code == 0);
    CHECK(help.out == "mayon-tools ports [--docker-map]\n监听端口；--docker-map 显式请求 Docker 端口映射。\n");
    CHECK(cli({"-h"}).out == help.out);
    CHECK(cli({"--bogus", "--help"}).code == 0);
    const Cli version = cli({"--version"});
    CHECK(version.code == 0);
    CHECK(version.out == "mayon-tools ports 0.2.0\n");
    CHECK(cli({"--version", "--help"}).out == help.out);
    CHECK(cli({"--version", "--bogus"}).out == version.out);
    CHECK_FALSE(force_docker({}));
    CHECK(force_docker({"--docker-map"}));
    CHECK_FALSE(force_docker({"--help"}));
}

TEST_CASE("the public page starts inactive and stops refreshing when hidden") {
    const auto page = make_ports_page();
    CHECK_FALSE(page->next_deadline().has_value());
    page->set_active(true);
    const auto deadline = page->next_deadline();
    REQUIRE(deadline.has_value());
    CHECK(*deadline > std::chrono::steady_clock::now());
    page->set_active(false);
    CHECK_FALSE(page->next_deadline().has_value());
    const auto mapped = make_ports_page(std::vector<std::string>{"--docker-map"});
    mapped->set_active(true);
    CHECK(mapped->next_deadline().has_value());
    mapped->set_active(false);
}

TEST_CASE("docker names are read from the explicit private socket") {
    const auto runtime = std::filesystem::temp_directory_path() / ("ports-mock-" + std::to_string(::getpid()));
    std::filesystem::create_directories(runtime);
    const std::string socket_path = (runtime / "mock.sock").string();
    const EnvGuard host("DOCKER_HOST", ("unix://" + socket_path).c_str());
    const EnvGuard xdg("XDG_RUNTIME_DIR", runtime.c_str());
    const std::string body =
        R"([{"Names":["/web"],"Ports":[{"PublicPort":8080,"IP":"127.0.0.1","Type":"tcp"}]}])";
    MockDocker server(socket_path);
    server.serve(http(body));
    const auto bindings = docker_names(true);
    server.join();
    CHECK(docker_for_listener(bindings, "tcp", 8080, "127.0.0.1") == "web");
    CHECK(docker_socket_path(std::nullopt, runtime, false) == std::nullopt);
    std::filesystem::remove_all(runtime);
}
