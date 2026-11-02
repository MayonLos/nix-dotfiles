#include "voice_internal.hpp"

#include "voice.hpp"

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>
#include <stdexcept>

#include "ui/search.hpp"
#include "ui/text.hpp"

namespace voice {
namespace {
using nlohmann::json;

const char* env_value(const char* name) {
    const char* value = std::getenv(name);
    return value != nullptr && *value != '\0' ? value : nullptr;
}
std::string io_error(int code) { return std::string(std::strerror(code)) + " (os error " + std::to_string(code) + ")"; }
std::string trim(const std::string& text) {
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const auto last = text.find_last_not_of(" \t\r\n");
    return text.substr(first, last - first + 1);
}
// Reads a TOML basic string starting after the opening quote.
std::string parse_string(const std::string& line, size_t& at) {
    std::string out;
    if (at >= line.size() || (line[at] != '"' && line[at] != '\'')) throw std::runtime_error("expected a quoted string");
    const char quote = line[at++];
    while (at < line.size()) {
        const char ch = line[at++];
        if (ch == quote) return out;
        if (ch == '\\' && quote == '"' && at < line.size()) {
            const char escaped = line[at++];
            switch (escaped) {
                case 'n': out += '\n'; break;
                case 't': out += '\t'; break;
                case 'r': out += '\r'; break;
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                default: out += escaped; break;
            }
            continue;
        }
        out += ch;
    }
    throw std::runtime_error("unterminated string");
}
std::string parse_key(const std::string& line, size_t& at) {
    if (at < line.size() && (line[at] == '"' || line[at] == '\'')) return parse_string(line, at);
    const size_t start = at;
    while (at < line.size() && line[at] != '=' && line[at] != ' ' && line[at] != '\t') ++at;
    return line.substr(start, at - start);
}
void skip_spaces(const std::string& line, size_t& at) {
    while (at < line.size() && (line[at] == ' ' || line[at] == '\t')) ++at;
}
// Parses one value; arrays may span lines, so the caller keeps feeding lines until `need_more` is false.
struct Parsed {
    enum class Kind { String, Integer, Boolean, Array } kind = Kind::String;
    std::string text;
    int64_t integer = 0;
    bool boolean = false;
    std::vector<std::string> array;
};
bool value_is_complete(const std::string& source) {
    int depth = 0;
    bool quoted = false;
    char quote = 0;
    for (size_t i = 0; i < source.size(); ++i) {
        const char ch = source[i];
        if (quoted) {
            if (ch == '\\' && quote == '"') ++i;
            else if (ch == quote) quoted = false;
            continue;
        }
        if (ch == '"' || ch == '\'') {
            quoted = true;
            quote = ch;
        } else if (ch == '[') {
            ++depth;
        } else if (ch == ']') {
            --depth;
        }
    }
    return depth <= 0;
}
std::string strip_comment(const std::string& line) {
    bool quoted = false;
    char quote = 0;
    for (size_t i = 0; i < line.size(); ++i) {
        const char ch = line[i];
        if (quoted) {
            if (ch == '\\' && quote == '"') ++i;
            else if (ch == quote) quoted = false;
            continue;
        }
        if (ch == '"' || ch == '\'') {
            quoted = true;
            quote = ch;
        } else if (ch == '#') {
            return line.substr(0, i);
        }
    }
    return line;
}
Parsed parse_value(const std::string& source) {
    std::string value = trim(source);
    if (value.empty()) throw std::runtime_error("missing value");
    Parsed out;
    if (value.front() == '"' || value.front() == '\'') {
        size_t at = 0;
        out.kind = Parsed::Kind::String;
        out.text = parse_string(value, at);
        if (trim(value.substr(at)).empty()) return out;
        throw std::runtime_error("unexpected text after string");
    }
    if (value.front() == '[') {
        out.kind = Parsed::Kind::Array;
        size_t at = 1;
        while (true) {
            skip_spaces(value, at);
            if (at < value.size() && value[at] == ']') {
                ++at;
                break;
            }
            if (at >= value.size()) throw std::runtime_error("unterminated array");
            out.array.push_back(parse_string(value, at));
            skip_spaces(value, at);
            if (at < value.size() && value[at] == ',') {
                ++at;
                continue;
            }
            if (at < value.size() && value[at] == ']') {
                ++at;
                break;
            }
            throw std::runtime_error("expected , or ] in array");
        }
        if (!trim(value.substr(at)).empty()) throw std::runtime_error("unexpected text after array");
        return out;
    }
    if (value == "true" || value == "false") {
        out.kind = Parsed::Kind::Boolean;
        out.boolean = value == "true";
        return out;
    }
    try {
        size_t used = 0;
        out.kind = Parsed::Kind::Integer;
        out.integer = std::stoll(value, &used, 10);
        if (used != value.size()) throw std::runtime_error("bad integer");
    } catch (const std::exception&) {
        throw std::runtime_error("unsupported value `" + value + "`");
    }
    return out;
}
std::string require_string(const Parsed& value, const std::string& key) {
    if (value.kind != Parsed::Kind::String) throw std::runtime_error("`" + key + "` must be a string");
    return value.text;
}
uint64_t require_unsigned(const Parsed& value, const std::string& key) {
    if (value.kind != Parsed::Kind::Integer || value.integer < 0) throw std::runtime_error("`" + key + "` must be a positive integer");
    return static_cast<uint64_t>(value.integer);
}
void write_all(int fd, const std::string& data, const std::atomic<bool>& cancel, Response& out) {
    size_t sent = 0;
    while (sent < data.size()) {
        if (cancel) {
            out.error = "cancelled";
            return;
        }
        const ssize_t wrote = ::write(fd, data.data() + sent, data.size() - sent);
        if (wrote < 0) {
            if (errno == EINTR) continue;
            out.error = io_error(errno);
            return;
        }
        sent += static_cast<size_t>(wrote);
    }
    out.ok = true;
}
}  // namespace

tui::TimePoint steady_now() { return std::chrono::steady_clock::now(); }

std::string home() {
    const char* value = env_value("HOME");
    return value != nullptr ? value : ".";
}
std::string config_dir() {
    const char* base = env_value("XDG_CONFIG_HOME");
    std::string root = base != nullptr ? base : home() + "/.config";
    return root + "/mayon-voice";
}
std::string data_dir() {
    const char* base = env_value("XDG_DATA_HOME");
    std::string root = base != nullptr ? base : home() + "/.local/share";
    return root + "/mayon-voice";
}

std::string display_path(const std::string& path) {
    const std::string base = home();
    if (!base.empty() && path.size() > base.size() + 1 && path.compare(0, base.size(), base) == 0 && path[base.size()] == '/') {
        return "~/" + path.substr(base.size() + 1);
    }
    return path;
}

Config load_config() {
    Config config;
    config.model_dir = data_dir() + "/models/sensevoice";
    const std::string path = config_dir() + "/config.toml";
    struct stat meta {};
    if (::stat(path.c_str(), &meta) != 0) {
        if (errno == ENOENT) return config;
        throw std::runtime_error("无法读取 " + path + "：" + io_error(errno));
    }
    std::ifstream file(path);
    if (!file) throw std::runtime_error("无法读取 " + path + "：" + io_error(errno));
    static const std::vector<std::string> kFields{"engine", "model_dir", "model_file", "whisper_binary", "device", "threads", "input_device", "delivery", "hotwords", "idle_seconds", "max_record_seconds", "polish", "key_file"};
    std::string line;
    size_t number = 0;
    while (std::getline(file, line)) {
        ++number;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::string text = strip_comment(line);
        size_t at = 0;
        skip_spaces(text, at);
        if (at >= text.size()) continue;
        if (text[at] == '[') throw std::runtime_error("config.toml 第 " + std::to_string(number) + " 行：不支持的表 " + trim(text));
        std::string key = parse_key(text, at);
        skip_spaces(text, at);
        if (at >= text.size() || text[at] != '=') throw std::runtime_error("config.toml 第 " + std::to_string(number) + " 行：缺少 =");
        ++at;
        std::string source = text.substr(at);
        while (!value_is_complete(source) && std::getline(file, line)) {
            ++number;
            source += " " + strip_comment(line);
        }
        if (std::find(kFields.begin(), kFields.end(), key) == kFields.end()) {
            throw std::runtime_error("config.toml 第 " + std::to_string(number) + " 行：unknown field `" + key + "`");
        }
        const Parsed value = parse_value(source);
        if (key == "engine") config.engine = require_string(value, key);
        else if (key == "model_dir") config.model_dir = require_string(value, key);
        else if (key == "model_file") config.model_file = require_string(value, key);
        else if (key == "whisper_binary") config.whisper_binary = require_string(value, key);
        else if (key == "device") config.device = require_string(value, key);
        else if (key == "threads") config.threads = static_cast<uint32_t>(std::min<uint64_t>(require_unsigned(value, key), UINT32_MAX));
        else if (key == "input_device") config.input_device = require_string(value, key);
        else if (key == "delivery") config.delivery = require_string(value, key);
        else if (key == "hotwords") {
            if (value.kind != Parsed::Kind::Array) throw std::runtime_error("`hotwords` must be an array of strings");
            config.hotwords = value.array;
        } else if (key == "idle_seconds") config.idle_seconds = require_unsigned(value, key);
        else if (key == "max_record_seconds") config.max_record_seconds = require_unsigned(value, key);
        else if (key == "polish") {
            if (value.kind != Parsed::Kind::Boolean) throw std::runtime_error("`polish` must be a boolean");
            config.polish = value.boolean;
        } else if (key == "key_file") config.key_file = require_string(value, key);
    }
    const bool engine_ok = config.engine == "sensevoice" || config.engine == "paraformer" || config.engine == "whisper-cli";
    const bool delivery_ok = config.delivery == "auto" || config.delivery == "fcitx" || config.delivery == "wtype" || config.delivery == "clipboard";
    const bool device_ok = config.device == "cpu" || config.device == "cuda";
    if (!engine_ok || !delivery_ok || !device_ok || config.idle_seconds == 0 || config.max_record_seconds == 0 || config.max_record_seconds > 600 || config.threads < 1 || config.threads > 16) {
        throw std::runtime_error("配置值超出允许范围");
    }
    return config;
}

std::optional<Status> parse_status(const std::string& text) {
    const json value = json::parse(text, nullptr, false);
    if (value.is_discarded()) return std::nullopt;
    Status out;
    if (value.is_object()) {
        if (const auto it = value.find("phase"); it != value.end() && it->is_string()) out.phase = it->get<std::string>();
        if (const auto it = value.find("delivery"); it != value.end() && it->is_string()) out.delivery = it->get<std::string>();
        if (const auto it = value.find("error"); it != value.end() && it->is_string()) out.error = it->get<std::string>();
    }
    return out;
}
std::string phase_text(const Status& status) {
    if (status.phase == "recording") return "● 录音中";
    if (status.phase == "transcribing") return "◌ 识别中";
    if (status.phase == "idle") return "○ 就绪";
    if (status.phase == "error") return "! 操作失败";
    return "○ 按需待命";
}
uint32_t phase_color(const Status& status) {
    if (status.phase == "recording") return tui::kGreen;
    if (status.phase == "transcribing") return tui::kYellow;
    if (status.phase == "idle") return tui::kGreen;
    if (status.phase == "error") return tui::kRed;
    return tui::kMuted;
}

Filtered filter_lines(const std::vector<Line>& lines, const std::string& query, bool help) {
    Filtered out;
    for (size_t id = 0; id < lines.size(); ++id) {
        if (help || query.empty()) {
            out.ids.push_back(id);
            out.lines.push_back(lines[id]);
            out.ranges.emplace_back();
            continue;
        }
        const auto hit = tui::match(query, lines[id].text);
        if (!hit) continue;
        out.ids.push_back(id);
        out.lines.push_back(lines[id]);
        out.ranges.push_back(hit->ranges);
    }
    if (out.lines.empty()) {
        out.empty = true;
        out.lines.push_back(Line{"没有匹配 · Esc 清除过滤", tui::kMuted, false});
        out.ranges.emplace_back();
    }
    return out;
}
size_t preserve_line(size_t selected, const std::vector<size_t>& previous, const std::vector<size_t>& next) {
    if (selected >= previous.size()) return 0;
    const auto found = std::find(next.begin(), next.end(), previous[selected]);
    return found == next.end() ? 0 : static_cast<size_t>(found - next.begin());
}

Response daemon_request(const std::string& command, int timeout_ms, const std::atomic<bool>& cancel) {
    Response out;
    const char* runtime = env_value("XDG_RUNTIME_DIR");
    if (runtime == nullptr) {
        out.error = "缺少 XDG_RUNTIME_DIR";
        return out;
    }
    const std::string dir = std::string(runtime) + "/mayon-voice";
    std::error_code code;
    std::filesystem::create_directories(dir, code);
    struct stat meta {};
    if (::lstat(dir.c_str(), &meta) != 0) {
        out.error = io_error(errno);
        return out;
    }
    if (!S_ISDIR(meta.st_mode) || meta.st_uid != ::geteuid()) {
        out.error = "runtime 目录归属错误";
        return out;
    }
    [[maybe_unused]] const int chmod_result = ::chmod(dir.c_str(), 0700);
    const std::string path = dir + "/control.sock";
    if (path.size() >= sizeof(sockaddr_un::sun_path)) {
        out.error = "socket 路径过长";
        return out;
    }
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        out.error = io_error(errno);
        return out;
    }
    struct Close {
        int fd;
        ~Close() { ::close(fd); }
    } close{fd};
    sockaddr_un address {};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    if (cancel) {
        out.error = "cancelled";
        return out;
    }
    if (::connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof address) != 0) {
        out.error = io_error(errno);
        return out;
    }
    timeval timeout {};
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    [[maybe_unused]] const int receive = ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    [[maybe_unused]] const int send = ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
    write_all(fd, command + "\n", cancel, out);
    if (!out.ok) return out;
    std::string response;
    char buffer[4096];
    while (response.size() < 65536 && response.find('\n') == std::string::npos) {
        if (cancel) {
            out.error = "cancelled";
            return out;
        }
        const ssize_t got = ::read(fd, buffer, sizeof buffer);
        if (got < 0) {
            if (errno == EINTR) continue;
            out.error = io_error(errno);
            return out;
        }
        if (got == 0) break;
        response.append(buffer, static_cast<size_t>(got));
    }
    const auto newline = response.find('\n');
    if (newline != std::string::npos) response.resize(newline);
    if (response.empty()) {
        out.error = "daemon 没有返回状态";
        return out;
    }
    out.ok = true;
    out.body = std::move(response);
    return out;
}

