#include "app.hpp"

#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <set>
#include <sstream>

#include "ui/text.hpp"

namespace clash {
namespace {
constexpr const char* kVersion = "0.2.0";
bool contains(std::string_view text, std::string_view part) { return text.find(part) != std::string_view::npos; }
bool is_space(char c) { return c == ' ' || c == '\t'; }
std::string trim(std::string_view text) {
    while (!text.empty() && is_space(text.front())) text.remove_prefix(1);
    while (!text.empty() && is_space(text.back())) text.remove_suffix(1);
    return std::string(text);
}
int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
bool decode_toml_string(std::string_view line, size_t& at, std::string& out) {
    if (at >= line.size()) return false;
    const char quote = line[at];
    if (quote != '"' && quote != '\'') return false;
    ++at;
    while (at < line.size()) {
        const char c = line[at];
        if (c == quote) {
            ++at;
            return true;
        }
        if (quote == '\'' || c != '\\') {
            out += c;
            ++at;
            continue;
        }
        ++at;
        if (at >= line.size()) return false;
        const char esc = line[at++];
        switch (esc) {
            case 'b': out += '\b'; break;
            case 't': out += '\t'; break;
            case 'n': out += '\n'; break;
            case 'f': out += '\f'; break;
            case 'r': out += '\r'; break;
            case '"': out += '"'; break;
            case '\\': out += '\\'; break;
            case 'u':
            case 'U': {
                const int digits = esc == 'u' ? 4 : 8;
                if (at + static_cast<size_t>(digits) > line.size()) return false;
                char32_t code = 0;
                for (int k = 0; k < digits; ++k) {
                    const int value = hex_value(line[at + k]);
                    if (value < 0) return false;
                    code = (code << 4) | static_cast<char32_t>(value);
                }
                at += static_cast<size_t>(digits);
                tui::append(out, code);
                break;
            }
            default: return false;
        }
    }
    return false;
}
struct PrefsValue {
    enum class Kind { String, Integer, Boolean } kind = Kind::String;
    std::string text;
    int64_t number = 0;
    bool flag = false;
};
bool parse_prefs_value(std::string_view raw, PrefsValue& out) {
    const std::string trimmed = trim(raw);
    raw = trimmed;
    if (raw.empty()) return false;
    if (raw.front() == '"' || raw.front() == '\'') {
        size_t at = 0;
        std::string value;
        if (!decode_toml_string(raw, at, value)) return false;
        if (at != raw.size()) return false;
        out.kind = PrefsValue::Kind::String;
        out.text = std::move(value);
        return true;
    }
    if (raw == "true" || raw == "false") {
        out.kind = PrefsValue::Kind::Boolean;
        out.flag = raw == "true";
        return true;
    }
    std::string number;
    for (const char c : raw) {
        if (c != '_') number += c;
    }
    if (number.empty()) return false;
    int64_t value = 0;
    const auto [ptr, error] = std::from_chars(number.data(), number.data() + number.size(), value);
    if (error != std::errc{} || ptr != number.data() + number.size()) return false;
    out.kind = PrefsValue::Kind::Integer;
    out.number = value;
    return true;
}
std::string prefs_strip_comment(std::string_view line) {
    bool single = false, doubly = false;
    for (size_t i = 0; i < line.size(); ++i) {
        const char c = line[i];
        if (single) {
            if (c == '\'') single = false;
        } else if (doubly) {
            if (c == '\\') ++i;
            else if (c == '"') doubly = false;
        } else if (c == '\'') {
            single = true;
        } else if (c == '"') {
            doubly = true;
        } else if (c == '#') {
            return std::string(line.substr(0, i));
        }
    }
    return std::string(line);
}
// settings.rs: serde deny_unknown_fields and every field defaulted.
bool load_prefs(const std::filesystem::path& path, Prefs& out, std::string& error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        std::error_code code;
        const bool missing = !std::filesystem::exists(path, code);
        if (missing) {
            out = Prefs{};
            return true;
        }
        error = "无法读取 Clash TUI 配置";
        return false;
    }
    std::ostringstream buffer;
    buffer << in.rdbuf();
    std::istringstream lines(buffer.str());
    Prefs prefs;
    std::set<std::string> seen;
    for (std::string line; std::getline(lines, line);) {
        const std::string text = trim(prefs_strip_comment(line));
        if (text.empty()) continue;
        if (text.front() == '[') {
            error = "Clash TUI 配置格式无效";
            return false;
        }
        const auto equal = text.find('=');
        if (equal == std::string::npos) {
            error = "Clash TUI 配置格式无效";
            return false;
        }
        const std::string key = trim(std::string_view(text).substr(0, equal));
        PrefsValue value;
        if (!parse_prefs_value(std::string_view(text).substr(equal + 1), value) || !seen.insert(key).second) {
            error = "Clash TUI 配置格式无效";
            return false;
        }
        if (key == "backend") {
            if (value.kind != PrefsValue::Kind::String) {
                error = "Clash TUI 配置格式无效";
                return false;
            }
        } else if (key == "test_url") {
            if (value.kind != PrefsValue::Kind::String) {
                error = "Clash TUI 配置格式无效";
                return false;
            }
            prefs.test_url = value.text;
        } else if (key == "timeout_ms" || key == "concurrency" || key == "default_page") {
            if (value.kind != PrefsValue::Kind::Integer || value.number < 0) {
                error = "Clash TUI 配置格式无效";
                return false;
            }
            const auto number = static_cast<uint64_t>(value.number);
            if (key == "timeout_ms") prefs.timeout_ms = number;
            else if (key == "concurrency") prefs.concurrency = number;
            else prefs.default_page = number;
        } else if (key == "default_sort") {
            if (value.kind != PrefsValue::Kind::String) {
                error = "Clash TUI 配置格式无效";
                return false;
            }
            prefs.default_sort = value.text;
        } else {
            error = "Clash TUI 配置格式无效";
            return false;
        }
    }
    out = std::move(prefs);
    return true;
}
}  // namespace

const char* const kTabs[kPageCount] = {"概览", "代理", "订阅", "连接", "规则", "日志", "工具"};
const char* sort_label(Sort value) {
    switch (value) {
        case Sort::Default: return "默认";
        case Sort::Delay: return "延迟";
        case Sort::Name: return "名称";
    }
    return "默认";
}
uint32_t tone_color(Tone value) {
    switch (value) {
        case Tone::Info: return tui::kMuted;
        case Tone::Action: return tui::kBlue;
        case Tone::Success: return tui::kGreen;
        case Tone::Warning: return tui::kYellow;
        case Tone::Error: return tui::kRed;
    }
    return tui::kMuted;
}
const char* tone_symbol(Tone value) {
    switch (value) {
        case Tone::Info: return "·";
        case Tone::Action: return "›";
        case Tone::Success: return "✓";
        case Tone::Warning: return "!";
        case Tone::Error: return "×";
    }
    return "·";
}
std::string Prefs::validate() const {
    if (timeout_ms < 100 || timeout_ms > 30000 || concurrency < 1 || concurrency > 32 || default_page < 1 || default_page > 7 ||
        !(default_sort == "default" || default_sort == "delay" || default_sort == "name")) {
        return "配置范围无效：超时 100–30000ms，并发 1–32，首页 1–7，排序 default/delay/name";
    }
    if (!parse_url(test_url)) return "测速地址必须为 http(s) URL";
    return {};
}
std::filesystem::path default_data_dir() {
    const char* home = std::getenv("HOME");
    return std::filesystem::path(home ? home : "") / ".local/share/mayon-clash";
}
std::filesystem::path default_config_path() {
    const char* home = std::getenv("HOME");
    const char* config = std::getenv("XDG_CONFIG_HOME");
    const std::filesystem::path base = config && *config ? std::filesystem::path(config) : std::filesystem::path(home ? home : "") / ".config";
    return base / "mayon-tui/clash.toml";
}
ParseResult parse_options(const std::vector<std::string>& args, Options& out, std::string& error) {
    const bool help_anywhere = std::any_of(args.begin(), args.end(), [](const std::string& arg) { return arg == "--help" || arg == "-h" || arg == "--version"; });
    std::filesystem::path config_path = default_config_path();
    for (size_t i = 0; i + 1 < args.size(); ++i) {
        if (args[i] == "--config") {
            config_path = args[i + 1];
            break;
        }
    }
    Options options;
    options.native.data = default_data_dir();
    options.native.socket = "/run/mayon-clash/mihomo.sock";
    options.native.mihomo = "mihomo";
    options.native.systemctl = "systemctl";
    options.socket = "/run/mayon-clash/mihomo.sock";
    if (!help_anywhere) {
        if (!load_prefs(config_path, options.prefs, error)) return ParseResult::Error;
    }
    for (size_t i = 0; i < args.size(); ++i) {
        const std::string& arg = args[i];
        const auto value = [&](const char* missing) -> std::optional<std::string> {
            if (i + 1 >= args.size()) {
                error = missing;
                return std::nullopt;
            }
            return args[++i];
        };
        if (arg == "--data-dir") {
            const auto next = value("需要数据目录");
            if (!next) return ParseResult::Error;
            options.native.data = *next;
        } else if (arg == "--mihomo") {
            const auto next = value("需要 mihomo 路径");
            if (!next) return ParseResult::Error;
            options.native.mihomo = *next;
        } else if (arg == "--systemctl") {
            const auto next = value("需要 systemctl 路径");
            if (!next) return ParseResult::Error;
            options.native.systemctl = *next;
        } else if (arg == "--socket") {
            const auto next = value("--socket 需要路径");
            if (!next) return ParseResult::Error;
            options.socket = *next;
        } else if (arg == "--test-url") {
            const auto next = value("--test-url 需要 URL");
            if (!next) return ParseResult::Error;
            options.prefs.test_url = *next;
        } else if (arg == "--config") {
            const auto next = value("--config 需要路径");
            if (!next) return ParseResult::Error;
        } else if (arg == "--usage-proxy") {
            const auto next = value("--usage-proxy 需要 URL");
            if (!next) return ParseResult::Error;
            options.usage_proxy = *next;
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "clashtui-mayon " << kVersion
                      << "\n\n--data-dir PATH     Native private data directory\n--mihomo PATH       Validator executable (isolated fixtures)\n--systemctl PATH    Service command (isolated fixtures)\nprofile "
                         "add|update|use|rename|url|delete|list (see README)\nsettings KEY VALUE · service start|stop\n--socket PATH       Mihomo Unix socket (never TCP controller)\n--test-url URL      Delay probe "
                         "target\n--config PATH       Read optional preferences\n--usage-proxy URL   Explicit HTTP/SOCKS proxy for usage headers\n\n1 概览 · 2 代理 · 3 订阅 · 4 连接 · 5 规则 · 6 日志 · 7 工具 · s 启动 · X 关闭（确认） · ? 帮助\n";
            return ParseResult::Exit;
        } else if (arg == "--version") {
            std::cout << "clashtui-mayon " << kVersion << "\n";
            return ParseResult::Exit;
        } else {
            error = "未知参数，请用 --help 查看";
            return ParseResult::Error;
        }
    }
    options.native.socket = options.socket;
    if (const std::string invalid = options.prefs.validate(); !invalid.empty()) {
        error = invalid;
        return ParseResult::Error;
    }
    out = std::move(options);
    return ParseResult::Run;
}

