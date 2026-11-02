// Docker page state, worker plumbing and drawing. Private to this tool; page.hpp is public.
#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "api.hpp"
#include "cleanup.hpp"
#include "ui/input.hpp"
#include "ui/page.hpp"
#include "ui/widgets.hpp"
#include "vm.hpp"

namespace dock {
enum class PageId { Containers, Images, Volumes, Overview, Cleanup };
struct Data {
    std::vector<Container> containers;
    std::vector<Image> images;
    std::vector<Volume> volumes;
    Info info;
    Disk disk;
};
enum class ConfirmKind { StopDaemon, ProjectRestart };
struct Confirm {
    ConfirmKind kind = ConfirmKind::StopDaemon;
    std::string project;
    std::vector<std::string> ids;
};
// Fixed-size worker pool. Jobs are cancellable through the token they capture; the UI
// thread never blocks on a request.
class Workers {
public:
    explicit Workers(size_t threads = 3);
    ~Workers();
    Workers(const Workers&) = delete;
    Workers& operator=(const Workers&) = delete;
    void run(std::function<void()> job);
    // Waits until no job is queued or running. Only teardown uses it.
    void wait_idle();

private:
    std::mutex mutex_;
    std::condition_variable ready_;
    std::deque<std::function<void()>> jobs_;
    std::vector<std::thread> threads_;
    size_t busy_ = 0;
    bool stop_ = false;
};
class App : public tui::Page {
public:
    explicit App(std::optional<std::string> host);
    ~App() override;
    void attach(tui::Post post) override;
    void set_active(bool active) override;
    void draw(ftxui::Screen& screen, tui::Rect area) override;
    bool handle(const tui::InputEvent& event) override;
    std::optional<tui::TimePoint> next_deadline() const override;
    void tick() override;
    std::optional<std::pair<int, int>> cursor() const override;
    bool editing() const { return filtering || cleanup_flow.has_value() || confirm.has_value(); }

    // Update sinks, called on the UI thread. Public so the tests can drive the state machine.
    void apply_data(uint64_t epoch, Data data);
    void apply_data_error(uint64_t epoch, const std::string& reason);
    void apply_stats(uint64_t epoch, const std::string& id, std::optional<StatView> stat);
    void apply_message(const std::string& message);
    void apply_cleaned(cleanup::Report report);
    void apply_vm(vm::Inventory inventory);
    void apply_log(uint64_t epoch, const std::string& chunk);
    void apply_log_ended(uint64_t epoch, const std::string& id);
    void paste_text(const std::string& text);

    // State exposed for the doctest port of the Rust app tests.
    std::optional<Engine> engine;
    std::string init_error;
    PageId page = PageId::Containers;
    bool quit = false;
    size_t selected = 0;
    tui::TextInput filter;
    tui::TextInput filter_before;
    bool filtering = false;
    size_t sort = 0;
    std::vector<Container> containers;
    std::vector<Image> images;
    std::vector<Volume> volumes;
    Info info;
    Disk disk;
    std::map<std::string, StatView> stats;
    std::set<std::string> stats_pending;
    uint64_t api_epoch = 0;
    std::string message = "Docker 启动中…";
    std::optional<tui::TimePoint> message_until;
    bool online = false;
    std::optional<std::string> load_error;
    std::optional<Confirm> confirm;
    bool help = false;
    bool details = false;
    std::optional<std::string> logs;
    std::vector<std::string> log_lines;
    tui::TextInput log_filter;
    size_t log_scroll = 0;
    bool log_follow = true;
    std::set<std::string> picked;
    std::optional<cleanup::Flow> cleanup_flow;
    std::optional<cleanup::Report> cleanup_report;
    size_t report_scroll = 0;
    bool cleaning = false;
    vm::Inventory vm;
    bool vm_section = false;
    std::optional<vm::Row> vm_details;
    size_t vm_scroll = 0;
    bool stopped_by_user = false;
    // Worker bookkeeping, visible to tests so cancellation can be asserted.
    bool refresh_running = false;
    bool action_running = false;
    bool vm_running = false;
    bool log_running = false;
    bool exec_running = false;
    tui::TimePoint last_refresh;
    tui::TimePoint last_vm;