VoicePage::VoicePage() : VoicePage(load_config()) {}
VoicePage::VoicePage(Config config, Clock clock) : config_(std::move(config)), clock_(std::move(clock)) {
    if (!clock_) clock_ = steady_now;
    refreshed_ = clock_() - std::chrono::seconds(1);
}
VoicePage::~VoicePage() { cancel_job(); }

void VoicePage::attach(tui::Post post) { post_ = std::move(post); }
void VoicePage::set_active(bool active) {
    active_ = active;
    if (active) {
        refreshed_ = clock_() - std::chrono::seconds(1);
    } else {
        cancel_job();
    }
}

std::vector<Line> VoicePage::lines() const {
    std::vector<Line> out;
    if (help_) {
        out.push_back(Line{" 快捷键", tui::kBlue, false});
        out.push_back(Line{" 空格 开始/结束录音    1/2 切页", tui::kFg, false});
        out.push_back(Line{" / 过滤信息            ? 关闭帮助", tui::kFg, false});
        out.push_back(Line{" q 退出界面（录音与服务独立运行）", tui::kFg, false});
        out.push_back(Line{" 鼠标滚轮滚动；点击顶部页签切页", tui::kFg, false});
        return out;
    }
    if (page_ == 0) {
        out.push_back(Line{phase_text(status_), phase_color(status_), true});
        out.push_back(Line{"", tui::kFg, false});
        out.push_back(Line{" 引擎       " + config_.engine + " / " + config_.device, tui::kFg, false});
        out.push_back(Line{" 上屏       " + status_.delivery.value_or(config_.delivery), tui::kFg, false});
        out.push_back(Line{"", tui::kFg, false});
        out.push_back(Line{" 按空格说话，再按一次结束。", tui::kMuted, false});
        out.push_back(Line{" 录音只暂存在私有 runtime；不保留转写历史。", tui::kMuted, false});
        out.push_back(Line{" 提示       " + status_.error.value_or("首次使用先运行 mayon-voice models fetch"), tui::kFg, false});
        return out;
    }
    out.push_back(Line{" 用户配置 · config.toml", tui::kBlue, true});
    out.push_back(Line{" 模型       " + display_path(config_.model_dir), tui::kFg, false});
    out.push_back(Line{" 设备       " + config_.device + " / " + std::to_string(config_.threads) + " threads", tui::kFg, false});
    out.push_back(Line{" 麦克风     " + config_.input_device, tui::kFg, false});
    std::string hotwords;
    for (const std::string& word : config_.hotwords) hotwords += (hotwords.empty() ? "" : "、") + word;
    out.push_back(Line{" 热词       " + hotwords, tui::kFg, false});
    out.push_back(Line{" AI 润色    " + std::string(config_.polish ? "开启 · 最多 3s，失败回退" : "关闭"), tui::kFg, false});
    out.push_back(Line{" 空闲退出   " + std::to_string(config_.idle_seconds) + "s", tui::kFg, false});
    out.push_back(Line{" 配置由用户维护；下次守护进程启动读取。", tui::kMuted, false});
    return out;
}

