// State, filtering, key handling and worker scheduling for the Clash TUI.
// Only the UI thread mutates state; workers hand variants to Post closures.
#pragma once
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <functional>
#include <iosfwd>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <tuple>
#include <utility>
#include <variant>
#include <vector>

#include "api.hpp"
#include "matcher.hpp"
#include "native.hpp"
#include "ui/input.hpp"
#include "ui/page.hpp"

namespace clash {
class App;
// Renderer (ui.cpp); a friend so it can record click geometry without exposing it.
void ui_draw(App& app, ftxui::Screen& screen, tui::Rect area);
constexpr size_t kPageCount = 7;
extern const char* const kTabs[kPageCount];
enum class PageKind : size_t { Overview, Proxies, Profiles, Connections, Rules, Logs, Tools };
enum class Sort { Default, Delay, Name };
const char* sort_label(Sort sort);
enum class Tone { Info, Action, Success, Warning, Error };
uint32_t tone_color(Tone tone);
const char* tone_symbol(Tone tone);

// TUI preferences from ~/.config/mayon-tui/clash.toml (settings.rs).
struct Prefs {
    std::string test_url = "https://www.gstatic.com/generate_204";
    uint64_t timeout_ms = 5000;
    uint64_t concurrency = 4;
    std::string default_sort = "default";
    uint64_t default_page = 1;
    // Empty on success, otherwise the Rust error text.
    std::string validate() const;
};
struct Options {
    std::filesystem::path socket = "/run/mayon-clash/mihomo.sock";
    Prefs prefs;
    std::optional<std::string> usage_proxy;
    Native native;
};
enum class ParseResult { Run, Exit, Error };
// The TUI option parser of main.rs, including --help/--version output.
ParseResult parse_options(const std::vector<std::string>& args, Options& out, std::string& error);
std::filesystem::path default_config_path();
std::filesystem::path default_data_dir();

// ---- App state ---------------------------------------------------------------------------------
struct Snapshot {
    Proxies proxies;
    RuntimeConfig config;
    std::string version;
};
struct Resources {
    Providers providers;
    Providers rule_providers;
    std::vector<Rule> rules;
};
struct SnapshotReady {
    bool ok = false;
    Snapshot data;
    ApiError error = ApiError::Transport;
};
struct ResourcesReady {
    bool ok = false;
    Resources data;
    ApiError error = ApiError::Transport;
};
struct ConnectionsReady {
    ConnectionsResponse value;
};
struct ConnectionsOffline {};
struct TrafficReady {
    Traffic value;
};
struct TrafficOffline {};
struct LogReady {
    LogEntry value;
};
struct LogsState {
    bool on = false;
};
struct Message {
    std::string text;
    bool command_done = false;
};
struct DelayReady {
    uint64_t generation = 0;
    std::string name;
    std::optional<uint64_t> delay;
};
struct DelayDone {
    uint64_t generation = 0;
};
struct UsageReady {
    std::string uid;
    bool ok = false;
    Usage usage;
    std::string error;
};
struct NativeDone {
    bool ok = false;
    std::string message;
};
using Update = std::variant<SnapshotReady, ResourcesReady, ConnectionsReady, ConnectionsOffline, TrafficReady, TrafficOffline, LogReady, LogsState, Message, DelayReady, DelayDone,
                            UsageReady, NativeDone>;

enum class NativeKind { Add, Update, Use, Rename, Delete, Change, Start, Stop, Diagnose, UpdateMany };
struct NativeAction {
    NativeKind kind = NativeKind::Start;
    std::string first;
    std::string second;
    std::optional<std::string> url;
    std::vector<std::string> ids;
};
enum class EditKind { Rename, Url, Setting };
struct EditAction {
    EditKind kind = EditKind::Rename;
    std::string id;
};
struct ConfirmAction {
    enum class Kind { Stop, Close, CloseAll, Tool, DeleteProfile };
    Kind kind = Kind::Stop;
    std::vector<std::string> ids;
    size_t tool = 0;
    std::string id;
};
struct Dialog {
    enum class Kind { Confirm, Import, Detail, Edit };
    Kind kind = Kind::Confirm;
    ConfirmAction action;
    std::string body;
    tui::TextInput url;
    tui::TextInput name;
    bool field = false;
    std::string title;
    tui::TextInput value;
    EditAction edit;
    std::string text;
};

class App : public tui::Page {
public:
    explicit App(Options options);
    ~App() override;
    App(const App&) = delete;
    App& operator=(const App&) = delete;

