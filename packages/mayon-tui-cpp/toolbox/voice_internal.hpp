// Private to the voice page and its tests. The public entry is voice.hpp.
#pragma once
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "ui/draw.hpp"
#include "ui/input.hpp"
#include "ui/page.hpp"

namespace voice {
using Clock = std::function<tui::TimePoint()>;
tui::TimePoint steady_now();

std::string home();
std::string config_dir();
std::string data_dir();
// Shortens a path under HOME to "~/...", like the Rust dashboard.
std::string display_path(const std::string& path);

// The subset of packages/mayon-voice Config that the dashboard shows. Defaults and
// validation follow mayon_voice::Config::load so both versions read the same file.
struct Config {
    std::string engine = "sensevoice";
    std::string model_dir;
    std::optional<std::string> model_file;
    std::string whisper_binary = "whisper-cli";
    std::string device = "cpu";
    uint32_t threads = 4;
    std::string input_device = "auto";
    std::string delivery = "auto";
    std::vector<std::string> hotwords;
    uint64_t idle_seconds = 600;
    uint64_t max_record_seconds = 120;
    bool polish = false;
    std::string key_file = "/run/secrets/deepseek-api-key";
};
// Throws std::runtime_error with the same meaning as the Rust errors.
Config load_config();

// The dashboard view of the daemon's status line. Missing fields stay empty.
struct Status {
    std::string phase = "inactive";
    std::optional<std::string> delivery;
    std::optional<std::string> error;
    bool operator==(const Status& other) const {
        return phase == other.phase && delivery == other.delivery && error == other.error;
    }
    bool operator!=(const Status& other) const { return !(*this == other); }
};
std::optional<Status> parse_status(const std::string& text);
std::string phase_text(const Status& status);
uint32_t phase_color(const Status& status);

// One dashboard line before filtering. `bar` draws the blue left bar the Rust page uses.
struct Line {
    std::string text;
    uint32_t fg = tui::kFg;
    bool bar = false;
};
struct Filtered {
    std::vector<size_t> ids;    // Stable ids of the visible lines.
    std::vector<Line> lines;    // Filtered lines, in order; highlight applies to `ranges`.
    std::vector<std::vector<std::pair<size_t, size_t>>> ranges;
    bool empty = false;  // True when nothing matched and the placeholder line is shown.
};
// Help ignores the query and keeps every line, like voice.rs.
Filtered filter_lines(const std::vector<Line>& lines, const std::string& query, bool help);
// Keeps the previous selected line selected after the filter changed.
size_t preserve_line(size_t selected, const std::vector<size_t>& previous, const std::vector<size_t>& next);

struct Response {
    bool ok = false;
    std::string error;
    std::optional<std::string> body;
};
// Blocking Unix-socket request to the running daemon, 500 ms timeouts like the Rust page.
Response daemon_request(const std::string& command, int timeout_ms, const std::atomic<bool>& cancel);

class VoicePage : public tui::Page {
public:
    explicit VoicePage(Config config, Clock clock = steady_now);
    // Loads Config::load() through the default clock; throws on configuration errors.
    VoicePage();
    ~VoicePage() override;
    VoicePage(const VoicePage&) = delete;
    VoicePage& operator=(const VoicePage&) = delete;

    void attach(tui::Post post) override;
    void set_active(bool active) override;
    void draw(ftxui::Screen& screen, tui::Rect area) override;
    bool handle(const tui::InputEvent& event) override;
    std::optional<tui::TimePoint> next_deadline() const override;
    void tick() override;
    std::optional<std::pair<int, int>> cursor() const override { return cursor_; }

    // Test seams; the UI thread owns all state as usual.
    const Status& status() const { return status_; }
    size_t page() const { return page_; }
    bool help() const { return help_; }
    bool filtering() const { return filtering_; }
    size_t scroll() const { return scroll_; }
    const std::vector<size_t>& visible_ids() const { return visible_ids_; }
    void request_for_test(const std::string& command) { request(command); }
    void cancel_for_test() { cancel_job(); }

private:
    struct Job {
        std::atomic<bool> cancel{false};
        std::atomic<bool> done{false};
        std::mutex mutex;
        std::optional<Status> status;
    };

    void request(const std::string& command);
    void cancel_job();
    void consume(std::shared_ptr<Job> job);
    void apply(const Status& status);

    std::vector<Line> lines() const;
    void draw_tabs(ftxui::Screen& screen, tui::Rect row);
    void draw_query(ftxui::Screen& screen, tui::Rect row);
    void draw_content(ftxui::Screen& screen, tui::Rect area);
    bool handle_key(const tui::Key& key);
    void switch_page(size_t page);
    void scroll_by(int64_t delta);

    Config config_;
    Clock clock_;
    size_t page_ = 0;
    bool help_ = false;
    bool filtering_ = false;
    tui::TextInput filter_;
    tui::TextInput previous_filter_;
    size_t scroll_ = 0;
    std::vector<size_t> visible_ids_;
    Status status_;
    tui::TimePoint refreshed_ = steady_now() - std::chrono::seconds(1);
    std::optional<tui::TimePoint> error_until_;
    std::shared_ptr<Job> job_;
    std::thread worker_;
    bool active_ = true;
    std::optional<std::pair<int, int>> cursor_;
    std::vector<std::pair<tui::Rect, size_t>> tab_hits_;
    int last_height_ = 0;
};
}  // namespace voice