void VoicePage::request(const std::string& command) {
    cancel_job();
    auto job = std::make_shared<Job>();
    job_ = job;
    refreshed_ = clock_();
    const tui::Post post = post_;
    worker_ = std::thread([this, job, command, post] {
        const Response response = daemon_request(command, 500, job->cancel);
        std::optional<Status> status;
        if (command == "status") {
            if (response.ok) status = parse_status(*response.body);
            if (!status) status = Status{"inactive", std::nullopt, std::nullopt};
        } else {
            if (!response.ok) {
                status = Status{"error", std::nullopt, "语音操作失败：" + response.error};
            } else if (auto parsed = parse_status(*response.body)) {
                status = std::move(parsed);
            } else {
                status = Status{"error", std::nullopt, "语音操作失败：daemon 返回了无效的 JSON"};
            }
        }
        {
            const std::lock_guard lock(job->mutex);
            if (job->cancel) return;
            job->status = std::move(status);
        }
        job->done = true;
        if (post) post([this, job] { consume(job); });
    });
}
void VoicePage::cancel_job() {
    if (job_) {
        job_->cancel = true;
        job_.reset();
    }
    if (worker_.joinable()) worker_.join();
}
void VoicePage::consume(std::shared_ptr<Job> job) {
    if (job != job_ || !job->done) return;
    if (worker_.joinable()) worker_.join();
    job_.reset();
    std::optional<Status> status;
    {
        const std::lock_guard lock(job->mutex);
        status = job->status;
    }
    if (status) apply(*status);
}
void VoicePage::apply(const Status& status) {
    Status next = status;
    const auto now = clock_();
    if (next.phase == "error") {
        error_until_ = now + std::chrono::seconds(5);
    } else if (error_until_ && now < *error_until_) {
        next.error = status_.error;
    }
    status_ = next;
}