    void attach(tui::Post post) override;
    void set_active(bool value) override;
    void draw(ftxui::Screen& screen, tui::Rect area) override;
    bool handle(const tui::InputEvent& event) override;
    std::optional<std::pair<int, int>> cursor() const override { return cursor_; }
    std::optional<tui::TimePoint> next_deadline() const override;
    void tick() override;

    // Called when the UI gains focus; starts periodic work and the live streams.
    void start();
    // Stops streams and one-shot work but keeps subscriptions and selection.
    void suspend();
    bool active() const { return active_; }
    const Options& options() const { return opts_; }

    // Test seam: apply an update as if a worker had posted it.
    void inject(Update update) { pending.push_back(std::move(update)); }

    // ---- State the renderer and tests inspect ------------------------------------------------
    Options opts_;
    Client client_;
    PageKind page = PageKind::Overview;
    Proxies proxies;
    std::vector<std::string> group_names;
    std::vector<std::string> node_names;
    RuntimeConfig config;
    std::vector<Connection> connections;
    std::vector<size_t> connection_view;
    std::map<std::string, uint64_t> rates;
    std::map<std::string, uint64_t> previous_connections;
    tui::TimePoint connection_time = std::chrono::steady_clock::now();
    bool connections_live = false;
    size_t connection_sort = 0;
    std::string version = "--";
    Providers providers;
    Providers rule_providers;
    std::vector<Rule> rules;
    std::vector<size_t> rule_view;
    std::vector<std::string> provider_view;
    bool provider_mode = false;
    Store store;
    std::map<std::string, Usage> usage;
    size_t group = 0;
    size_t node = 0;
    size_t profile = 0;
    size_t connection = 0;
    size_t rule = 0;
    size_t provider = 0;
    size_t log = 0;
    size_t tool = 0;
    bool nodes_focus = true;
    std::array<tui::TextInput, kPageCount> filters;
    tui::TextInput filter_before;
    bool filtering = false;
    std::optional<Dialog> dialog;
    int detail_scroll = 0;
    bool help = false;
    size_t help_page = 0;
    bool quit = false;
    bool dirty = true;
    std::string status = "正在连接内核…";
    Tone tone = Tone::Info;
    bool online = false;
    Settings native_settings;
    std::optional<std::string> native_error;
    bool native_busy = false;
    std::optional<std::pair<bool, tui::TimePoint>> lifecycle_pending;
    std::optional<Traffic> traffic;
    std::deque<std::pair<uint64_t, uint64_t>> history;
    std::pair<uint64_t, uint64_t> totals{0, 0};
    uint64_t memory = 0;
    std::map<std::string, std::optional<uint64_t>> delays;
    std::optional<std::pair<size_t, size_t>> measuring;
    Sort sort = Sort::Default;
    bool hide_timeout = false;
    std::deque<LogEntry> logs;
    std::vector<size_t> log_view;
    size_t log_level = 0;
    bool logs_paused = false;
    bool logs_live = false;
    uint64_t generation = 0;

    // ---- Queries used by the renderer -------------------------------------------------------
    const tui::TextInput& filter() const { return filters[static_cast<size_t>(page)]; }
    std::string filter_text() const { return filter().str(); }
    std::optional<std::string> group_name() const;
    std::optional<std::string> current_node() const;
    std::optional<std::optional<uint64_t>> delay(const std::string& node) const;
    std::string proxy_chain(const std::string& start) const;
    std::string chain() const;
    const Connection* selected_connection() const;
    const Rule* selected_rule() const;
    bool refresh_running = false;
    bool resources_running = false;
    bool loading() const { return !first_snapshot && refresh_running; }
    bool resources_loading() const { return resources_running; }
    std::string launch_progress() const;
    size_t tools_len() const { return 9; }
    std::string profile_name(size_t index) const;