namespace {
bool equal(const Snapshot& left, const Snapshot& right) { return left.proxies == right.proxies && left.config == right.config && left.version == right.version; }
bool all_zero(const std::map<std::string, uint64_t>& values) {
    return std::all_of(values.begin(), values.end(), [](const auto& item) { return item.second == 0; });
}
Res<> from_api(std::expected<void, ApiError> result) {
    if (result) return {};
    return std::unexpected(message(result.error()));
}
}  // namespace

App::App(Options options) : opts_(std::move(options)), client_{opts_.socket, nullptr} {
    page = static_cast<PageKind>(std::min<uint64_t>(opts_.prefs.default_page - 1, static_cast<uint64_t>(kPageCount - 1)));
    help_page = static_cast<size_t>(page);
    sort = opts_.prefs.default_sort == "delay" ? Sort::Delay : opts_.prefs.default_sort == "name" ? Sort::Name : Sort::Default;
    tone = Tone::Info;
    first_snapshot = false;
    last_refresh = std::chrono::steady_clock::now();
    last_resources = last_refresh - std::chrono::seconds(31);
    last_auto = last_refresh - std::chrono::seconds(61);
}
App::~App() {
    {
        const std::lock_guard lock(post_mutex);
        post_alive = false;
    }
    finish_native();
    suspend();
    join_all(false);
}
void App::attach(tui::Post post) {
    post_ = std::move(post);
    attached = true;
}
void App::set_active(bool value) {
    if (value) {
        start();
    } else {
        suspend();
    }
}
void App::start() {
    if (active_) {
        dirty = true;
        return;
    }
    {
        const std::lock_guard lock(post_mutex);
        post_alive = true;
        for (auto& done : deferred_native) pending.push_back(std::move(done));
        deferred_native.clear();
    }
    active_ = true;
    dirty = true;
    reload_profiles();
    refresh();
    if (traffic_stop) traffic_stop->stop();
    if (traffic_thread.joinable()) traffic_thread.join();
    traffic_stop = std::make_shared<Stop>();
    const auto traffic = traffic_stop;
    traffic_thread = std::thread([this, traffic] {
        while (!traffic->stopped()) {
            client_.stream_lines(
                "/traffic", *traffic, nullptr,
                [this](std::string_view line) {
                    try {
                        deliver(TrafficReady{parse_traffic(line)});
                    } catch (const std::exception&) {
                    }
                    return true;
                });
            if (traffic->stopped()) return;
            deliver(TrafficOffline{});
            traffic->wait_ms(2000);
        }
    });
    if (connections_stop) connections_stop->stop();
    if (connections_thread.joinable()) connections_thread.join();
    connections_stop = std::make_shared<Stop>();
    const auto connections_stop_copy = connections_stop;
    connections_thread = std::thread([this, connections_stop_copy] {
        while (!connections_stop_copy->stopped()) {
            client_.connection_stream(*connections_stop_copy, [this, connections_stop_copy](std::string_view text) {
                try {
                    deliver(ConnectionsReady{parse_connections(text)});
                } catch (const std::exception&) {
                }
                return !connections_stop_copy->stopped();
            });
            if (connections_stop_copy->stopped()) return;
            deliver(ConnectionsOffline{});
            connections_stop_copy->wait_ms(2000);
        }
    });
    if (page == PageKind::Logs) start_logs();
}
void App::suspend() {
    active_ = false;
    {
        const std::lock_guard lock(post_mutex);
        post_alive = false;
    }
    cancel_measure();
    cancel_and_join(refresh_thread, refresh_cancel, refresh_running);
    cancel_and_join(resources_thread, resources_cancel, resources_running);
    cancel_and_join(usage_thread, usage_cancel, usage_running);
    cancel_and_join(command_thread, command_cancel, command_running);
    if (traffic_stop) traffic_stop->stop();
    if (traffic_thread.joinable()) traffic_thread.join();
    traffic_stop.reset();
    if (connections_stop) connections_stop->stop();
    if (connections_thread.joinable()) connections_thread.join();
    connections_stop.reset();
    if (logs_stop) logs_stop->stop();
    if (logs_thread.joinable()) logs_thread.join();
    logs_stop.reset();
    logs_running = false;
    connections_live = false;
    logs_live = false;
}
void App::cancel_and_join(std::thread& worker, std::shared_ptr<std::atomic<bool>> token, bool& running) {
    if (token) token->store(true);
    if (worker.joinable()) worker.join();
    running = false;
}
void App::join_all(bool include_native) {
    cancel_and_join(refresh_thread, refresh_cancel, refresh_running);
    cancel_and_join(resources_thread, resources_cancel, resources_running);
    cancel_and_join(usage_thread, usage_cancel, usage_running);
    cancel_and_join(command_thread, command_cancel, command_running);
    if (traffic_stop) traffic_stop->stop();
    if (traffic_thread.joinable()) traffic_thread.join();
    if (connections_stop) connections_stop->stop();
    if (connections_thread.joinable()) connections_thread.join();
    if (logs_stop) logs_stop->stop();
    if (logs_thread.joinable()) logs_thread.join();
    if (delay_thread.joinable()) delay_thread.join();
    if (include_native && native_thread.joinable()) native_thread.join();
}
void App::deliver(Update update) {
    const std::lock_guard gate(post_mutex);
    if (!post_alive) return;
    if (!post_) {
        pending.push_back(std::move(update));
        dirty = true;
        return;
    }
    {
        const std::lock_guard lock(inbox_mutex);
        if (inbox.size() >= 1024) return;  // Bounded buffer: a runaway log stream cannot grow without limit.
        inbox.push_back(std::move(update));
    }
    if (!inbox_posted.exchange(true)) {
        post_([this] { drain_inbox(); });
    }
}
void App::drain_inbox() {
    inbox_posted.store(false);
    std::deque<Update> moved;
    {
        const std::lock_guard lock(inbox_mutex);
        moved.swap(inbox);
    }
    for (auto& update : moved) pending.push_back(std::move(update));
    dirty = true;
}
void App::deliver_native(NativeDone done) {
    const std::lock_guard gate(post_mutex);
    if (!post_alive) {
        // Keep the single native completion while the page is unfocused; start()
        // applies it when focus returns.
        deferred_native.push_back(std::move(done));
        return;
    }
    if (!post_) {
        pending.push_back(std::move(done));
        dirty = true;
        return;
    }
    post_([this, done = std::move(done)] {
        pending.push_back(done);
        dirty = true;
    });
}
void App::reload_profiles() {
    if (auto loaded = opts_.native.store()) {
        store = std::move(*loaded);
        profile = std::min(profile, store.items.empty() ? size_t{0} : store.items.size() - 1);
    } else {
        status = loaded.error();
    }
    if (auto loaded = opts_.native.settings()) {
        native_settings = std::move(*loaded);
    } else {
        status = loaded.error();
    }
}
void App::refresh() {
    if (refresh_running) return;
    if (refresh_thread.joinable()) refresh_thread.join();
    last_refresh = std::chrono::steady_clock::now();
    refresh_running = true;
    refresh_cancel = std::make_shared<std::atomic<bool>>(false);
    const auto token = refresh_cancel;
    refresh_thread = std::thread([this, token] {
        Client client{opts_.socket, token};
        SnapshotReady update;
        if (auto proxies = client.proxies()) {
            if (auto config = client.configs()) {
                if (auto version = client.version()) {
                    update.ok = true;
                    update.data = Snapshot{std::move(*proxies), std::move(*config), std::move(*version)};
                } else {
                    update.error = version.error();
                }
            } else {
                update.error = config.error();
            }
        } else {
            update.error = proxies.error();
        }
        if (token->load()) return;
        deliver(update);
    });
}
void App::refresh_resources() {
    if (resources_running) return;
    if (resources_thread.joinable()) resources_thread.join();
    last_resources = std::chrono::steady_clock::now();
    resources_running = true;
    resources_cancel = std::make_shared<std::atomic<bool>>(false);
    const auto token = resources_cancel;
    resources_thread = std::thread([this, token] {
        Client client{opts_.socket, token};
        ResourcesReady update;
        auto providers = client.providers(false);
        auto rules_providers = client.providers(true);
        auto rules = client.rules();
        if (providers && rules_providers && rules) {
            update.ok = true;
            update.data = Resources{std::move(*providers), std::move(*rules_providers), std::move(*rules)};
        } else if (!providers) {
            update.error = providers.error();
        } else if (!rules_providers) {
            update.error = rules_providers.error();
        } else {
            update.error = rules.error();
        }
        if (token->load()) return;
        deliver(update);
    });
}
void App::start_logs() {
    if (logs_running) return;
    if (logs_thread.joinable()) logs_thread.join();
    logs_running = true;
    logs_stop = std::make_shared<Stop>();
    const auto stop = logs_stop;
    logs_thread = std::thread([this, stop] {
        while (!stop->stopped()) {
            client_.stream_lines(
                "/logs?level=debug", *stop, [this] { deliver(LogsState{true}); },
                [this, stop](std::string_view line) {
                    try {
                        LogEntry entry = parse_log(line);
                        entry.payload = redact_log(entry.payload);
                        deliver(LogReady{std::move(entry)});
                    } catch (const std::exception&) {
                    }
                    return !stop->stopped();
                });
            if (stop->stopped()) return;
            deliver(LogsState{false});
            stop->wait_ms(2000);
        }
    });
}
void App::command(std::function<Res<>()> work) {
    if (command_running) {
        status = "操作正在进行，请稍候";
        return;
    }
    if (command_thread.joinable()) command_thread.join();
    status = "正在执行…";
    command_running = true;
    command_cancel = std::make_shared<std::atomic<bool>>(false);
    const auto token = command_cancel;
    command_thread = std::thread([this, token, work = std::move(work)] {
        Res<> result = work();
        if (token->load()) return;
        Message message;
        message.command_done = true;
        message.text = result ? "操作完成" : result.error();
        deliver(std::move(message));
    });
}
std::optional<std::string> App::group_name() const {
    if (group < group_names.size()) return group_names[group];
    return std::nullopt;
}
std::optional<std::string> App::current_node() const {
    const auto name = group_name();
    if (!name) return std::nullopt;
    const auto found = proxies.find(*name);
    if (found == proxies.end()) return std::nullopt;
    return found->second.now;
}
std::optional<std::optional<uint64_t>> App::delay(const std::string& node) const {
    if (const auto found = delays.find(node); found != delays.end()) return found->second;
    const auto proxy = proxies.find(node);
    if (proxy == proxies.end() || proxy->second.history.empty()) return std::nullopt;
    const auto& last = proxy->second.history.back();
    return last.delay > 0 ? std::optional<uint64_t>(last.delay) : std::optional<uint64_t>{};
}
void App::rebuild_nodes() {
    const std::optional<std::string> selected = node < node_names.size() ? std::optional<std::string>(node_names[node]) : std::nullopt;
    const Matcher matcher(filters[static_cast<size_t>(PageKind::Proxies)].str());
    std::vector<std::string> nodes;
    const auto name = group_name();
    if (name) {
        if (const auto found = proxies.find(*name); found != proxies.end()) {
            for (const std::string& candidate : found->second.all) {
                const auto known = delay(candidate);
                if (hide_timeout && known && !*known) continue;
                if (!matcher.matches(candidate)) continue;
                nodes.push_back(candidate);
            }
        }
    }
    if (sort == Sort::Name) {
        std::stable_sort(nodes.begin(), nodes.end(), [](const std::string& left, const std::string& right) {
            std::string a = left, b = right;
            std::transform(a.begin(), a.end(), a.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
            std::transform(b.begin(), b.end(), b.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
            return a < b;
        });
    } else if (sort == Sort::Delay) {
        std::stable_sort(nodes.begin(), nodes.end(), [this](const std::string& left, const std::string& right) {
            const auto key = [this](const std::string& name) {
                const auto value = delay(name);
                if (value && *value) return std::pair{0, **value};
                if (!value) return std::pair{1, uint64_t{0}};
                return std::pair{2, uint64_t{0}};
            };
            return key(left) < key(right);
        });
    }
    node_names = std::move(nodes);
    node = 0;
    if (selected) {
        if (const auto found = std::find(node_names.begin(), node_names.end(), *selected); found != node_names.end()) node = static_cast<size_t>(found - node_names.begin());
    }
}
void App::rebuild_views() {
    const std::optional<std::string> connection_id = selected_connection() ? std::optional<std::string>(selected_connection()->id) : std::nullopt;
    std::optional<std::tuple<std::string, std::string, std::string>> rule_key;
    if (const Rule* selected = selected_rule()) rule_key = std::tuple{selected->kind, selected->payload, selected->proxy};
    const std::optional<std::string> provider_name = provider < provider_view.size() ? std::optional<std::string>(provider_view[provider]) : std::nullopt;
    const Matcher matcher(filter_text());
    rebuild_nodes();
    const Matcher connection_matcher(filters[static_cast<size_t>(PageKind::Connections)].str());
    connection_view.clear();
    for (size_t i = 0; i < connections.size(); ++i) {
        const Connection& c = connections[i];
        std::string chains;
        for (const std::string& part : c.chains) {
            if (!chains.empty()) chains += ' ';
            chains += part;
        }
        const std::string text = c.metadata.host + " " + c.metadata.destination_ip + " " + c.rule + " " + c.rule_payload + " " + c.metadata.process + " " + chains;
        if (connection_matcher.matches(text)) connection_view.push_back(i);
    }
    std::stable_sort(connection_view.begin(), connection_view.end(), [this](size_t left, size_t right) {
        const Connection& a = connections[left];
        const Connection& b = connections[right];
        auto key = [this](const Connection& row) { return rates.contains(row.id) ? rates.at(row.id) : 0; };
        bool less = false;
        switch (connection_sort) {
            case 0: less = key(b) < key(a); break;
            case 1: less = (b.upload + b.download) < (a.upload + a.download); break;
            case 2: less = a.start < b.start; break;
            default: less = a.metadata.host < b.metadata.host; break;
        }
        if (less) return true;
        if (connection_sort == 0 ? key(a) < key(b) : connection_sort == 1 ? (a.upload + a.download) < (b.upload + b.download) : connection_sort == 2 ? b.start < a.start : b.metadata.host < a.metadata.host)
            return false;
        return a.id < b.id;
    });
    connection = 0;
    if (connection_id) {
        for (size_t i = 0; i < connection_view.size(); ++i) {
            if (connections[connection_view[i]].id == *connection_id) {
                connection = i;
                break;
            }
        }
    }
    const Matcher rule_matcher(filters[static_cast<size_t>(PageKind::Rules)].str());
    rule_view.clear();
    for (size_t i = 0; i < rules.size(); ++i) {
        const Rule& row = rules[i];
        if (rule_matcher.matches(row.kind + " " + row.payload + " " + row.proxy)) rule_view.push_back(i);
    }
    rule = 0;
    if (rule_key) {
        for (size_t i = 0; i < rule_view.size(); ++i) {
            const Rule& row = rules[rule_view[i]];
            if (std::tuple{row.kind, row.payload, row.proxy} == *rule_key) {
                rule = i;
                break;
            }
        }
    }
    const auto& map = page == PageKind::Rules ? rule_providers : providers;
    provider_view.clear();
    for (const auto& [name, value] : map) {
        (void)value;
        if (matcher.matches(name)) provider_view.push_back(name);
    }
    provider = 0;
    if (provider_name) {
        if (const auto found = std::find(provider_view.begin(), provider_view.end(), *provider_name); found != provider_view.end()) provider = static_cast<size_t>(found - provider_view.begin());
    }
    rebuild_logs();
}
void App::rebuild_logs() {
    std::optional<uint64_t> selected;
    if (log < log_view.size() && log_view[log] < logs.size()) selected = logs[log_view[log]].id;
    const Matcher matcher(filters[static_cast<size_t>(PageKind::Logs)].str());
    log_view.clear();
    for (size_t i = 0; i < logs.size(); ++i) {
        const LogEntry& entry = logs[i];
        const int level = entry.level == "debug" ? 0 : entry.level == "info" ? 1 : (entry.level == "warning" || entry.level == "warn") ? 2 : entry.level == "error" ? 3 : 1;
        if (static_cast<size_t>(level) >= log_level && matcher.matches(entry.payload)) log_view.push_back(i);
    }
    log = 0;
    if (selected) {
        for (size_t i = 0; i < log_view.size(); ++i) {
            if (logs[log_view[i]].id == *selected) {
                log = i;
                break;
            }
        }
    }
}
std::string App::proxy_chain(const std::string& start) const {
    std::vector<std::string> chain{start};
    for (int i = 0; i < 16; ++i) {
        const std::string& last = chain.back();
        const auto found = proxies.find(last);
        if (found == proxies.end() || !found->second.now) break;
        const std::string next = *found->second.now;
        if (std::find(chain.begin(), chain.end(), next) != chain.end()) {
            chain.push_back("循环链路");
            break;
        }
        chain.push_back(next);
    }
    std::string out;
    for (const std::string& part : chain) {
        if (!out.empty()) out += " → ";
        out += part;
    }
    return out;
}
std::string App::chain() const {
    if (config.mode == "direct") return "DIRECT · 直连模式";
    if (config.mode == "global") return proxy_chain("GLOBAL");
    return "规则模式：按目标选择链路 · 4 连接查看实际出口";
}
const Connection* App::selected_connection() const {
    if (connection < connection_view.size() && connection_view[connection] < connections.size()) return &connections[connection_view[connection]];
    return nullptr;
}
const Rule* App::selected_rule() const {
    if (rule < rule_view.size() && rule_view[rule] < rules.size()) return &rules[rule_view[rule]];
    return nullptr;
}
std::string App::launch_progress() const {
    if (lifecycle_pending) {
        if (!lifecycle_pending->first) return "正在停止服务 → 等待 socket 与 TUN 清理…";
        std::error_code code;
        if (std::filesystem::exists(opts_.socket, code)) return "服务 activating → socket 已出现 → 等待 API 就绪…";
        return "正在生成配置 → 服务 activating → 等待 socket…";
    }
    if (native_error) return *native_error;
    if (store.items.empty()) return "尚无订阅 · 3 → i 添加";
    return "服务未运行 · s 手动启动 · 当前网络直连";
}
std::string App::profile_name(size_t index) const {
    if (index < store.items.size()) return store.items[index].name;
    return "未命名订阅";
}
void App::sync_notice() {
    if (status == noticed_status) return;
    noticed_status = status;
    if (contains(status, "失败") || contains(status, "无效") || contains(status, "不可用") || contains(status, "超时")) tone = Tone::Error;
    else if (contains(status, "完成") || contains(status, "就绪") || contains(status, "已连接")) tone = Tone::Success;
    else if (contains(status, "请") || contains(status, "未运行")) tone = Tone::Warning;
    else tone = Tone::Action;
    notice_text = status;
    notice_tone = tone;
    notice_until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    dirty = true;
}
std::optional<tui::TimePoint> App::next_deadline() const {
    if (!active_) return std::nullopt;
    std::vector<tui::TimePoint> deadlines;
    if (!refresh_running) deadlines.push_back(last_refresh + std::chrono::seconds(2));
    if (online && !resources_running) deadlines.push_back(last_resources + std::chrono::seconds(30));
    if (online && !native_busy) deadlines.push_back(last_auto + std::chrono::seconds(60));
    if (lifecycle_pending) deadlines.push_back(lifecycle_pending->second + std::chrono::seconds(120));
    if (lifecycle_pending || (page == PageKind::Connections && !connection_view.empty())) deadlines.push_back(last_clock + std::chrono::seconds(1));
    if (notice_until) deadlines.push_back(*notice_until);
    if (deadlines.empty()) return std::nullopt;
    return *std::min_element(deadlines.begin(), deadlines.end());
}
void App::tick() {
    const bool follow_logs = log + 1 >= log_view.size();
    bool logs_changed = false;
    const std::optional<uint64_t> log_identity = log < log_view.size() && log_view[log] < logs.size() ? std::optional<uint64_t>(logs[log_view[log]].id) : std::nullopt;
    for (size_t processed = 0; processed < 128 && !pending.empty(); ++processed) {
        Update update = std::move(pending.front());
        pending.pop_front();
        if (auto* snapshot = std::get_if<SnapshotReady>(&update)) {
            if (snapshot->ok && online && !lifecycle_pending && equal(snapshot->data, Snapshot{proxies, config, version})) {
                refresh_running = false;
                continue;
            }
            if (!snapshot->ok && !online && !lifecycle_pending && last_api_error && *last_api_error == message(snapshot->error)) {
                refresh_running = false;
                continue;
            }
        } else if (auto* resources = std::get_if<ResourcesReady>(&update)) {
            if (resources->ok && providers == resources->data.providers && rule_providers == resources->data.rule_providers && rules == resources->data.rules) {
                resources_running = false;
                continue;
            }
        } else if (auto* value = std::get_if<ConnectionsReady>(&update)) {
            if (connections_live && connections == value->value.connections && memory == value->value.memory &&
                totals == std::pair{value->value.upload_total, value->value.download_total} && all_zero(rates)) continue;
        } else if (std::holds_alternative<ConnectionsOffline>(update)) {
            if (!connections_live && rates.empty()) continue;
        } else if (std::holds_alternative<TrafficOffline>(update)) {
            if (!traffic && history.empty()) continue;
        } else if (auto* state = std::get_if<LogsState>(&update)) {
            if (logs_live == state->on) continue;
        }
        dirty = true;
        if (auto* snapshot = std::get_if<SnapshotReady>(&update)) {
            if (snapshot->ok) {
                first_snapshot = true;
                last_api_error.reset();
                if (!online) status = "内核已连接 · ? 查看上手指引";
                online = true;
                if (lifecycle_pending && lifecycle_pending->first) {
                    if (snapshot->data.config.tun != native_settings.tun || snapshot->data.config.mixed_port != std::optional<uint16_t>(native_settings.mixed_port)) {
                        status = "API 已连接 → 等待 TUN / 监听端口就绪…";
                    } else {
                        lifecycle_pending.reset();
                        status = "Clash 已就绪";
                    }
                }
                const std::optional<std::string> old_group = group_name();
                const std::optional<std::string> old_node = node < node_names.size() ? std::optional<std::string>(node_names[node]) : std::nullopt;
                proxies = std::move(snapshot->data.proxies);
                config = std::move(snapshot->data.config);
                version = std::move(snapshot->data.version);
                group_names.clear();
                for (const auto& [name, value] : proxies) {
                    if (!value.all.empty()) group_names.push_back(name);
                }
                if (const auto global = proxies.find("GLOBAL"); global != proxies.end()) {
                    std::stable_sort(group_names.begin(), group_names.end(), [&](const std::string& left, const std::string& right) {
                        const auto rank = [&](const std::string& name) -> size_t {
                            if (name == "GLOBAL") return 0;
                            const auto found = std::find(global->second.all.begin(), global->second.all.end(), name);
                            return found == global->second.all.end() ? std::numeric_limits<size_t>::max() : static_cast<size_t>(found - global->second.all.begin()) + 1;
                        };
                        return rank(left) < rank(right);
                    });
                }
                group = 0;
                if (old_group) {
                    const auto found = std::find(group_names.begin(), group_names.end(), *old_group);
                    if (found != group_names.end()) group = static_cast<size_t>(found - group_names.begin());
                }
                if (!old_group) {
                    const auto found = std::find_if(group_names.begin(), group_names.end(), [](const std::string& name) { return name != "GLOBAL"; });
                    group = found == group_names.end() ? 0 : static_cast<size_t>(found - group_names.begin());
                }
                if (!group_names.empty()) group = std::min(group, group_names.size() - 1);
                else group = 0;
                rebuild_views();
                if (old_node) {
                    const auto found = std::find(node_names.begin(), node_names.end(), *old_node);
                    if (found != node_names.end()) node = static_cast<size_t>(found - node_names.begin());
                }
                refresh_running = false;
            } else {
                first_snapshot = true;
                last_api_error = message(snapshot->error);
                const bool was_online = online;
                online = false;
                traffic.reset();
                connections_live = false;
                if (native_busy || native_error) {
                    if (!native_busy) status = native_error.value_or("");
                } else if (was_online || lifecycle_pending || status == "正在连接内核…") {
                    if (lifecycle_pending) status = launch_progress();
                    else if (snapshot->error == ApiError::Transport) status = "Clash 未运行 · s 启动";
                    else status = message(snapshot->error);
                }
                if (lifecycle_pending && !lifecycle_pending->first) {
                    std::error_code code;
                    if (!std::filesystem::exists(opts_.socket, code)) {
                        lifecycle_pending.reset();
                        status = "Clash 已关闭 · s 启动";
                    }
                }
                refresh_running = false;
            }
        } else if (auto* resources = std::get_if<ResourcesReady>(&update)) {
            if (resources->ok) {
                std::optional<std::tuple<std::string, std::string, std::string>> selected;
                if (const Rule* row = selected_rule()) selected = std::tuple{row->kind, row->payload, row->proxy};
                providers = std::move(resources->data.providers);
                rule_providers = std::move(resources->data.rule_providers);
                rules = std::move(resources->data.rules);
                rebuild_views();
                rule = 0;
                if (selected) {
                    for (size_t i = 0; i < rule_view.size(); ++i) {
                        const Rule& row = rules[rule_view[i]];
                        if (std::tuple{row.kind, row.payload, row.proxy} == *selected) {
                            rule = i;
                            break;
                        }
                    }
                }
            } else {
                status = std::string("规则/provider 刷新失败：") + message(resources->error);
            }
            resources_running = false;
        } else if (auto* value = std::get_if<ConnectionsReady>(&update)) {
            const std::optional<std::string> selected = selected_connection() ? std::optional<std::string>(selected_connection()->id) : std::nullopt;
            const double elapsed = std::max(std::chrono::duration<double>(std::chrono::steady_clock::now() - connection_time).count(), 0.001);
            connection_time = std::chrono::steady_clock::now();
            rates.clear();
            for (const Connection& c : value->value.connections) {
                const uint64_t total = c.upload + c.download;
                if (const auto old = previous_connections.find(c.id); old != previous_connections.end()) {
                    const double speed = static_cast<double>(total > old->second ? total - old->second : 0) / elapsed;
                    rates[c.id] = static_cast<uint64_t>(speed);
                }
            }
            previous_connections.clear();
            for (const Connection& c : value->value.connections) previous_connections[c.id] = c.upload + c.download;
            connections = std::move(value->value.connections);
            memory = value->value.memory;
            totals = {value->value.upload_total, value->value.download_total};
            connections_live = true;
            rebuild_views();
            connection = 0;
            if (selected) {
                for (size_t i = 0; i < connection_view.size(); ++i) {
                    if (connections[connection_view[i]].id == *selected) {
                        connection = i;
                        break;
                    }
                }
            }
        } else if (std::holds_alternative<ConnectionsOffline>(update)) {
            connections_live = false;
            previous_connections.clear();
            rates.clear();
        } else if (auto* value = std::get_if<TrafficReady>(&update)) {
            totals = {value->value.up_total, value->value.down_total};
            if (history.size() == 60) history.pop_front();
            history.emplace_back(value->value.up, value->value.down);
            traffic = value->value;
        } else if (std::holds_alternative<TrafficOffline>(update)) {
            traffic.reset();
            history.clear();
        } else if (auto* entry = std::get_if<LogReady>(&update)) {
            if (!logs_paused) {
                entry->value.id = next_log_id++;
                log_bytes += entry->value.payload.size() + entry->value.level.size();
                logs.push_back(std::move(entry->value));
                while (logs.size() > 2000 || log_bytes > 4 * 1024 * 1024) {
                    if (logs.empty()) break;
                    const LogEntry& line = logs.front();
                    log_bytes -= std::min(log_bytes, line.payload.size() + line.level.size());
                    logs.pop_front();
                    log = log > 0 ? log - 1 : 0;
                }
                logs_changed = true;
            }
        } else if (auto* state = std::get_if<LogsState>(&update)) {
            logs_live = state->on;
        } else if (auto* message_update = std::get_if<Message>(&update)) {
            status = message_update->text;
            if (message_update->command_done) command_running = false;
            last_refresh = std::chrono::steady_clock::now() - std::chrono::seconds(3);
            last_resources = std::chrono::steady_clock::now() - std::chrono::seconds(31);
        } else if (auto* delayUpdate = std::get_if<DelayReady>(&update)) {
            if (delayUpdate->generation == generation) {
                const std::optional<std::string> selected = node < node_names.size() ? std::optional<std::string>(node_names[node]) : std::nullopt;
                delays[delayUpdate->name] = delayUpdate->delay && *delayUpdate->delay > 0 ? delayUpdate->delay : std::nullopt;
                if (measuring) measuring->first += 1;
                rebuild_nodes();
                if (selected) {
                    const auto found = std::find(node_names.begin(), node_names.end(), *selected);
                    if (found != node_names.end()) node = static_cast<size_t>(found - node_names.begin());
                }
            }
        } else if (auto* done = std::get_if<DelayDone>(&update)) {
            if (done->generation == generation) {
                measuring.reset();
                delay_running = false;
                if (!contains(status, "失败")) status = "测速完成 · 延迟仅代表此测试目标";
            }
        } else if (auto* usageUpdate = std::get_if<UsageReady>(&update)) {
            usage_running = false;
            if (usageUpdate->ok) {
                usage[usageUpdate->uid] = usageUpdate->usage;
                status = "用量已刷新（仅内存）";
            } else {
                status = usageUpdate->error;
            }
        } else if (auto* done = std::get_if<NativeDone>(&update)) {
            native_busy = false;
            if (done->ok) {
                native_error.reset();
                status = done->message;
            } else {
                native_error = done->message;
                status = done->message;
                lifecycle_pending.reset();
            }
            reload_profiles();
            last_refresh = std::chrono::steady_clock::now() - std::chrono::seconds(3);
            last_resources = std::chrono::steady_clock::now() - std::chrono::seconds(31);
            if (queued_stop) {
                queued_stop = false;
                native_command(NativeAction{NativeKind::Stop, {}, {}, std::nullopt, {}});
            }
        }
    }
    if (logs_changed) {
        rebuild_logs();
        if (follow_logs) {
            log = log_view.empty() ? 0 : log_view.size() - 1;
        } else if (log_identity) {
            log = 0;
            for (size_t i = 0; i < log_view.size(); ++i) {
                if (logs[log_view[i]].id == *log_identity) {
                    log = i;
                    break;
                }
            }
        }
    }
    sync_notice();
    if (notice_until && *notice_until <= std::chrono::steady_clock::now()) {
        notice_text.clear();
        notice_until.reset();
        dirty = true;
    }
    if (!active_) return;
    const auto now = std::chrono::steady_clock::now();
    if ((lifecycle_pending || (page == PageKind::Connections && !connection_view.empty())) && now - last_clock >= std::chrono::seconds(1)) {
        last_clock = now;
        dirty = true;
    }
    if (lifecycle_pending && now - lifecycle_pending->second > std::chrono::seconds(120)) {
        status = "启动/关闭等待超时：" + launch_progress() + "；请检查服务状态";
        lifecycle_pending.reset();
        dirty = true;
        if (!native_busy) native_command(NativeAction{NativeKind::Diagnose, {}, {}, std::nullopt, {}});
    }
    if (online && !native_busy && now - last_auto >= std::chrono::seconds(60)) {
        last_auto = now;
        const auto due = store.due();
        if (!due.empty()) native_command(NativeAction{NativeKind::UpdateMany, {}, {}, std::nullopt, due});
    }
    if (now - last_refresh >= std::chrono::seconds(2)) {
        reload_profiles();
        refresh();
    }
    if (online && now - last_resources >= std::chrono::seconds(30)) refresh_resources();
}

// ---- Mutations from keys -----------------------------------------------------------------------
void App::move_selection(int delta, bool edge) {
    size_t* index = nullptr;
    size_t length = 0;
    if (provider_mode && (page == PageKind::Proxies || page == PageKind::Rules)) {
        index = &provider;
        length = provider_view.size();
    } else {
        switch (page) {
            case PageKind::Proxies:
                if (!nodes_focus) {
                    node = 0;
                    index = &group;
                    length = group_names.size();
                } else {
                    index = &node;
                    length = node_names.size();
                }
                break;
            case PageKind::Profiles:
                index = &profile;
                length = store.items.size();
                break;
            case PageKind::Connections:
                index = &connection;
                length = connection_view.size();
                break;
            case PageKind::Rules:
                index = &rule;
                length = rule_view.size();
                break;
            case PageKind::Logs:
                index = &log;
                length = log_view.size();
                break;
            case PageKind::Tools:
                index = &tool;
                length = 9;
                break;
            case PageKind::Overview:
                return;
        }
    }
    if (!index) return;
    if (edge) {
        *index = delta > 0 ? (length > 0 ? length - 1 : 0) : 0;
    } else {
        const long long target = static_cast<long long>(*index) + delta;
        *index = target < 0 ? 0 : std::min(static_cast<size_t>(target), length > 0 ? length - 1 : 0);
    }
    if (page == PageKind::Proxies && !nodes_focus) rebuild_nodes();
}
void App::cancel_measure() {
    if (delay_cancel) delay_cancel->store(true);
    if (delay_thread.joinable() && delay_thread.get_id() != std::this_thread::get_id()) delay_thread.join();
    ++generation;
    measuring.reset();
    delay_running = false;
}
void App::measure(size_t kind) {
    cancel_measure();
    std::vector<std::string> nodes;
    if (kind == 0) {
        if (node < node_names.size()) nodes.push_back(node_names[node]);
    } else if (kind == 1) {
        if (const auto name = group_name()) {
            if (const auto found = proxies.find(*name); found != proxies.end()) nodes = found->second.all;
        }
    } else {
        nodes = node_names;
    }
    if (nodes.empty()) return;
    const std::string group = group_name().value_or("");
    const uint64_t generation_value = generation;
    const auto client = client_;
    const std::string url = opts_.prefs.test_url;
    const uint64_t timeout = opts_.prefs.timeout_ms;
    const size_t concurrency = std::max<uint64_t>(1, std::min<uint64_t>(opts_.prefs.concurrency, 32));
    measuring = std::pair<size_t, size_t>{0, nodes.size()};
    status = kind == 1 ? "整组测速中（并发由内核管理；自动组可能重选出口）" : "测速中 · 最多 " + std::to_string(concurrency) + " 并发 · Esc 取消本地队列";
    delay_running = true;
    delay_cancel = std::make_shared<std::atomic<bool>>(false);
    const auto token = delay_cancel;
    delay_thread = std::thread([this, kind, nodes = std::move(nodes), group, generation_value, client, url, timeout, concurrency, token] {
        Client worker{client.socket, token};
        if (kind == 1) {
            if (auto result = worker.group_delay(group, url, timeout)) {
                for (const std::string& name : nodes) {
                    if (token->load()) return;
                    std::optional<uint64_t> value;
                    if (const auto found = result->find(name); found != result->end()) value = found->second;
                    deliver(DelayReady{generation_value, name, value});
                }
            } else {
                if (token->load()) return;
                deliver(Message{std::string("整组测速失败：") + message(result.error()), false});
            }
        } else {
            std::atomic<size_t> next{0};
            std::vector<std::thread> workers;
            const size_t count = std::min(concurrency, nodes.size());
            for (size_t i = 0; i < count; ++i) {
                workers.emplace_back([&] {
                    while (!token->load()) {
                        const size_t index = next.fetch_add(1);
                        if (index >= nodes.size()) return;
                        auto delay = worker.delay(nodes[index], url, timeout);
                        if (token->load()) return;
                        deliver(DelayReady{generation_value, nodes[index], delay ? std::optional<uint64_t>(*delay) : std::nullopt});
                    }
                });
            }
            for (auto& thread : workers) thread.join();
        }
        if (token->load()) return;
        deliver(DelayDone{generation_value});
    });
}
void App::refresh_usage() {
    if (usage_running) {
        status = "用量请求正在进行";
        return;
    }
    if (profile >= store.items.size()) return;
    const Subscription& item = store.items[profile];
    if (item.url.empty()) {
        status = "本地订阅没有远程用量";
        return;
    }
    const std::string uid = item.id;
    std::optional<std::string> proxy = opts_.usage_proxy;
    if (!proxy && config.mixed_port && *config.mixed_port > 0) proxy = "http://127.0.0.1:" + std::to_string(*config.mixed_port);
    if (!proxy) {
        status = "没有代理端口；可用 --usage-proxy 指定";
        return;
    }
    if (usage_thread.joinable()) usage_thread.join();
    status = "正在经代理读取用量响应头…";
    usage_running = true;
    usage_cancel = std::make_shared<std::atomic<bool>>(false);
    const auto token = usage_cancel;
    usage_thread = std::thread([this, token, url = item.url, proxy = *proxy, uid] {
        auto result = usage_request(url, proxy);
        if (token->load()) return;
        UsageReady update;
        update.uid = uid;
        if (result) {
            update.ok = true;
            update.usage = *result;
        } else {
            update.error = result.error();
        }
        deliver(std::move(update));
    });
}
void App::edit_setting() {
    std::string key;
    std::string value;
    switch (tool) {
        case 3: key = "tun"; value = native_settings.tun ? "false" : "true"; break;
        case 4: key = "mode"; value = native_settings.mode == "rule" ? "global" : native_settings.mode == "global" ? "direct" : "rule"; break;
        case 5: key = "ipv6"; value = native_settings.ipv6 ? "false" : "true"; break;
        case 6: key = "allow-lan"; value = native_settings.allow_lan ? "false" : "true"; break;
        case 7:
            key = "log-level";
            value = native_settings.log_level == "info" ? "debug" : native_settings.log_level == "debug" ? "warning" : native_settings.log_level == "warning" ? "error" : native_settings.log_level == "error" ? "silent" : "info";
            break;
        default: {
            Dialog edit;
            edit.kind = Dialog::Kind::Edit;
            edit.title = "Mixed port · 1–65535";
            edit.value.set(std::to_string(native_settings.mixed_port));
            edit.edit = EditAction{EditKind::Setting, "mixed-port"};
            dialog = std::move(edit);
            return;
        }
    }
    native_command(NativeAction{NativeKind::Change, key, value, std::nullopt, {}});
}
void App::confirm(ConfirmAction action, std::string body) {
    Dialog value;
    value.kind = Dialog::Kind::Confirm;
    value.action = std::move(action);
    value.body = std::move(body);
    dialog = std::move(value);
}
void App::execute(ConfirmAction action) {
    switch (action.kind) {
        case ConfirmAction::Kind::DeleteProfile: native_command(NativeAction{NativeKind::Delete, action.id, {}, std::nullopt, {}}); break;
        case ConfirmAction::Kind::Stop: native_command(NativeAction{NativeKind::Stop, {}, {}, std::nullopt, {}}); break;
        case ConfirmAction::Kind::Close: {
            const auto ids = action.ids;
            const auto socket = opts_.socket;
            command([socket, ids] {
                Client client{socket, nullptr};
                for (const std::string& id : ids) {
                    if (auto closed = client.close(id); !closed) return from_api(closed);
                }
                return Res<>{};
            });
            break;
        }
        case ConfirmAction::Kind::CloseAll: {
            const auto socket = opts_.socket;
            command([socket] {
                Client client{socket, nullptr};
                return from_api(client.close_all());
            });
            break;
        }
        case ConfirmAction::Kind::Tool: {
            const auto socket = opts_.socket;
            const size_t index = action.tool;
            command([socket, index] {
                Client client{socket, nullptr};
                return from_api(client.tool(index));
            });
            break;
        }
    }
}
void App::native_command(NativeAction action) {
    if (native_busy) {
        if (action.kind == NativeKind::Stop) {
            queued_stop = true;
            lifecycle_pending = std::pair{false, std::chrono::steady_clock::now()};
            status = "已接受关闭请求 · 等待当前写入完成后停止服务…";
        } else {
            status = "订阅/服务操作正在进行，请稍候";
        }
        return;
    }
    native_busy = true;
    native_error.reset();
    switch (action.kind) {
        case NativeKind::Start: status = "正在校验配置并启动服务…"; break;
        case NativeKind::Stop: status = "正在关闭服务…"; break;
        case NativeKind::Add: status = "正在下载并校验订阅…"; break;
        case NativeKind::Update:
        case NativeKind::UpdateMany: status = "正在更新订阅：直连失败时经本地代理重试…"; break;
        default: status = "正在保存并应用…"; break;
    }
    if (action.kind == NativeKind::Start || action.kind == NativeKind::Stop) lifecycle_pending = std::pair{action.kind == NativeKind::Start, std::chrono::steady_clock::now()};
    const bool running = online;
    const Native native = opts_.native;
    if (native_thread.joinable()) native_thread.join();
    native_thread = std::thread([this, action = std::move(action), running, native] {
        Res<> result;
        std::string message_text;
        switch (action.kind) {
            case NativeKind::Add: result = native.add(action.first, action.second, running); break;
            case NativeKind::Update: result = native.update(action.first, running, action.url); break;
            case NativeKind::Use: result = native.select(action.first, running); break;
            case NativeKind::Rename: result = native.rename(action.first, action.second); break;
            case NativeKind::Delete: result = native.remove(action.first); break;
            case NativeKind::Change: result = native.change(action.first, action.second, running); break;
            case NativeKind::Diagnose:
                message_text = native.failure();
                result = std::unexpected(message_text);
                break;
            case NativeKind::Start:
                result = native.generate();
                if (result) {
                    result = native.service("start");
                    if (result) message_text = "服务已启动 → 等待 API 就绪";
                }
                break;
            case NativeKind::Stop:
                result = native.service("stop");
                if (result) message_text = "服务已停止 → 等待 socket 消失";
                break;
            case NativeKind::UpdateMany: {
                size_t failed = 0;
                const size_t count = action.ids.size();
                for (const std::string& id : action.ids) {
                    if (!native.update(id, running, std::nullopt)) ++failed;
                }
                if (failed == 0) {
                    message_text = "已更新 " + std::to_string(count) + " 个订阅";
                } else {
                    result = std::unexpected("更新完成：" + std::to_string(count) + " 个中 " + std::to_string(failed) + " 个失败，失败项保留原缓存");
                }
                break;
            }
        }
        if (result && message_text.empty()) message_text = "操作完成 · 已保存，下次启动继续使用";
        NativeDone done;
        done.ok = static_cast<bool>(result);
        done.message = result ? message_text : result.error();
        deliver_native(std::move(done));
    });
}
void App::finish_native() {
    if (native_thread.joinable()) native_thread.join();
    if (queued_stop) {
        queued_stop = false;
        opts_.native.service("stop");
    }
}

// ---- Input -------------------------------------------------------------------------------------
void App::paste_text(const std::string& value) {
    tui::TextInput* target = nullptr;
    if (dialog) {
        if (dialog->kind == Dialog::Kind::Import) target = dialog->field ? &dialog->name : &dialog->url;
        else if (dialog->kind == Dialog::Kind::Edit) target = &dialog->value;
    } else if (filtering) {
        target = &filters[static_cast<size_t>(page)];
    }
    if (!target) return;
    const std::string before = target->str();
    target->paste(value);
    if (target->str() != before) {
        dirty = true;
        rebuild_views();
    }
}
bool App::handle(const tui::InputEvent& event) {
    switch (event.type) {
        case tui::InputEvent::Type::Key: key(event.key); break;
        case tui::InputEvent::Type::Paste: paste_text(event.paste); break;
        case tui::InputEvent::Type::MouseClick:
        case tui::InputEvent::Type::WheelUp:
        case tui::InputEvent::Type::WheelDown: handle_mouse(event); break;
        case tui::InputEvent::Type::FocusIn:
        case tui::InputEvent::Type::FocusOut: break;
    }
    // main.rs awaits the native task before tearing down the terminal.
    if (quit) finish_native();
    return quit;
}
void App::key(const tui::Key& event) {
    dirty = true;
    if (event.ctrl && event.ch == U'c') {
        quit = true;
        return;
    }
    if (dialog) {
        Dialog current = std::move(*dialog);
        dialog.reset();
        if (current.kind == Dialog::Kind::Edit) {
            if (event.code == tui::KeyCode::Escape) return;
            if (event.code == tui::KeyCode::Enter) {
                NativeAction action;
                if (current.edit.kind == EditKind::Rename) action = NativeAction{NativeKind::Rename, current.edit.id, current.value.str(), std::nullopt, {}};
                else if (current.edit.kind == EditKind::Url) action = NativeAction{NativeKind::Update, current.edit.id, {}, current.value.str(), {}};
                else action = NativeAction{NativeKind::Change, current.edit.id, current.value.str(), std::nullopt, {}};
                native_command(std::move(action));
                return;
            }
            current.value.handle(event);
        } else if (current.kind == Dialog::Kind::Confirm) {
            if (event.code == tui::KeyCode::Enter || event.is(U'y')) {
                execute(current.action);
                return;
            }
            if (event.code == tui::KeyCode::Escape || event.is(U'n')) return;
        } else if (current.kind == Dialog::Kind::Import) {
            if (event.code == tui::KeyCode::Escape) return;
            if (event.code == tui::KeyCode::Tab || event.code == tui::KeyCode::BackTab) current.field = !current.field;
            else if (event.code == tui::KeyCode::Enter) {
                if (parse_url(current.url.str())) {
                    native_command(NativeAction{NativeKind::Add, current.url.str(), current.name.str(), std::nullopt, {}});
                    return;
                }
                status = "请输入有效 http(s) 订阅 URL（内容隐藏）";
            } else if (current.field) {
                current.name.handle(event);
            } else {
                current.url.handle(event);
            }
        } else if (current.kind == Dialog::Kind::Detail) {
            if (event.code == tui::KeyCode::Escape || event.code == tui::KeyCode::Enter || event.is(U'q')) return;
            const long long lines = static_cast<long long>(std::count(current.text.begin(), current.text.end(), '\n')) + 1;
            if (event.code == tui::KeyCode::Down || event.is(U'j')) detail_scroll = static_cast<int>(std::min<long long>(detail_scroll + 1, std::max<long long>(lines - 1, 0)));
            else if (event.code == tui::KeyCode::Up || event.is(U'k')) detail_scroll = std::max(detail_scroll - 1, 0);
            else if (event.code == tui::KeyCode::PageDown) detail_scroll = static_cast<int>(std::min<long long>(detail_scroll + 10, std::max<long long>(lines - 1, 0)));
            else if (event.code == tui::KeyCode::PageUp) detail_scroll = std::max(detail_scroll - 10, 0);
            else if (event.is(U'g')) detail_scroll = 0;
        }
        dialog = std::move(current);
        return;
    }
    if (help) {
        if (event.code == tui::KeyCode::Escape || event.is(U'?') || event.is(U'q')) help = false;
        else if (event.code == tui::KeyCode::Tab || event.code == tui::KeyCode::Right || event.is(U'l')) help_page = (help_page + 1) % kPageCount;
        else if (event.code == tui::KeyCode::Left || event.is(U'h')) help_page = (help_page + kPageCount - 1) % kPageCount;
        else if (event.code == tui::KeyCode::Char && event.ch >= U'1' && event.ch <= U'7') help_page = static_cast<size_t>(event.ch - U'1');
        return;
    }
    if (filtering) {
        if (event.code == tui::KeyCode::Escape) {
            filtering = false;
            filters[static_cast<size_t>(page)] = filter_before;
            rebuild_views();
        } else if (event.code == tui::KeyCode::Enter) {
            filtering = false;
        } else if (event.code == tui::KeyCode::Down) {
            move_selection(1, false);
        } else if (event.code == tui::KeyCode::Up) {
            move_selection(-1, false);
        } else if (event.code == tui::KeyCode::PageDown) {
            move_selection(10, false);
        } else if (event.code == tui::KeyCode::PageUp) {
            move_selection(-10, false);
        } else if (filters[static_cast<size_t>(page)].handle(event)) {
            rebuild_views();
        }
        return;
    }
    if (event.ctrl || event.alt) return;
    if (event.is(U'q')) {
        quit = true;
    } else if (event.is(U'?')) {
        help = true;
        help_page = static_cast<size_t>(page);
    } else if (event.code == tui::KeyCode::Char && event.ch >= U'1' && event.ch <= U'7') {
        page = static_cast<PageKind>(static_cast<size_t>(event.ch - U'1'));
        provider_mode = false;
        rebuild_views();
        if (page == PageKind::Logs) start_logs();
        reload_profiles();
    } else if (event.is(U's') && !online && !lifecycle_pending) {
        if (!store.current) {
            page = PageKind::Profiles;
            status = "请先 i 添加订阅";
        } else {
            native_command(NativeAction{NativeKind::Start, {}, {}, std::nullopt, {}});
        }
    } else if (event.is(U'X') && online && (!lifecycle_pending || lifecycle_pending->first)) {
        confirm(ConfirmAction{ConfirmAction::Kind::Stop, {}, 0, {}}, "停止 mayon-clash 服务并移除 TUN；之后网络直连。");
    } else if (event.is(U'r')) {
        reload_profiles();
        refresh();
        last_resources = std::chrono::steady_clock::now() - std::chrono::seconds(31);
    } else if (event.is(U'i') && (page == PageKind::Profiles || (!online && page == PageKind::Overview))) {
        Dialog import;
        import.kind = Dialog::Kind::Import;
        dialog = std::move(import);
    } else if (event.is(U'o')) {
        page = PageKind::Tools;
        tool = 3;
    } else if (!online && page != PageKind::Profiles && page != PageKind::Tools) {
        // Offline: only the global keys above act.
    } else if (event.is(U'/') && (page == PageKind::Proxies || page == PageKind::Connections || page == PageKind::Rules || page == PageKind::Logs)) {
        filter_before = filters[static_cast<size_t>(page)];
        filtering = true;
        if (page == PageKind::Proxies) nodes_focus = true;
    } else if (event.code == tui::KeyCode::Escape) {
        cancel_measure();
        filters[static_cast<size_t>(page)].clear();
        rebuild_views();
    } else if (event.is(U'j') || event.code == tui::KeyCode::Down) {
        move_selection(1, false);
    } else if (event.is(U'k') || event.code == tui::KeyCode::Up) {
        move_selection(-1, false);
    } else if (event.code == tui::KeyCode::PageDown) {
        move_selection(10, false);
    } else if (event.code == tui::KeyCode::PageUp) {
        move_selection(-10, false);
    } else if (event.is(U'g')) {
        move_selection(-1, true);
    } else if (event.is(U'G')) {
        move_selection(1, true);
    } else if ((event.code == tui::KeyCode::Tab || event.code == tui::KeyCode::BackTab) && page == PageKind::Proxies) {
        nodes_focus = !nodes_focus;
    } else if ((event.is(U'h') || event.code == tui::KeyCode::Left) && page == PageKind::Proxies) {
        nodes_focus = false;
    } else if ((event.is(U'l') || event.code == tui::KeyCode::Right) && page == PageKind::Proxies) {
        nodes_focus = true;
    } else if (event.is(U'p') && (page == PageKind::Proxies || page == PageKind::Rules)) {
        provider_mode = !provider_mode;
        provider = 0;
        rebuild_views();
    } else if (event.is(U'S') && page == PageKind::Proxies && !provider_mode) {
        sort = sort == Sort::Default ? Sort::Delay : sort == Sort::Delay ? Sort::Name : Sort::Default;
        rebuild_nodes();
    } else if (event.is(U'S') && page == PageKind::Connections) {
        connection_sort = (connection_sort + 1) % 4;
        rebuild_views();
    } else if (event.is(U'H') && page == PageKind::Proxies) {
        hide_timeout = !hide_timeout;
        rebuild_nodes();
    } else if (event.is(U'c') && page == PageKind::Proxies) {
        const auto current_value = current_node();
        const auto found = current_value ? std::find(node_names.begin(), node_names.end(), *current_value) : node_names.end();
        if (found != node_names.end()) {
            node = static_cast<size_t>(found - node_names.begin());
            nodes_focus = true;
        } else {
            status = "当前节点被过滤；Esc 清除或 H 显示超时节点";
        }
    } else if (event.is(U't') && provider_mode && page == PageKind::Proxies) {
        if (provider < provider_view.size()) {
            const std::string name = provider_view[provider];
            const auto socket = opts_.socket;
            command([socket, name] {
                Client client{socket, nullptr};
                return from_api(client.healthcheck(name));
            });
        }
    } else if (event.is(U'u') && provider_mode) {
        if (provider < provider_view.size()) {
            const std::string name = provider_view[provider];
            const bool rules_mode = page == PageKind::Rules;
            const auto& map = rules_mode ? rule_providers : providers;
            const auto found = map.find(name);
            if (found != map.end() && (found->second.vehicle_type == "Compatible" || found->second.vehicle_type == "Inline")) {
                page = PageKind::Profiles;
                status = "嵌入源请在订阅页更新所属订阅";
                return;
            }
            const auto socket = opts_.socket;
            command([socket, name, rules_mode] {
                Client client{socket, nullptr};
                return from_api(client.update_provider(name, rules_mode));
            });
        }
    } else if (event.is(U't') && page == PageKind::Proxies) {
        measure(0);
    } else if (event.is(U'T') && page == PageKind::Proxies) {
        measure(1);
    } else if (event.is(U'b') && page == PageKind::Proxies) {
        measure(2);
    } else if (event.is(U'm')) {
        const std::string mode = native_settings.mode == "rule" ? "global" : native_settings.mode == "global" ? "direct" : "rule";
        native_command(NativeAction{NativeKind::Change, "mode", mode, std::nullopt, {}});
    } else if (event.code == tui::KeyCode::Enter && page == PageKind::Proxies && !provider_mode) {
        if (!nodes_focus) {
            nodes_focus = true;
            return;
        }
        const auto name = group_name();
        if (!name) return;
        const std::string kind = proxies.count(*name) ? proxies[*name].kind : "";
        if (!(kind == "Selector" || kind == "URLTest" || kind == "Fallback")) {
            status = "此组由内核按策略分配，不能手动选节点";
            return;
        }
        if (node < node_names.size()) {
            const std::string selected = node_names[node];
            const auto socket = opts_.socket;
            command([socket, group = *name, selected] {
                Client client{socket, nullptr};
                return from_api(client.select(group, selected));
            });
        }
    } else if (event.is(U'v') && page == PageKind::Proxies && !provider_mode) {
        detail_scroll = 0;
        Dialog detail;
        detail.kind = Dialog::Kind::Detail;
        const std::string name = group_name().value_or("--");
        const std::string kind = group_name() && proxies.count(*group_name()) ? proxies[*group_name()].kind : "--";
        detail.text = "代理组：" + name + "\n类型：" + kind + "\n当前：" + current_node().value_or("按策略分配") + "\n所选节点：" +
                      (node < node_names.size() ? node_names[node] : "--") + "\n提示：自动/故障转移组可手动指定；T 测速会恢复自动选择。";
        dialog = std::move(detail);
    } else if (event.code == tui::KeyCode::Enter && provider_mode) {
        if (provider < provider_view.size()) {
            const std::string& name = provider_view[provider];
            const auto& map = page == PageKind::Rules ? rule_providers : providers;
            if (const auto found = map.find(name); found != map.end()) {
                detail_scroll = 0;
                Dialog detail;
                detail.kind = Dialog::Kind::Detail;
                detail.text = "源：" + name + "\n类型：" + found->second.vehicle_type + " / " + found->second.kind + "\n更新：" + found->second.updated_at + "\n节点：" +
                              std::to_string(found->second.proxies.size()) + "\n规则：" + std::to_string(found->second.rule_count) + "\n注意：Compatible 源来自配置，不能远程更新。";
                dialog = std::move(detail);
            }
        }
    } else if (event.is(U'U') && page == PageKind::Profiles) {
        std::vector<std::string> ids;
        for (const Subscription& item : store.items) ids.push_back(item.id);
        native_command(NativeAction{NativeKind::UpdateMany, {}, {}, std::nullopt, std::move(ids)});
    } else if ((event.is(U'n') || event.is(U'e') || event.is(U'd')) && page == PageKind::Profiles) {
        const auto id = selected_profile_id();
        if (!id) return;
        if (event.is(U'd')) {
            if (store.current && *store.current == *id) {
                status = "当前订阅不能删除；请先切换";
            } else {
                confirm(ConfirmAction{ConfirmAction::Kind::DeleteProfile, {}, 0, *id}, "删除所选订阅及它的缓存？");
            }
        } else if (event.is(U'n')) {
            Dialog edit;
            edit.kind = Dialog::Kind::Edit;
            edit.title = "重命名订阅";
            edit.value.set(profile < store.items.size() ? store.items[profile].name : "");
            edit.edit = EditAction{EditKind::Rename, *id};
            dialog = std::move(edit);
        } else {
            Dialog edit;
            edit.kind = Dialog::Kind::Edit;
            edit.title = "编辑订阅 URL · 内容脱敏";
            edit.edit = EditAction{EditKind::Url, *id};
            dialog = std::move(edit);
        }
    } else if ((event.is(U'u') || event.code == tui::KeyCode::Enter) && page == PageKind::Profiles) {
        if (const auto id = selected_profile_id()) {
            if (event.code == tui::KeyCode::Enter) native_command(NativeAction{NativeKind::Use, *id, {}, std::nullopt, {}});
            else native_command(NativeAction{NativeKind::Update, *id, {}, std::nullopt, {}});
        }
    } else if (event.is(U'f') && page == PageKind::Profiles) {
        refresh_usage();
    } else if (event.is(U'x') && page == PageKind::Connections) {
        if (const Connection* selected = selected_connection()) {
            confirm(ConfirmAction{ConfirmAction::Kind::Close, {selected->id}, 0, {}},
                    "关闭所选连接 " + selected->metadata.host + ":" + selected->metadata.destination_port + "？");
        }
    } else if (event.is(U'd') && page == PageKind::Connections) {
        std::vector<std::string> ids;
        for (const size_t index : connection_view) ids.push_back(connections[index].id);
        if (!ids.empty()) {
            confirm(ConfirmAction{ConfirmAction::Kind::Close, ids, 0, {}},
                    "关闭当前过滤结果中的 " + std::to_string(ids.size()) + " 条连接？确认后仅操作此快照。");
        }
    } else if (event.is(U'D') && page == PageKind::Connections) {
        confirm(ConfirmAction{ConfirmAction::Kind::CloseAll, {}, 0, {}}, "关闭全部连接？包括确认期间新建的连接。");
    } else if (event.code == tui::KeyCode::Enter && page == PageKind::Connections) {
        if (const Connection* c = selected_connection()) {
            detail_scroll = 0;
            std::string chains;
            for (const std::string& part : c->chains) {
                if (!chains.empty()) chains += " → ";
                chains += part;
            }
            Dialog detail;
            detail.kind = Dialog::Kind::Detail;
            detail.text = "目标：" + c->metadata.host + ":" + c->metadata.destination_port + "\nIP：" + c->metadata.destination_ip + "\n源：" + c->metadata.source_ip + ":" + c->metadata.source_port +
                          " / " + c->metadata.network + "\n进程：" + c->metadata.process + "\n路径：" + c->metadata.process_path + "\n规则：" + c->rule + " / " + c->rule_payload + "\n链路：" + chains +
                          "\n开始：" + c->start + "\n上传：" + bytes_text(c->upload) + "\n下载：" + bytes_text(c->download) + "\nID：" + c->id;
            dialog = std::move(detail);
        }
    } else if (event.code == tui::KeyCode::Enter && page == PageKind::Rules && !provider_mode) {
        if (const Rule* row = selected_rule()) {
            detail_scroll = 0;
            Dialog detail;
            detail.kind = Dialog::Kind::Detail;
            detail.text = "规则：" + row->kind + "\n内容：" + row->payload + "\n策略：" + row->proxy + "\n命中：" +
                          (row->extra ? std::to_string(row->extra->hit_count) : std::string("内核未提供计数")) + "\n上次命中：" + (row->extra ? row->extra->hit_at : std::string("未知"));
            dialog = std::move(detail);
        }
    } else if (event.is(U' ') && page == PageKind::Logs) {
        logs_paused = !logs_paused;
    } else if (event.is(U'L') && page == PageKind::Logs) {
        log_level = (log_level + 1) % 4;
        rebuild_logs();
    } else if (event.code == tui::KeyCode::Enter && page == PageKind::Tools && tool >= 3) {
        edit_setting();
    } else if (event.code == tui::KeyCode::Enter && page == PageKind::Tools) {
        if (!online) {
            status = "此工具需要服务运行；s 手动启动";
            return;
        }
        const std::string body = tool == 0 ? "清空 fake-ip 缓存？已建立的映射会被丢弃。"
                                 : tool == 1 ? "清空 DNS 缓存？之后的解析会重新查询。"
                                             : "更新 GeoIP/GeoSite 数据库？内核将联网下载并重载规则；Nix store 内资源可能只读。";
        confirm(ConfirmAction{ConfirmAction::Kind::Tool, {}, tool, {}}, body);
    }
}
std::optional<std::string> App::selected_profile_id() const {
    if (profile < store.items.size()) return store.items[profile].id;
    return std::nullopt;
}
void App::handle_mouse(const tui::InputEvent& event) {
    dirty = true;
    if (help) {
        if (event.type == tui::InputEvent::Type::WheelDown) help_page = (help_page + 1) % kPageCount;
        if (event.type == tui::InputEvent::Type::WheelUp) help_page = (help_page + kPageCount - 1) % kPageCount;
        return;
    }
    if (dialog) {
        if (event.type == tui::InputEvent::Type::WheelDown) detail_scroll += 1;
        else if (event.type == tui::InputEvent::Type::WheelUp) detail_scroll = std::max(detail_scroll - 1, 0);
        else if (event.type == tui::InputEvent::Type::MouseClick) {
            const int height = dialog->kind == Dialog::Kind::Import ? 13 : dialog->kind == Dialog::Kind::Detail ? 22 : 9;
            const tui::Rect area = tui::centered(screen_width, screen_height, 80, height);
            if (dialog->kind == Dialog::Kind::Import) {
                if (event.x > area.x && event.x < area.x + area.width && ((event.y == area.y + 2 && dialog->field) || (event.y == area.y + 4 && !dialog->field))) {
                    tui::Key tab;
                    tab.code = tui::KeyCode::Tab;
                    key(tab);
                    return;
                }
            }
            if (event.y == area.y + area.height - 2 && event.x > area.x && event.x < area.x + area.width - 1) {
                tui::Key value;
                value.code = event.x < area.x + area.width / 2 ? tui::KeyCode::Enter : tui::KeyCode::Escape;
                key(value);
            }
        }
        return;
    }
    if (event.type == tui::InputEvent::Type::WheelDown) {
        move_selection(3, false);
        return;
    }
    if (event.type == tui::InputEvent::Type::WheelUp) {
        move_selection(-3, false);
        return;
    }
    if (event.type != tui::InputEvent::Type::MouseClick) return;
    if (event.y == 1) {
        for (const auto& [rect, index] : tab_hits) {
            if (rect.contains(event.x, event.y)) {
                tui::Key value;
                value.code = tui::KeyCode::Char;
                value.ch = static_cast<char32_t>(U'1' + index);
                key(value);
                return;
            }
        }
        return;
    }
    if (event.y < 3 || event.y >= screen_height - 2) return;
    const bool activate = last_click && last_click->first == event.x && last_click->second == event.y &&
                          std::chrono::steady_clock::now() - last_click_time < std::chrono::milliseconds(400);
    last_click = std::pair{event.x, event.y};
    last_click_time = std::chrono::steady_clock::now();
    for (const auto& hit : row_hits) {
        if (!hit.rect.contains(event.x, event.y)) continue;
        if (page == PageKind::Proxies && !provider_mode) nodes_focus = !hit.groups;
        if (provider_mode && (page == PageKind::Proxies || page == PageKind::Rules)) provider = hit.index;
        else if (page == PageKind::Proxies && hit.groups) {
            group = hit.index;
            node = 0;
            rebuild_nodes();
        } else if (page == PageKind::Proxies) node = hit.index;
        else if (page == PageKind::Profiles) profile = hit.index;
        else if (page == PageKind::Connections) connection = hit.index;
        else if (page == PageKind::Rules) rule = hit.index;
        else if (page == PageKind::Logs) log = hit.index;
        else if (page == PageKind::Tools) tool = hit.index;
        if (activate) {
            tui::Key value;
            value.code = tui::KeyCode::Enter;
            key(value);
        }
        return;
    }
}
}  // namespace clash