std::optional<tui::TimePoint> VoicePage::next_deadline() const {
    if (!active_) return std::nullopt;
    if (job_) return std::nullopt;  // The completion posts a mailbox wake.
    return refreshed_ + std::chrono::milliseconds(500);
}
void VoicePage::tick() {
    if (!active_) return;
    if (job_) {
        if (!job_->done) return;
        consume(job_);
    }
    if (!job_ && clock_() - refreshed_ >= std::chrono::milliseconds(500)) request("status");
}

void VoicePage::switch_page(size_t page) {
    page_ = page;
    scroll_ = 0;
    visible_ids_.clear();
}
void VoicePage::scroll_by(int64_t delta) {
    const int64_t last = static_cast<int64_t>(visible_ids_.size()) - 1;
    int64_t next = static_cast<int64_t>(scroll_) + delta;
    scroll_ = static_cast<size_t>(std::clamp<int64_t>(next, 0, std::max<int64_t>(last, 0)));
}

bool VoicePage::handle_key(const tui::Key& key) {
    if (key.ctrl && key.ch == U'c') return true;
    if (help_) {
        if (key.code == tui::KeyCode::Escape || key.is(U'?') || key.is(U'q')) help_ = false;
        return false;
    }
    if (filtering_) {
        if (key.code == tui::KeyCode::Escape) {
            filtering_ = false;
            cursor_.reset();
            filter_ = previous_filter_;
            scroll_ = 0;
        } else if (key.code == tui::KeyCode::Enter) {
            filtering_ = false;
            cursor_.reset();
        } else if (key.code == tui::KeyCode::Down) {
            scroll_by(1);
        } else if (key.code == tui::KeyCode::Up) {
            scroll_by(-1);
        } else {
            filter_.handle(key);
        }
        return false;
    }
    if (key.ctrl || key.alt) return false;
    if (key.is(U'q')) return true;
    if (key.code == tui::KeyCode::Escape) {
        if (!filter_.empty()) {
            filter_.clear();
            scroll_ = 0;
            return false;
        }
        return true;
    }
    if (key.is(U'1')) {
        switch_page(0);
        return false;
    }
    if (key.is(U'2')) {
        switch_page(1);
        return false;
    }
    if (key.is(U'?')) {
        help_ = true;
        return false;
    }
    if (key.is(U'/')) {
        previous_filter_ = filter_;
        filtering_ = true;
        return false;
    }
    if (key.is(U' ')) {
        request("toggle");
        return false;
    }
    if (key.code == tui::KeyCode::Down) scroll_by(1);
    else if (key.code == tui::KeyCode::Up) scroll_by(-1);
    else if (key.code == tui::KeyCode::PageDown) scroll_by(8);
    else if (key.code == tui::KeyCode::PageUp) scroll_by(-8);
    else if (key.code == tui::KeyCode::Home || key.is(U'g')) scroll_ = 0;
    else if (key.code == tui::KeyCode::End || key.is(U'G')) scroll_ = visible_ids_.empty() ? 0 : visible_ids_.size() - 1;
    return false;
}