    // Selection helpers mirrored from the Rust implementation.
    std::optional<Container> selected_container() const;
    std::vector<const Container*> filtered_containers() const;
    std::vector<const Image*> filtered_images() const;
    std::vector<const Volume*> filtered_volumes() const;
    std::vector<std::string> ids() const;
    size_t len() const;
    std::optional<std::string> selected_id() const;
    void keep_selection(std::optional<std::string> id);
    void move_sel(int delta);
    void move_logs(int delta);
    void begin_filter();
    bool has_temporary_message() const;
    void refresh();
    void start_logs();
    void preview_cleanup(std::vector<cleanup::Entry> plan);
    void execute_cleanup(std::vector<cleanup::Entry> plan);
    void suspend_api_for_daemon_stop();
    void confirm_action();
    void confirm_project_restart();
    void exec_container();
    void copy_vm_path();
    std::vector<cleanup::Entry> cleanup_entries() const;
    std::vector<const vm::Row*> vm_rows() const;
    void action_key(const tui::Key& key);
    void mouse(const tui::InputEvent& event, int width, int height);
    void set_message(const std::string& text);
    void command(std::function<std::optional<std::string>()> job);
    void act(const std::string& what);
    void follow_logs(const std::string& id, bool history);
    void pause_hidden_vm();
    bool has_api_job() const { return refresh_running || log_running || vm_running || exec_running; }

private:
    void cancel_api(bool include_action);
    void start_vm();
    void enqueue_result(std::function<void()> job);
    void wake();
    void drain_results();
    bool current_epoch(uint64_t epoch) const;
    void draw_chrome(ftxui::Screen& screen, tui::Rect area);
    void draw_table(ftxui::Screen& screen, tui::Rect area, const std::string& label,
                    const std::vector<tui::Column>& columns, const std::vector<std::vector<std::string>>& cells);
    void draw_containers(ftxui::Screen& screen, tui::Rect area);
    void draw_images(ftxui::Screen& screen, tui::Rect area);
    void draw_volumes(ftxui::Screen& screen, tui::Rect area);
    void draw_overview(ftxui::Screen& screen, tui::Rect area);
    void draw_cleanup(ftxui::Screen& screen, tui::Rect area);
    void draw_logs(ftxui::Screen& screen, tui::Rect area);
    void draw_dialog(ftxui::Screen& screen, const std::string& title, const std::string& body, size_t scroll = 0);
    void draw_filter_line(ftxui::Screen& screen, int y, tui::Rect area, const tui::TextInput& input);
    void empty_state(ftxui::Screen& screen, tui::Rect area);
    void handle_mouse_rows(const tui::InputEvent& event);
    std::vector<std::pair<tui::Rect, size_t>> row_hits_;
    tui::Rect tabs_row_;
    tui::Rect body_area_;
    std::optional<std::pair<int, int>> cursor_;
    bool active_ = false;
    std::optional<std::string> host_request_;
    tui::Post post_;
    std::mutex post_mutex_;
    bool post_open_ = false;
    tui::Cancel api_cancel_ = std::make_shared<std::atomic<bool>>(false);
    tui::Cancel log_cancel_ = std::make_shared<std::atomic<bool>>(false);
    tui::Cancel vm_cancel_ = std::make_shared<std::atomic<bool>>(false);
    tui::Cancel action_cancel_ = std::make_shared<std::atomic<bool>>(false);
    tui::Cancel exec_cancel_ = std::make_shared<std::atomic<bool>>(false);
    Workers workers_{3};
    std::mutex results_mutex_;
    std::deque<std::function<void()>> results_;
};
std::vector<std::string> split_lines(std::string_view text);
std::string join_lines(const std::vector<std::string>& lines);
std::string compact_status(const std::string& status);
std::string compact_port_mappings(const Container& container);
std::string container_details(const Container& container);
std::string confirm_body(const Confirm& confirm);
std::vector<std::string> compose_project_ids(const std::vector<Container>& containers, const std::string& project);
bool api_update_is_current(uint64_t update_epoch, uint64_t current_epoch, bool stopped);
bool stopped_key_allowed(const tui::Key& key);
size_t table_click_index(size_t selected, size_t visible_rows, size_t clicked_row, size_t len);
std::string short_id(std::string_view id);
}  // namespace dock