    void rebuild_nodes();
    void rebuild_views();
    void rebuild_logs();
    void cancel_measure();

    // Test seams for the event/command paths.
    void key(const tui::Key& key);
    void paste_text(const std::string& value);
    void native_command(NativeAction action);
    void finish_native();
    void sync_notice();

    // Renderer bookkeeping (geometry for clicks, computed during draw).
    struct HitRow {
        tui::Rect rect;
        size_t index = 0;
        bool groups = false;
    };
    std::vector<std::pair<tui::Rect, size_t>> tab_hits;
    std::vector<HitRow> row_hits;
    std::optional<std::pair<int, int>> cursor_;
    int screen_width = 80;
    int screen_height = 24;
    friend void ui_draw(App& app, ftxui::Screen& screen, tui::Rect area);

private:
    void deliver(Update update);
    void deliver_native(NativeDone done);
    void drain_inbox();
    void cancel_and_join(std::thread& worker, std::shared_ptr<std::atomic<bool>> token, bool& running);
    void join_all(bool include_native);
    void reload_profiles();
    void refresh();
    void refresh_resources();
    void start_logs();
    void command(std::function<Res<>()> work);
    void execute(ConfirmAction action);
    void edit_setting();
    void measure(size_t kind);
    void refresh_usage();
    void confirm(ConfirmAction action, std::string body);
    void move_selection(int delta, bool edge);
    bool handle_key(const tui::Key& key);
    void handle_mouse(const tui::InputEvent& event);
    std::optional<std::string> selected_profile_id() const;
    std::pair<std::string, std::string> tool_entry(size_t index) const;

    tui::Post post_;
    bool attached = false;
    bool active_ = false;
    // Workers must never touch the run_page mailbox after it is gone. suspend()
    // closes this gate before returning, so the mailbox outlives every post.
    std::mutex post_mutex;
    bool post_alive = true;
    std::deque<NativeDone> deferred_native;
    std::mutex inbox_mutex;
    std::deque<Update> inbox;
    std::atomic<bool> inbox_posted{false};
    std::deque<Update> pending;
    std::string noticed_status;
    std::optional<tui::TimePoint> notice_until;
    std::string notice_text;
    Tone notice_tone = Tone::Info;
    std::optional<std::string> last_api_error;
    bool first_snapshot = false;
    tui::TimePoint last_clock = std::chrono::steady_clock::now();
    tui::TimePoint last_auto = std::chrono::steady_clock::now() - std::chrono::seconds(61);
    tui::TimePoint last_refresh = std::chrono::steady_clock::now();
    tui::TimePoint last_resources = std::chrono::steady_clock::now() - std::chrono::seconds(31);
    std::optional<std::pair<int, int>> last_click;
    tui::TimePoint last_click_time;
    bool queued_stop = false;
    size_t log_bytes = 0;
    uint64_t next_log_id = 0;

    std::thread refresh_thread;
    std::thread resources_thread;
    std::thread traffic_thread;
    std::thread connections_thread;
    std::thread logs_thread;
    std::thread delay_thread;
    std::thread usage_thread;
    std::thread command_thread;
    std::thread native_thread;
    std::shared_ptr<std::atomic<bool>> refresh_cancel;
    std::shared_ptr<std::atomic<bool>> resources_cancel;
    std::shared_ptr<std::atomic<bool>> usage_cancel;
    std::shared_ptr<std::atomic<bool>> command_cancel;
    std::shared_ptr<std::atomic<bool>> delay_cancel;
    std::shared_ptr<Stop> traffic_stop;
    std::shared_ptr<Stop> connections_stop;
    std::shared_ptr<Stop> logs_stop;
    bool logs_running = false;
    bool usage_running = false;
    bool command_running = false;
    bool delay_running = false;
};

// The script entrypoint. Returns -1 when the arguments are not a non-interactive
// subcommand; errors already printed to `err` return 1.
int run_cli(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err);
}  // namespace clash