bool VoicePage::handle(const tui::InputEvent& event) {
    switch (event.type) {
        case tui::InputEvent::Type::Key:
            return handle_key(event.key);
        case tui::InputEvent::Type::Paste:
            if (filtering_ && !help_) {
                filter_.paste(event.paste);
                scroll_ = 0;
            }
            return false;
        case tui::InputEvent::Type::WheelDown:
            if (!help_) scroll_by(1);
            return false;
        case tui::InputEvent::Type::WheelUp:
            if (!help_) scroll_by(-1);
            return false;
        case tui::InputEvent::Type::MouseClick:
            for (const auto& [rect, page] : tab_hits_) {
                if (rect.contains(event.x, event.y)) {
                    switch_page(page);
                    return false;
                }
            }
            return false;
        case tui::InputEvent::Type::FocusIn:
        case tui::InputEvent::Type::FocusOut:
            return false;
    }
    return false;
}

void VoicePage::draw_tabs(ftxui::Screen& screen, tui::Rect row) {
    tab_hits_.clear();
    int x = row.x + 1;
    const int right = row.x + row.width;
    for (size_t index = 0; index < 2 && x < right; ++index) {
        const std::string name = index == 0 ? "状态" : "配置";
        const int start = x;
        x = tui::put(screen, x, row.y, std::to_string(index + 1), tui::Style{tui::kMuted}, right - x);
        x = tui::put(screen, x + 1, row.y, name, index == page_ ? tui::Style{tui::kBrightFg, {}, true} : tui::Style{tui::kMuted}, std::max(right - x - 1, 0));
        tab_hits_.emplace_back(tui::Rect{start, row.y, x - start + 1, 1}, index);
        x += 2;
    }
}
void VoicePage::draw_query(ftxui::Screen& screen, tui::Rect row) {
    cursor_.reset();
    if (row.width <= 2 || row.height <= 0) return;
    const int start_x = tui::put(screen, row.x + 1, row.y, "/ ", tui::Style{tui::kBlue}, row.width - 1);
    const int room = row.x + row.width - start_x - 1;
    if (room <= 0) return;
    const std::u32string before = tui::decode(filter_.before_cursor());
    const std::u32string all = tui::decode(filter_.str());
    size_t skip = 0;
    int used = tui::width_of(tui::encode(before));
    while (used >= room && skip < before.size()) used -= tui::width_of(tui::encode(std::u32string_view(before).substr(skip++, 1)));
    tui::put(screen, start_x, row.y, tui::encode(std::u32string_view(all).substr(skip)), tui::Style{tui::kBlue}, room);
    cursor_ = std::make_pair(start_x + used, row.y);
}
void VoicePage::draw_content(ftxui::Screen& screen, tui::Rect area) {
    const std::vector<Line> source = lines();
    const Filtered filtered = filter_lines(source, filter_.str(), help_);
    const size_t count = filtered.ids.size();
    const size_t total = source.size();
    if (!help_) {
        scroll_ = preserve_line(scroll_, visible_ids_, filtered.ids);
        visible_ids_ = filtered.ids;
        if (!visible_ids_.empty() && scroll_ >= visible_ids_.size()) scroll_ = visible_ids_.size() - 1;
        if (visible_ids_.empty()) scroll_ = 0;
    } else {
        scroll_ = 0;
    }
    int y = area.y;
    for (size_t index = scroll_; index < filtered.lines.size() && y < area.y + area.height; ++index) {
        const Line& line = filtered.lines[index];
        int x = area.x + 1;
        if (line.bar) x = tui::put(screen, x, y, "▏ ", tui::Style{tui::kBlue}, std::max(area.width - 1, 0));
        const int line_room = std::max(area.x + area.width - x - 1, 0);
        if (filtered.empty || help_ || filter_.empty()) {
            tui::put(screen, x, y, tui::clip(line.text, line_room), tui::Style{line.fg}, line_room);
        } else {
            tui::put_ranges(screen, x, y, line.text, filtered.ranges[index], tui::Style{line.fg}, line_room);
        }
        ++y;
    }
    if (area.height > 0 && !help_ && filtered.lines.size() > static_cast<size_t>(area.height)) {
        tui::put_scroll(screen, area.x + area.width - 1, area.y, area.height, scroll_, filtered.lines.size());
    }
    (void)count;
    (void)total;
}

