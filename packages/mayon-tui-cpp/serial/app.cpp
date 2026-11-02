#include "app.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <exception>
#include <string_view>

#include "ui/search.hpp"

namespace serial {
namespace {
using std::chrono::duration;
using std::chrono::duration_cast;
using std::chrono::milliseconds;
using std::chrono::seconds;

constexpr auto kRefresh = milliseconds(750);
constexpr auto kFlashPoll = milliseconds(100);
constexpr size_t kMaxTxBytes = 1024 * 1024;
constexpr size_t kHistoryLimit = 1000;
constexpr size_t kFlashLineLimit = 2000;
constexpr size_t kFlashBytesLimit = 1024 * 1024;
constexpr size_t kSeriesLimit = 1024;
constexpr size_t kSeriesChannels = 16;

struct Stamp {
    std::string clock;  // HH:MM:SS.mmm
    std::string rfc3339;
};
Stamp local_stamp() {
    const auto now = std::chrono::system_clock::now();
    const auto whole = std::chrono::time_point_cast<seconds>(now);
    const auto micros = duration_cast<std::chrono::microseconds>(now - whole).count();
    const std::time_t when = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
    localtime_r(&when, &tm);
    char clock[16];
    std::snprintf(clock, sizeof clock, "%02d:%02d:%02d.%03lld", tm.tm_hour, tm.tm_min, tm.tm_sec, static_cast<long long>(micros / 1000));
    long offset = tm.tm_gmtoff;
    const char sign = offset < 0 ? '-' : '+';
    offset = offset < 0 ? -offset : offset;
    char stamp[80];
    std::snprintf(stamp, sizeof stamp, "%04d-%02d-%02dT%02d:%02d:%02d.%06lld%c%02ld:%02ld", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                  tm.tm_hour, tm.tm_min, tm.tm_sec, static_cast<long long>(micros), sign, offset / 3600, offset / 60 % 60);
    return Stamp{clock, stamp};
}
std::expected<void, std::string> write_fd(int fd, std::string_view text) {
    while (!text.empty()) {
        const ssize_t wrote = ::write(fd, text.data(), text.size());
        if (wrote < 0) {
            if (errno == EINTR) continue;
            return std::unexpected(os_error(errno));
        }
        text.remove_prefix(static_cast<size_t>(wrote));
    }
    return {};
}
std::filesystem::path with_extension(const std::filesystem::path& stem, const char* extension) {
    std::filesystem::path out = stem;
    out += ".";
    out += extension;
    return out;
}
std::string csv_number(double value) { return number_text(value); }
std::string csv_seconds(double value) {
    char buffer[64];
    std::snprintf(buffer, sizeof buffer, "%.6f", value);
    return buffer;
}
std::string ascii_of(const Bytes& bytes) {
    std::string out;
    for (const uint8_t byte : bytes) out += byte >= 32 && byte < 127 ? static_cast<char>(byte) : '.';
    return out;
}
std::string hex_of(const Bytes& bytes, size_t from, size_t count) {
    static constexpr char kDigits[] = "0123456789ABCDEF";
    std::string out;
    for (size_t i = 0; i < count && from + i < bytes.size(); ++i) {
        if (i != 0) out += ' ';
        const uint8_t byte = bytes[from + i];
        out += kDigits[byte >> 4];
        out += kDigits[byte & 15];
    }
    return out;
}
}  // namespace

Capture::Capture(size_t limit) : limit_(std::clamp<size_t>(limit, 100, 1'000'000)) {}
void Capture::push(Record record) {
    record.id = next++;
    record.plain = plain(record.text);
    bytes_ += record.raw.size() + record.text.size();
    records.push_back(std::move(record));
    trim();
}
void Capture::trim() {
    while (records.size() > limit_ || bytes_ > kMaxCaptureBytes) {
        if (records.empty()) break;
        bytes_ -= records.front().raw.size() + records.front().text.size();
        records.pop_front();
        ++evicted;
    }
}
void Capture::reencode(Encoding encoding) {
    for (Record& record : records) {
        if (record.kind == "RX") record.text = decode_bytes(encoding, record.raw);
    }
    for (Record& record : records) {
        if (record.kind == "RX") record.plain = plain(record.text);
    }
    bytes_ = 0;
    for (const Record& record : records) bytes_ += record.raw.size() + record.text.size();
    trim();
}

Logger::~Logger() { close_all(*this); }
Logger::Logger(Logger&& other) noexcept : path(std::move(other.path)), raw_(other.raw_), text_(other.text_), csv_(other.csv_) {
    other.raw_ = other.text_ = other.csv_ = -1;
}
Logger& Logger::operator=(Logger&& other) noexcept {
    if (this != &other) {
        close_all(*this);
        path = std::move(other.path);
        raw_ = other.raw_;
        text_ = other.text_;
        csv_ = other.csv_;
        other.raw_ = other.text_ = other.csv_ = -1;
    }
    return *this;
}
void Logger::close_all(Logger& logger) {
    for (int* fd : {&logger.raw_, &logger.text_, &logger.csv_}) {
        if (*fd >= 0) {
            ::close(*fd);
            *fd = -1;
        }
    }
}
std::expected<Logger, std::string> Logger::start(const Store& store, bool csv) {
    // The Rust name is %Y%m%d-%H%M%S-%f in local time.
    const auto now = std::chrono::system_clock::now();
    const auto whole = std::chrono::time_point_cast<std::chrono::seconds>(now);
    const auto micros = duration_cast<std::chrono::microseconds>(now - whole).count();
    const std::time_t when = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
    localtime_r(&when, &tm);
    char name[64];
    std::snprintf(name, sizeof name, "%04d%02d%02d-%02d%02d%02d-%06lld", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min,
                  tm.tm_sec, static_cast<long long>(micros));
    Logger logger;
    logger.path = store.data / "logs" / name;
    // Only files created by this attempt are removed; an existing log is never touched.
    std::vector<std::filesystem::path> created;
    const auto fail = [&](const std::string& message) {
        close_all(logger);
        for (const auto& path : created) {
            std::error_code ignored;
            std::filesystem::remove(path, ignored);
        }
        return std::unexpected(message);
    };
    try {
        logger.raw_ = private_file(with_extension(logger.path, "bin"));
        created.push_back(with_extension(logger.path, "bin"));
        logger.text_ = private_file(with_extension(logger.path, "log"));
        created.push_back(with_extension(logger.path, "log"));
        if (csv) {
            logger.csv_ = private_file(with_extension(logger.path, "csv"));
            created.push_back(with_extension(logger.path, "csv"));
            if (auto wrote = write_fd(logger.csv_, "timestamp,seconds,channel,value\n"); !wrote) return fail(wrote.error());
        }
    } catch (const std::exception& error) {
        return fail(error.what());
    }
    return logger;
}
std::expected<void, std::string> Logger::record(const Record& record) {
    if (auto wrote = write_fd(text_, record.stamp + " [" + record.kind + "] " + plain(record.text) + "\n"); !wrote) return wrote;
    if (record.kind != "RX" || csv_ < 0) return {};
    for (const auto& [key, value] : parse_values(plain(record.text))) {
        std::string quoted;
        for (const char c : key) {
            if (c == '"') quoted += '"';
            quoted += c;
        }
        if (auto wrote = write_fd(csv_, record.stamp + "," + csv_seconds(record.elapsed) + ",\"" + quoted + "\"," + csv_number(value) + "\n"); !wrote) {
            return wrote;
        }
    }
    return {};
}
std::expected<void, std::string> Logger::write_raw(std::span<const uint8_t> bytes) {
    return write_fd(raw_, std::string_view(reinterpret_cast<const char*>(bytes.data()), bytes.size()));
}

App::App(Store value, std::function<void()> notify)
    : store(std::move(value)),
      worker(Worker::start(notify)),
      capture(store.config.scrollback),
      wire(store.config.scrollback),
      notify_(std::move(notify)) {
    devices = discover();
    status = "选择端口后 Enter 连接 · ? 查看帮助";
}
App::~App() {
    flush();
    if (flash_) flash_->cancel();
    // A parked worker (after suspend) rejects this; there is nothing left to stop then.
    [[maybe_unused]] const auto shutdown = worker.tx->try_send(Command::shutdown());
    persist();
}
bool App::command(Command command) {
    const auto kind = command.kind;
    if ((flash_ || flash_wait_) && kind != Command::Kind::Release && kind != Command::Kind::Shutdown) {
        status = "烧录期间串口已释放，等待烧录结束";
        return false;
    }
    const auto result = worker.tx->try_send(std::move(command));
    if (result == CommandChannel::Result::Ok) {
        if (kind == Command::Kind::Connect) reconnect_on_resume = true;
        if (kind == Command::Kind::Disconnect) reconnect_on_resume = false;
        return true;
    }
    status = std::string("串口队列忙：") + (result == CommandChannel::Result::Full ? "sending on a full channel" : "sending on a closed channel");
    return false;
}
void App::persist() {
    if (device) store.config.devices[device->key()] = profile;
    try {
        store.save();
    } catch (const std::exception& error) {
        status = std::string("保存失败：") + error.what();
    }
}
void App::select(Device next, std::optional<uint32_t> baud) {
    if (flash_ || flash_wait_) {
        status = "烧录期间不能切换设备";
        return;
    }
    persist();
    flush();
    const auto found = store.config.devices.find(next.key());
    profile = found == store.config.devices.end() ? Profile{} : found->second;
    if (baud) profile.settings.baud = *baud;
    device = std::move(next);
    connected = false;
    repeat.reset();
    series.clear();
    disconnected = Clock::now();
    command(Command::connect(*device, profile.settings));
    page = 0;
    persist();
}
void App::note(const std::string& kind, std::string text, Bytes raw) {
    std::string shown = std::move(text);
    if (kind == "RX" && raw.size() >= kDisplayLimitBytes) shown += " [达到16KiB显示上限；完整字节见HEX/.bin]";
    const Stamp stamp = local_stamp();
    const double elapsed = duration<double>(Clock::now() - started).count();
    if (kind != "RX") wire.push(Record{0, stamp.clock, stamp.rfc3339, elapsed, kind, raw, shown});
    if (kind == "RX") {
        for (const auto& [key, value] : parse_values(plain(shown))) {
            if (series.size() >= kSeriesChannels && !series.contains(key)) continue;
            auto& data = series[key];
            data.emplace_back(elapsed, value);
            while (data.size() > kSeriesLimit) data.pop_front();
        }
    }
    capture.push(Record{0, stamp.clock, stamp.rfc3339, elapsed, kind, std::move(raw), std::move(shown)});
    if (logger) {
        if (auto wrote = logger->record(capture.records.back()); !wrote) {
            status = std::string("日志写入失败：") + wrote.error();
            logger.reset();
        }
    }
}
void App::flush() {
    if (auto raw = framer.flush()) {
        // The decode must read the bytes before the argument that moves them is evaluated.
        std::string text = decode_bytes(profile.encoding, *raw);
        note("RX", std::move(text), std::move(*raw));
    }
}
void App::toggle_encoding() {
    flush();
    profile.encoding = profile.encoding == Encoding::Utf8 ? Encoding::Gbk : Encoding::Utf8;
    capture.reencode(profile.encoding);
    persist();
}
void App::receive(Bytes raw) {
    rx_total += raw.size();
    const Stamp stamp = local_stamp();
    const double elapsed = duration<double>(Clock::now() - started).count();
    for (size_t at = 0; at < raw.size(); at += 16) {
        const size_t count = std::min<size_t>(16, raw.size() - at);
        Bytes chunk(raw.begin() + static_cast<ptrdiff_t>(at), raw.begin() + static_cast<ptrdiff_t>(at + count));
        const std::string text = hex_of(chunk, 0, count) + "  " + ascii_of(chunk);
        wire.push(Record{0, stamp.clock, stamp.rfc3339, elapsed, "RX", std::move(chunk), text});
    }
    if (logger) {
        if (auto wrote = logger->write_raw(raw); !wrote) {
            status = std::string("原始日志失败：") + wrote.error();
            logger.reset();
        }
    }
    for (Bytes& line : framer.push(raw)) {
        std::string text = decode_bytes(profile.encoding, line);
        note("RX", std::move(text), std::move(line));
    }
}
TimePoint App::deadline() const {
    TimePoint next = std::min(refresh_at_ + kRefresh, rate_at_ + seconds(1));
    if (repeat) next = std::min(next, repeat->next);
    if (flash_) next = std::min(next, Clock::now() + kFlashPoll);
    return next;
}
void App::suspend() {
    flush();
    worker.stop();
    worker = Worker::parked();
    connected = false;
    repeat.reset();
    if (flash_wait_ || flash_) status = "切换工具或失焦，已取消烧录";
    flash_wait_ = false;
    pending_flash_.reset();
    if (flash_) {
        flash_->cancel();
        flash_.reset();
    }
}
void App::resume() {
    worker = Worker::start(notify_);
    refresh_at_ = Clock::now() - seconds(1);
    if (reconnect_on_resume) reconnect();
}
void App::tick() {
    for (int i = 0; i < 512; ++i) {
        auto event = worker.rx->try_recv();
        if (!event) break;
        if (event->kind == Event::Kind::Rx) {
            receive(std::move(event->bytes));
        } else if (event->kind == Event::Kind::Tx) {
            tx_total += event->count;
        } else if (event->kind == Event::Kind::Connected) {
            connected = true;
            std::string suffix;
            if (disconnected) {
                char gap[32];
                std::snprintf(gap, sizeof gap, " · 断开 %.2fs", duration<double>(Clock::now() - *disconnected).count());
                suffix = gap;
                disconnected.reset();
            }
            note("连接", event->text + " 已连接" + suffix, {});
            status = "已连接 " + event->text;
            if (device) device->path = event->text;
        } else if (event->kind == Event::Kind::Disconnected) {
            flush();
            connected = false;
            repeat.reset();
            if (!disconnected) disconnected = Clock::now();
            note("断开", event->text, {});
            series.clear();
        } else if (event->kind == Event::Kind::Released) {
            if (flash_wait_ && event->id == flash_seq_) {
                flash_wait_ = false;
                start_flash();
            }
        } else if (event->kind == Event::Kind::Error) {
            note("错误", event->text, {});
            status = event->text;
        }
    }
    if (Clock::now() - refresh_at_ > kRefresh) {
        replace_devices(discover());
        refresh_at_ = Clock::now();
    }
    const double elapsed = duration<double>(Clock::now() - rate_at_).count();
    if (elapsed >= 1.0) {
        rate = static_cast<double>(rx_total - rate_rx_) / elapsed;
        rate_tx = static_cast<double>(tx_total - rate_tx_bytes_) / elapsed;
        rate_rx_ = rx_total;
        rate_tx_bytes_ = tx_total;
        rate_at_ = Clock::now();
    }
    if (repeat && Clock::now() >= repeat->next && connected) {
        Bytes bytes = repeat->bytes;
        repeat->next = Clock::now() + repeat->every;
        command(Command::write(std::move(bytes)));
    }
    std::optional<std::string> done;
    if (flash_) {
        for (int i = 0; i < 200; ++i) {
            auto event = flash_->rx->try_recv();
            if (!event) break;
            if (event->kind == FlashEvent::Kind::Line) {
                flash_lines.push_back(plain(event->text));
                trim_flash_lines();
            } else {
                done = std::move(event->text);
                break;
            }
        }
    }
    if (done) {
        flash_.reset();
        flash_lines.push_back(*done);
        note("烧录", *done, {});
        reconnect();
    }
}
void App::trim_flash_lines() {
    size_t bytes = 0;
    for (const std::string& line : flash_lines) bytes += line.size();
    while (!flash_lines.empty() && (flash_lines.size() > kFlashLineLimit || bytes > kFlashBytesLimit)) {
        bytes -= flash_lines.front().size();
        flash_lines.pop_front();
    }
}
void App::reconnect() {
    if (flash_ || flash_wait_) return;
    if (device) command(Command::connect(*device, profile.settings));
}
std::expected<void, std::string> App::send(const std::string& text) {
    if (!connected) return std::unexpected("设备未连接");
    auto bytes = payload(text, tx_hex, profile.encoding, profile.ending);
    if (!bytes) return std::unexpected(bytes.error());
    if (bytes->size() > kMaxTxBytes) return std::unexpected("单次发送限制 1 MiB");
    if (!command(Command::write(*bytes))) return std::unexpected(status);
    last_sent = *bytes;
    store.remember(text);
    persist();
    note("TX", tx_hex ? "HEX " + text : text, *bytes);
    status = "已排队发送";
    return {};
}
void App::replace_devices(std::vector<Device> next) {
    std::optional<std::string> selected_key;
    if (selected < devices.size()) selected_key = devices[selected].key();
    devices = std::move(next);
    selected = 0;
    if (!selected_key) return;
    for (size_t i = 0; i < devices.size(); ++i) {
        if (devices[i].key() == *selected_key) {
            selected = i;
            break;
        }
    }
}
void App::open(InputKind kind, std::string text) {
    std::string before;
    if (kind == InputKind::Filter) before = filter;
    if (kind == InputKind::Search) before = search;
    Input next;
    next.kind = kind;
    next.text.set(text);
    next.before = before;
    input = std::move(next);
    history_index = store.history.size();
}
std::expected<void, std::string> App::submit(InputKind kind, const std::string& text) {
    switch (kind) {
        case InputKind::Send:
            return send(text);
        case InputKind::Search:
            search = text;
            search_next();
            return {};
        case InputKind::Filter:
            filter = text;
            scroll = 0;
            return {};
        case InputKind::Baud: {
            const auto parsed = parse_unsigned(trim_text(text), 0xFFFF'FFFFu);
            if (!parsed) return std::unexpected("请输入有效波特率");
            if (*parsed == 0 || *parsed > 12'000'000) return std::unexpected("波特率范围 1–12000000");
            profile.settings.baud = static_cast<uint32_t>(*parsed);
            apply();
            return {};
        }
        case InputKind::Settings: {
            Settings settings = profile.settings;
            for (const std::string& field : split_whitespace(text)) {
                const size_t equals = field.find('=');
                if (equals == std::string::npos) return std::unexpected("使用 baud=115200 bits=8 parity=none stop=1 flow=none");
                const std::string key = field.substr(0, equals);
                const std::string value = field.substr(equals + 1);
                if (key == "baud") {
                    const auto parsed = parse_unsigned(value, 0xFFFF'FFFFu);
                    if (!parsed) return std::unexpected("波特率无效");
                    settings.baud = static_cast<uint32_t>(*parsed);
                } else if (key == "bits") {
                    const auto parsed = parse_unsigned(value, 255);
                    if (!parsed) return std::unexpected("数据位无效");
                    settings.bits = static_cast<uint8_t>(*parsed);
                } else if (key == "stop") {
                    const auto parsed = parse_unsigned(value, 255);
                    if (!parsed) return std::unexpected("停止位无效");
                    settings.stop = static_cast<uint8_t>(*parsed);
                } else if (key == "parity") {
                    settings.parity = value;
                } else if (key == "flow") {
                    settings.flow = value;
                } else {
                    return std::unexpected("未知参数 " + key);
                }
            }
            if (auto valid = validate_settings(settings); !valid) return valid;
            profile.settings = settings;
            apply();
            return {};
        }
        case InputKind::Favorite: {
            const size_t equals = text.find('=');
            if (equals == std::string::npos) return std::unexpected("格式：名称=命令");
            const std::string name = trim_text(text.substr(0, equals));
            if (name.empty()) return std::unexpected("名称不能为空");
            store.config.favorites.push_back(Favorite{name, text.substr(equals + 1), tx_hex});
            persist();
            return {};
        }
        case InputKind::File: {
            if (!connected) return std::unexpected("设备未连接");
            std::error_code error;
            const auto status = std::filesystem::status(text, error);
            if (error) return std::unexpected(os_error(error.value()));
            if (!std::filesystem::is_regular_file(status)) return std::unexpected("仅支持不超过 1 MiB 的普通文件；按原字节发送");
            const auto size = std::filesystem::file_size(text, error);
            if (error) return std::unexpected(os_error(error.value()));
            if (size > kMaxTxBytes) return std::unexpected("仅支持不超过 1 MiB 的普通文件；按原字节发送");
            Bytes bytes(size);
            const int fd = ::open(text.c_str(), O_RDONLY | O_CLOEXEC);
            if (fd < 0) return std::unexpected(os_error(errno));
            size_t got = 0;
            while (got < bytes.size()) {
                const ssize_t count = ::read(fd, bytes.data() + got, bytes.size() - got);
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) break;
                got += static_cast<size_t>(count);
            }
            const int read_error = errno;
            ::close(fd);
            if (got != bytes.size()) return std::unexpected(os_error(read_error));
            command(Command::write(std::move(bytes)));
            note("TX", "发送文件 " + text + " · " + std::to_string(got) + " B", {});
            return {};
        }
        case InputKind::Timer: {
            const auto parsed = parse_unsigned(trim_text(text), UINT64_MAX);
            if (!parsed) return std::unexpected("请输入毫秒数；0 停止");
            if (*parsed == 0) {
                repeat.reset();
                return {};
            }
            if (*parsed < 20) return std::unexpected("最短间隔 20 ms");
            if (last_sent.empty() || !connected) return std::unexpected("先连接并发送一条命令");
            Repeat next;
            next.bytes = last_sent;
            next.every = milliseconds(*parsed);
            next.next = Clock::now() + next.every;
            repeat = std::move(next);
            return {};
        }
        case InputKind::FlashCommand:
            profile.flash = text;
            persist();
            return {};
        case InputKind::FlashDir: {
            std::error_code error;
            if (!text.empty() && !std::filesystem::is_directory(text, error)) return std::unexpected("目录不存在");
            profile.flash_dir = text;
            persist();
            return {};
        }
        case InputKind::Highlights: {
            std::vector<std::string> words;
            size_t at = 0;
            while (at <= text.size()) {
                const size_t next = text.find(',', at);
                const std::string part = trim_text(text.substr(at, next == std::string::npos ? std::string::npos : next - at));
                if (!part.empty()) words.push_back(part);
                if (next == std::string::npos) break;
                at = next + 1;
            }
            store.config.highlights = std::move(words);
            persist();
            return {};
        }
    }
    return {};
}
void App::apply() {
    persist();
    if (flash_ || flash_wait_) {
        status = "参数已保存，将在烧录结束后应用";
        return;
    }
    if (device) {
        flush();
        reconnect();
    }
}
const Capture& App::view_capture() const { return mode == 0 ? capture : wire; }
std::optional<uint64_t> App::view_anchor() const { return mode == 0 ? anchor : wire_anchor; }
void App::pause() {
    if (anchor) {
        anchor.reset();
        wire_anchor.reset();
        scroll = 0;
        return;
    }
    anchor = capture.records.empty() ? uint64_t{0} : capture.records.back().id;
    wire_anchor = wire.records.empty() ? uint64_t{0} : wire.records.back().id;
}
void App::scroll_up(size_t count) {
    if (!anchor) pause();
    scroll = std::min<size_t>(scroll + count, view_capture().records.empty() ? 0 : view_capture().records.size() - 1);
}
const std::vector<uint64_t>& App::search_matches() {
    Capture& view = mode == 0 ? capture : wire;
    const bool wire_mode = mode != 0;
    const uint64_t front = view.records.empty() ? 0 : view.records.front().id;
    SearchCache& cache = search_cache_;
    if (cache.search != search || cache.filter != filter || cache.wire != wire_mode) {
        cache.ids.clear();
        cache.next = front;
        cache.search = search;
        cache.filter = filter;
        cache.wire = wire_mode;
    }
    size_t keep = 0;
    while (keep < cache.ids.size() && cache.ids[keep] < front) ++keep;
    if (keep > 0) cache.ids.erase(cache.ids.begin(), cache.ids.begin() + static_cast<ptrdiff_t>(keep));
    if (!trim_text(search).empty()) {
        const bool has_filter = !trim_text(filter).empty();
        for (uint64_t id = cache.next; id < view.next; ++id) {
            if (id < front) continue;
            const size_t index = static_cast<size_t>(id - front);
            if (index >= view.records.size()) break;
            const Record& record = view.records[index];
            if (record.kind == "RX" && has_filter && !tui::match(filter, record.plain)) continue;
            if (!tui::match(search, record.plain)) continue;
            cache.ids.push_back(id);
        }
    }
    cache.next = view.next;
    cache.evicted = view.evicted;
    return cache.ids;
}
const std::vector<uint64_t>& App::filtered_ids() {
    Capture& view = mode == 0 ? capture : wire;
    const bool wire_mode = mode != 0;
    const uint64_t front = view.records.empty() ? 0 : view.records.front().id;
    FilterCache& cache = filter_cache_;
    if (cache.filter != filter || cache.wire != wire_mode) {
        cache.ids.clear();
        cache.next = front;
        cache.filter = filter;
        cache.wire = wire_mode;
    }
    size_t keep = 0;
    while (keep < cache.ids.size() && cache.ids[keep] < front) ++keep;
    if (keep > 0) cache.ids.erase(cache.ids.begin(), cache.ids.begin() + static_cast<ptrdiff_t>(keep));
    const bool has_filter = !trim_text(filter).empty();
    for (uint64_t id = cache.next; id < view.next; ++id) {
        if (id < front) continue;
        const size_t index = static_cast<size_t>(id - front);
        if (index >= view.records.size()) break;
        const Record& record = view.records[index];
        if (has_filter && record.kind == "RX" && !tui::match(filter, record.plain)) continue;
        cache.ids.push_back(id);
    }
    cache.next = view.next;
    cache.evicted = view.evicted;
    return cache.ids;
}
void App::search_next() { search_move(false); }
void App::search_previous() { search_move(true); }
void App::search_move(bool reverse) {
    const std::optional<uint64_t> previous = found;
    const std::vector<uint64_t>& matches = search_matches();
    found.reset();
    if (reverse) {
        for (auto it = matches.rbegin(); it != matches.rend(); ++it) {
            if (!previous || *it < *previous) {
                found = *it;
                break;
            }
        }
        if (!found && !matches.empty()) found = matches.back();
    } else {
        for (const uint64_t id : matches) {
            if (!previous || id > *previous) {
                found = id;
                break;
            }
        }
        if (!found && !matches.empty()) found = matches.front();
    }
    if (found) {
        if (mode == 0) {
            anchor = found;
        } else {
            wire_anchor = found;
            anchor = capture.records.empty() ? uint64_t{0} : capture.records.back().id;
        }
        scroll = 0;
        size_t position = 0;
        for (size_t i = 0; i < matches.size(); ++i) {
            if (matches[i] == *found) position = i + 1;
        }
        status = "第 " + std::to_string(position) + "/共 " + std::to_string(matches.size()) + " 个 · n 下一个 · N 上一个";
    } else {
        status = "没有匹配 · Esc 清除";
    }
}
void App::logging() {
    if (logger) {
        flush();
        logger.reset();
        status = "日志已关闭";
        return;
    }
    auto started_logger = Logger::start(store, csv);
    if (!started_logger) {
        status = "无法创建日志：" + started_logger.error();
        return;
    }
    logger = std::move(*started_logger);
    status = "日志 → " + logger->path.string() + ".*";
}
void App::request_flash() {
    if (flash_ || flash_wait_) {
        status = "烧录正在执行";
        return;
    }
    if (!device) {
        status = "先选择监视设备";
        return;
    }
    if (trim_text(profile.flash).empty()) {
        status = "先在 5 烧录 页设置命令与工作目录；不猜芯片型号";
        page = 4;
        return;
    }
    repeat.reset();
    flash_wait_ = true;
    status = "等待串口关闭确认 · Esc 取消";
    flash_seq_ += 1;
    pending_flash_ = std::make_pair(profile.flash, profile.flash_dir);
    page = 4;
    if (!command(Command::release(flash_seq_))) {
        flash_wait_ = false;
        pending_flash_.reset();
    }
}
void App::start_flash() {
    flash_lines.clear();
    if (!pending_flash_) return;
    auto [command_text, directory] = *pending_flash_;
    pending_flash_.reset();
    auto flash = Flash::start(command_text, directory);
    if (!flash) {
        status = "无法启动烧录：" + flash.error();
        reconnect();
        return;
    }
    flash_ = std::move(*flash);
    status = "串口已释放，烧录中 · Esc 取消";
}
void App::cancel_flash() {
    if (flash_wait_) {
        flash_wait_ = false;
        pending_flash_.reset();
        status = "已取消待执行的烧录";
        reconnect();
    }
    if (flash_) {
        flash_->cancel();
        flash_.reset();
        note("烧录", "已取消烧录", {});
        reconnect();
    }
}

std::expected<Bytes, std::string> payload(const std::string& text, bool hex, Encoding encoding, const std::string& ending) {
    if (hex) return parse_hex(text);
    auto bytes = encode_text(encoding, text);
    if (!bytes) return bytes;
    if (ending == "CR") bytes->push_back('\r');
    else if (ending == "LF") bytes->push_back('\n');
    else if (ending == "CRLF") {
        bytes->push_back('\r');
        bytes->push_back('\n');
    }
    return bytes;
}
std::expected<void, std::string> validate_settings(const Settings& settings) {
    if (settings.baud == 0 || settings.baud > 12'000'000 || settings.bits < 5 || settings.bits > 8 || settings.stop < 1 || settings.stop > 2 ||
        (settings.parity != "none" && settings.parity != "odd" && settings.parity != "even") ||
        (settings.flow != "none" && settings.flow != "hardware" && settings.flow != "software")) {
        return std::unexpected("参数无效：bits=5..8 parity=none/odd/even stop=1/2 flow=none/hardware/software");
    }
    return {};
}
Device explicit_device(const std::string& path) {
    Device device;
    device.path = path;
    device.product = "手动端口";
    return device;
}
std::vector<std::string> detected_flash() {
    std::vector<std::string> found;
    const char* path = std::getenv("PATH");
    const std::string_view all = path == nullptr ? std::string_view() : std::string_view(path);
    for (const char* name : {"probe-rs", "openocd", "st-flash"}) {
        size_t at = 0;
        while (at <= all.size()) {
            const size_t next = all.find(':', at);
            const std::string directory(all.substr(at, next == std::string_view::npos ? std::string_view::npos : next - at));
            if (!directory.empty()) {
                std::error_code error;
                if (std::filesystem::is_regular_file(std::filesystem::path(directory) / name, error)) {
                    found.emplace_back(name);
                    break;
                }
            }
            if (next == std::string_view::npos) break;
            at = next + 1;
        }
    }
    return found;
}
}  // namespace serial
