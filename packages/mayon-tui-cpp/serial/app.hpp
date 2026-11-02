// Serial application state and operations: the same model as the Rust tool's app.rs.
// It has no drawing or terminal code, so tests can drive it directly.
#pragma once
#include <array>
#include <chrono>
#include <cstdint>
#include <deque>
#include <expected>
#include <filesystem>
#include <functional>
#include <map>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

#include "codec.hpp"
#include "flash.hpp"
#include "store.hpp"
#include "transport.hpp"
#include "ui/input.hpp"

namespace serial {
using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;

inline constexpr std::array<uint32_t, 10> kCommonBauds{9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600, 1'000'000, 2'000'000};
inline constexpr size_t kMaxCaptureBytes = 32u * 1024 * 1024;
// A received chunk display cap, matching the framer's current-line cap.
inline constexpr size_t kDisplayLimitBytes = 16u * 1024;

// One captured line or event. Clock and stamp are formatted when the record is created,
// because drawing must not run localtime() for every visible row on every frame.
struct Record {
    uint64_t id = 0;
    std::string clock;   // local HH:MM:SS.mmm
    std::string stamp;   // RFC 3339 with the local offset
    double elapsed = 0;  // seconds since the application started
    std::string kind;    // RX, TX, 连接, 断开, 错误, 烧录
    Bytes raw;
    std::string text;
    std::string plain;  // text with ANSI and control sequences removed, cached for filtering
};
// Bounded capture: at most `limit` records and 32 MiB of raw plus decoded bytes.
class Capture {
public:
    explicit Capture(size_t limit);
    void push(Record record);
    // Re-decodes RX records after an encoding switch and re-applies both limits.
    void reencode(Encoding encoding);
    size_t size_bytes() const { return bytes_; }
    size_t limit() const { return limit_; }

    std::deque<Record> records;
    uint64_t next = 0;
    size_t evicted = 0;

private:
    void trim();
    size_t bytes_ = 0;
    size_t limit_;
};
// Writes the raw byte stream, a timestamped text log and optional telemetry CSV.
class Logger {
public:
    static std::expected<Logger, std::string> start(const Store& store, bool csv);
    ~Logger();
    Logger(Logger&& other) noexcept;
    Logger& operator=(Logger&& other) noexcept;
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;
    std::expected<void, std::string> record(const Record& record);
    std::expected<void, std::string> write_raw(std::span<const uint8_t> bytes);
    // Stem without an extension; the files are `.bin`, `.log` and optionally `.csv`.
    std::filesystem::path path;

private:
    Logger() = default;
    static void close_all(Logger& logger);
    int raw_ = -1;
    int text_ = -1;
    int csv_ = -1;
};

enum class InputKind { Send, Search, Filter, Baud, Settings, Favorite, File, Timer, FlashCommand, FlashDir, Highlights };
struct Input {
    InputKind kind = InputKind::Send;
    tui::TextInput text;
    std::string before;
};
struct Repeat {
    Bytes bytes;
    std::chrono::milliseconds every{1000};
    TimePoint next;
};

class App {
public:
    // Starts the transport worker immediately, like the Rust App::new. `notify` runs on the
    // worker thread when captured data is ready; it must only wake the UI, never change state.
    explicit App(Store store, std::function<void()> notify = {});
    ~App();
    App(const App&) = delete;
    App& operator=(const App&) = delete;

    // Queues a command for the transport worker; a busy or parked worker is reported.
    bool command(Command command);
    void persist();
    void select(Device device, std::optional<uint32_t> baud);
    void note(const std::string& kind, std::string text, Bytes raw);
    void flush();
    void toggle_encoding();
    void receive(Bytes raw);
    TimePoint deadline() const;
    void suspend();
    void resume();
    void tick();
    void reconnect();
    std::expected<void, std::string> send(const std::string& text);
    void replace_devices(std::vector<Device> devices);
    void open(InputKind kind, std::string text);
    std::expected<void, std::string> submit(InputKind kind, const std::string& text);
    void apply();
    const Capture& view_capture() const;
    std::optional<uint64_t> view_anchor() const;
    void pause();
    void scroll_up(size_t count);
    // Match ids are cached incrementally, so a streaming capture does not rescan old records.
    const std::vector<uint64_t>& search_matches();
    const std::vector<uint64_t>& filtered_ids();
    void search_next();
    void search_previous();
    void logging();
    void request_flash();
    void cancel_flash();
    bool flashing() const { return flash_ != nullptr; }
    bool flash_waiting() const { return flash_wait_; }
    const std::optional<std::pair<std::string, std::string>>& pending_flash() const { return pending_flash_; }

    Store store;
    Worker worker;
    std::vector<Device> devices;
    size_t selected = 0;
    std::optional<Device> device;
    Profile profile;
    bool connected = false;
    bool reconnect_on_resume = false;
    std::string status;
    size_t page = 1;
    Capture capture;
    Capture wire;
    std::optional<uint64_t> wire_anchor;
    Framer framer;
    TimePoint started = Clock::now();
    std::optional<TimePoint> disconnected;
    size_t mode = 0;       // 0 TEXT, 1 HEX, 2 MIX
    size_t timestamp = 0;  // 0 clock, 1 relative, 2 none
    std::optional<uint64_t> anchor;
    size_t scroll = 0;
    std::string search;
    std::string filter;
    std::optional<uint64_t> found;
    bool graph = true;
    std::map<std::string, std::deque<std::pair<double, double>>> series;
    std::optional<Input> input;
    bool help = false;
    bool tx_hex = false;
    size_t history_index = 0;
    size_t favorite_index = 0;
    size_t settings_index = 0;
    Bytes last_sent;
    std::optional<Repeat> repeat;
    std::optional<Logger> logger;
    bool csv = false;
    uint64_t rx_total = 0;
    uint64_t tx_total = 0;
    double rate = 0;
    double rate_tx = 0;
    std::deque<std::string> flash_lines;

private:
    void start_flash();
    void search_move(bool reverse);
    void trim_flash_lines();

    TimePoint rate_at_ = Clock::now();
    uint64_t rate_rx_ = 0;
    uint64_t rate_tx_bytes_ = 0;
    TimePoint refresh_at_ = Clock::now();
    std::unique_ptr<Flash> flash_;
    bool flash_wait_ = false;
    uint64_t flash_seq_ = 0;
    std::optional<std::pair<std::string, std::string>> pending_flash_;
    std::function<void()> notify_;
    struct SearchCache {
        std::string search;
        std::string filter;
        uint64_t next = 0;
        size_t evicted = 0;
        size_t mode = 0;
        bool wire = false;
        std::vector<uint64_t> ids;
    };
    SearchCache search_cache_;
    struct FilterCache {
        std::string filter;
        uint64_t next = 0;
        size_t evicted = 0;
        bool wire = false;
        std::vector<uint64_t> ids;
    };
    FilterCache filter_cache_;
};

// Text plus the configured line ending, or raw HEX bytes. Errors are user-facing Chinese.
std::expected<Bytes, std::string> payload(const std::string& text, bool hex, Encoding encoding, const std::string& ending);
// Range and enumeration checks for a full settings row.
std::expected<void, std::string> validate_settings(const Settings& settings);
// A port supplied on the command line that sysfs did not enumerate.
Device explicit_device(const std::string& path);
// Flash tools found on PATH, in a stable order.
std::vector<std::string> detected_flash();
}  // namespace serial