void VoicePage::draw(ftxui::Screen& screen, tui::Rect area) {
    cursor_.reset();
    tab_hits_.clear();
    if (area.width <= 0 || area.height <= 0) return;
    const int footer = area.y + area.height - 1;
    const int content_y = area.y + 2;
    const tui::Rect content{area.x, content_y, area.width, std::max(footer - content_y, 0)};
    draw_content(screen, content);
    tui::put(screen, area.x + 1, area.y, tui::clip("语音输入 · 本地中文识别", std::max(area.width - 2, 0)), tui::Style{tui::kBrightFg}, std::max(area.width - 2, 0));
    if (!filter_.empty() || filtering_) {
        const size_t count = visible_ids_.size();
        const size_t total = lines().size();
        const std::string status = " " + std::to_string(count) + "/" + std::to_string(total) + " · /" + filter_.str() + " ";
        tui::put_right(screen, area.x + area.width - 1, area.y, tui::clip(status, std::max(area.width - 24, 0)), tui::Style{tui::kMuted});
    }
    if (area.height >= 2) draw_tabs(screen, tui::Rect{area.x, area.y + 1, area.width, 1});
    if (filtering_) {
        draw_query(screen, tui::Rect{area.x, footer, area.width, 1});
    } else if (footer >= 0 && footer < screen.dimy()) {
        if (area.height >= 2) {
            std::vector<tui::Hint> hints;
            if (help_) {
                hints.push_back({"?", "关闭帮助"});
                hints.push_back({"↑/↓", "滚动"});
            } else {
                hints.push_back({"空格", "录音"});
                hints.push_back({"1/2", "切页"});
                hints.push_back({"/", "过滤"});
                hints.push_back({"?", "帮助"});
                hints.push_back({"q", "退出"});
            }
            tui::put_hints(screen, area.x + 1, footer, std::max(area.width - 2, 0), hints);
        }
    }
}

}  // namespace voice

std::unique_ptr<tui::Page> make_voice_page() { return std::make_unique<voice::VoicePage>(); }
