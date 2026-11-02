#include "app.hpp"

#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <format>
#include <limits>
#include <ftxui/screen/screen.hpp>
#include <stdexcept>

#include "ui/draw.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"
#include "ui/widgets.hpp"

extern char** environ;

namespace dock {
namespace {
using tui::Hint;
using tui::KeyCode;
using tui::Rect;
using tui::Style;
using Clock = std::chrono::steady_clock;
constexpr auto kRefresh = std::chrono::seconds(2);
constexpr auto kVmRefresh = std::chrono::seconds(30);
constexpr auto kMessageLife = std::chrono::seconds(5);
constexpr size_t kLogLines = 4000;
constexpr size_t kLogBytes = 4 * 1024 * 1024;
constexpr size_t kLogBuffer = 256 * 1024;
constexpr int kLogRedrawMs = 70;

bool is_matches(const std::string& query, const std::string& text) { return tui::match(query, text).has_value(); }
std::optional<std::string> project_of(const Container& container) {
    const auto it = container.labels.find(kComposeProject);
    if (it == container.labels.end()) return std::nullopt;
    return it->second;
}
std::string name_of(const Container& container) {
    if (container.names.empty()) return container.id;
    std::string name = container.names.front();
    while (!name.empty() && name.front() == '/') name.erase(name.begin());
    return name;
}
std::string state_label(const Volume& volume) {
    if (!volume.usage) return "未知";
    if (volume.usage->refs > 0) return "使用中";
    if (volume.usage->refs == 0) return "未使用";
    return "未知 / 保护";
}
std::string volume_size(const Volume& volume) {
    if (!volume.usage || volume.usage->size < 0) return "未知";
    return cleanup::bytes(static_cast<uint64_t>(volume.usage->size));
}
std::string short_bytes(uint64_t value) {
    constexpr uint64_t mib = 1024ull * 1024ull;
    constexpr uint64_t gib = 1024ull * mib;
    if (value >= gib) return std::format("{:.1f}G", static_cast<double>(value) / static_cast<double>(gib));
    if (value >= mib) return std::format("{}M", value / mib);
    if (value >= 1024) return std::format("{}K", value / 1024);
    return std::format("{}B", value);
}
std::string clean_bytes(std::optional<uint64_t> size) {
    std::string text = cleanup::bytes(size);
    // Rust's table cells use the same byte text with the trailing ".0" dropped.
    size_t at = 0;
    while ((at = text.find(".0 ", at)) != std::string::npos) {
        text.replace(at, 3, " ");
        at += 1;
    }
    return text;
}
std::string join(const std::vector<std::string>& values, const std::string& by) {
    std::string out;
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) out += by;
        out += values[i];
    }
    return out;
}
// Runs one fixed argv without a shell and waits for it. Used for systemctl and wl-copy-like helpers.
int run_wait(const std::vector<std::string>& args) {
    std::vector<std::string> storage = args;
    std::vector<char*> argv;
    for (std::string& arg : storage) argv.push_back(arg.data());
    argv.push_back(nullptr);
    pid_t pid = -1;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    const int spawned = posix_spawnp(&pid, storage.front().c_str(), &actions, nullptr, argv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    if (spawned != 0) return -1;
    int status = 0;
    while (::waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
// Starts and does not wait; kitty becomes the parent of the exec session.
bool spawn_detached(const std::vector<std::string>& args) {
    std::vector<std::string> storage = args;
    std::vector<char*> argv;
    for (std::string& arg : storage) argv.push_back(arg.data());
    argv.push_back(nullptr);
    pid_t pid = -1;
    const int spawned = posix_spawnp(&pid, storage.front().c_str(), nullptr, nullptr, argv.data(), environ);
    return spawned == 0;
}
}  // namespace

Workers::Workers(size_t threads) {
    for (size_t i = 0; i < threads; ++i) {
        threads_.emplace_back([this] {
            while (true) {
                std::function<void()> job;
                {
                    std::unique_lock lock(mutex_);
                    ready_.wait(lock, [this] { return stop_ || !jobs_.empty(); });
                    if (stop_ && jobs_.empty()) return;
                    job = std::move(jobs_.front());
                    jobs_.pop_front();
                    ++busy_;
                }
                try {
                    job();
                } catch (...) {
                }
                {
                    const std::lock_guard lock(mutex_);
                    --busy_;
                    if (jobs_.empty() && busy_ == 0) ready_.notify_all();
                }
            }
        });
    }
}
Workers::~Workers() {
    wait_idle();
    {
        const std::lock_guard lock(mutex_);
        stop_ = true;
    }
    ready_.notify_all();
    for (auto& thread : threads_) thread.join();
}
void Workers::run(std::function<void()> job) {
    {
        const std::lock_guard lock(mutex_);
        jobs_.push_back(std::move(job));
    }
    ready_.notify_one();
}
void Workers::wait_idle() {
    std::unique_lock lock(mutex_);
    ready_.wait(lock, [this] { return jobs_.empty() && busy_ == 0; });
}
std::string join_lines(const std::vector<std::string>& lines) { return join(lines, "\n"); }
std::string compact_status(const std::string& status) {
    std::string value = status;
    for (const auto& [from, to] : std::vector<std::pair<std::string, std::string>>{
             {" seconds", "s"}, {" second", "s"}, {" minutes", "m"}, {" minute", "m"},
             {" hours", "h"}, {" hour", "h"}, {" days", "d"}, {" day", "d"},
             {" weeks", "w"}, {" week", "w"}, {" months", "mo"}, {" month", "mo"},
             {" ago", ""}, {"Exited", "Exit"}}) {
        size_t at = 0;
        while ((at = value.find(from, at)) != std::string::npos) {
            value.replace(at, from.size(), to);
            at += to.size();
        }
    }
    return value;
}
std::string compact_port_mappings(const Container& container) {
    std::vector<std::string> out;
    for (const Port& port : container.ports) {
        if (!port.public_port) continue;
        out.push_back(std::format("{}>{}/{}", *port.public_port, port.private_port, port.kind));
    }
    return join(out, ",");
}
std::string container_details(const Container& container) {
    const std::string name = name_of(container);
    const std::string project = project_of(container).value_or("-");
    std::string ports;
    if (container.ports.empty()) {
        ports = "无";
    } else {
        std::vector<std::string> rows;
        for (const Port& port : container.ports) {
            if (port.public_port) {
                rows.push_back(std::format("{}:{} → :{}/{}", port.ip.value_or("*"), *port.public_port, port.private_port, port.kind));
            } else {
                rows.push_back(std::format("未发布 → :{}/{}", port.private_port, port.kind));
            }
        }
        ports = join(rows, "\n");
    }
    return std::format("名称：{}\nID：{}\nCompose 项目：{}\n镜像：{}\n状态：{} ({})\n端口映射：\n{}", name, container.id, project, container.image, container.status, container.state, ports);
}
std::string confirm_body(const Confirm& confirm) {
    if (confirm.kind == ConfirmKind::ProjectRestart) {
        return std::format("重启 Compose 项目 {} 中的 {} 个容器？\ny 确认 · Esc 取消", confirm.project, confirm.ids.size());
    }
    return "停止 Docker daemon 与 socket proxy？\n下次 Docker 请求会自动启动。\ny 确认 · Esc 取消";
}
std::vector<std::string> compose_project_ids(const std::vector<Container>& containers, const std::string& project) {
    std::vector<std::string> out;
    for (const Container& container : containers) {
        if (project_of(container) == project) out.push_back(container.id);
    }
    return out;
}
bool api_update_is_current(uint64_t update_epoch, uint64_t current_epoch, bool stopped) {
    return !stopped && update_epoch == current_epoch;
}
bool stopped_key_allowed(const tui::Key& key) {
    switch (key.code) {
        case KeyCode::Escape:
        case KeyCode::Up:
        case KeyCode::Down:
        case KeyCode::Left:
        case KeyCode::Right:
            return true;
        case KeyCode::Char:
            break;
        default:
            return false;
    }
    if (key.ctrl || key.alt) return false;
    return key.is(U'q') || key.is(U'?') || key.is(U's') || key.is(U'j') || key.is(U'k') ||
           key.is(U'o') || key.is(U'/') || (key.ch >= U'1' && key.ch <= U'5');
}
size_t table_click_index(size_t selected, size_t visible_rows, size_t clicked_row, size_t len) {
    if (len == 0 || visible_rows == 0) return 0;
    const size_t offset = selected + 1 > visible_rows ? selected + 1 - visible_rows : 0;
    return std::min(offset + clicked_row, len - 1);
}
std::string short_id(std::string_view id) {
    if (id.size() > 12) return std::string(id.substr(0, 12));
    return std::string(id);
}

App::App(std::optional<std::string> host) : vm(vm::Inventory::pending()) {
    // A page must not connect before it is first activated. Constructor only resolves the socket.
    ::signal(SIGPIPE, SIG_IGN);
    std::optional<std::string> requested = host;
    if (!requested) {
        if (const char* env = std::getenv("DOCKER_HOST"); env && *env) requested = std::string(env);
    }
    host_request_ = requested;
    try {
        engine = Engine::create(requested);
    } catch (const std::exception& error) {
        init_error = error.what();
        message = "Docker 不可用；检查配置后按 R 重试";
    }
    last_refresh = Clock::now() - std::chrono::seconds(5);
    last_vm = Clock::now() - std::chrono::seconds(31);
}
App::~App() {
    {
        const std::lock_guard lock(post_mutex_);
        post_open_ = false;
    }
    cancel_api(true);
    workers_.wait_idle();
}
void App::attach(tui::Post post) {
    post_ = std::move(post);
    const std::lock_guard lock(post_mutex_);
    post_open_ = true;
    active_ = true;
}
void App::enqueue_result(std::function<void()> job) {
    {
        const std::lock_guard lock(results_mutex_);
        results_.push_back(std::move(job));
    }
    wake();
}
void App::wake() {
    const std::lock_guard lock(post_mutex_);
    if (!post_open_ || !post_) return;
    // The posted closure captures nothing: worker state travels through results_.
    post_([] {});
}
void App::drain_results() {
    std::deque<std::function<void()>> jobs;
    {
        const std::lock_guard lock(results_mutex_);
        jobs.swap(results_);
    }
    for (auto& job : jobs) job();
}
void App::set_active(bool active) {
    active_ = active;
    {
        const std::lock_guard lock(post_mutex_);
        post_open_ = active;
    }
    if (!active) {
        // A confirmed mutation may finish; every read-only stream and request stops.
        cancel_api(false);
        refresh_running = false;
        vm_running = false;
        log_running = false;
        exec_running = false;
        stats_pending.clear();
    } else {
        last_refresh = Clock::now() - std::chrono::seconds(3);
        last_vm = Clock::now() - std::chrono::seconds(31);
        if (logs) follow_logs(*logs, false);
    }
}
void App::cancel_api(bool include_action) {
    *api_cancel_ = true;
    *log_cancel_ = true;
    *vm_cancel_ = true;
    *exec_cancel_ = true;
    api_cancel_ = std::make_shared<std::atomic<bool>>(false);
    log_cancel_ = std::make_shared<std::atomic<bool>>(false);
    vm_cancel_ = std::make_shared<std::atomic<bool>>(false);
    exec_cancel_ = std::make_shared<std::atomic<bool>>(false);
    if (include_action) {
        *action_cancel_ = true;
        action_cancel_ = std::make_shared<std::atomic<bool>>(false);
    }
}
bool App::current_epoch(uint64_t epoch) const { return api_update_is_current(epoch, api_epoch, stopped_by_user); }

std::optional<Container> App::selected_container() const {
    const auto rows = filtered_containers();
    if (selected < rows.size()) return *rows[selected];
    return std::nullopt;
}
std::vector<const Container*> App::filtered_containers() const {
    std::vector<const Container*> out;
    for (const Container& container : containers) {
        std::string name = container.names.empty() ? container.id : container.names.front();
        if (!is_matches(filter.str(), name + " " + container.image + " " + project_of(container).value_or(""))) continue;
        out.push_back(&container);
    }
    if (sort == 1) {
        std::stable_sort(out.begin(), out.end(), [](const Container* a, const Container* b) { return a->image < b->image; });
    } else if (sort == 2) {
        std::stable_sort(out.begin(), out.end(), [](const Container* a, const Container* b) { return a->status < b->status; });
    }
    return out;
}
std::vector<const Image*> App::filtered_images() const {
    std::vector<const Image*> out;
    for (const Image& image : images) {
        if (!is_matches(filter.str(), image.id + " " + join(image.tags, " "))) continue;
        out.push_back(&image);
    }
    return out;
}
std::vector<const Volume*> App::filtered_volumes() const {
    std::vector<const Volume*> out;
    for (const Volume& volume : volumes) {
        if (!is_matches(filter.str(), volume.name)) continue;
        out.push_back(&volume);
    }
    return out;
}
std::vector<std::string> App::ids() const {
    std::vector<std::string> out;
    switch (page) {
        case PageId::Containers:
            for (const Container* row : filtered_containers()) out.push_back(row->id);
            break;
        case PageId::Images:
            for (const Image* row : filtered_images()) out.push_back(row->id);
            break;
        case PageId::Volumes:
            for (const Volume* row : filtered_volumes()) out.push_back(row->name);
            break;
        case PageId::Overview:
            break;
        case PageId::Cleanup:
            if (vm_section) {
                for (const vm::Row* row : vm_rows()) out.push_back(row->key());
            } else {
                for (const cleanup::Entry& row : cleanup_entries()) out.push_back(row.key());
            }
            break;
    }
    return out;
}
size_t App::len() const { return ids().size(); }
std::optional<std::string> App::selected_id() const {
    switch (page) {
        case PageId::Containers: {
            const auto row = selected_container();
            return row ? std::optional<std::string>(row->id) : std::nullopt;
        }
        case PageId::Images: {
            const auto rows = filtered_images();
            return selected < rows.size() ? std::optional<std::string>(rows[selected]->id) : std::nullopt;
        }
        case PageId::Volumes: {
            const auto rows = filtered_volumes();
            return selected < rows.size() ? std::optional<std::string>(rows[selected]->name) : std::nullopt;
        }
        case PageId::Overview:
            return std::nullopt;
        case PageId::Cleanup:
            if (vm_section) {
                const auto rows = vm_rows();
                return selected < rows.size() ? std::optional<std::string>(rows[selected]->key()) : std::nullopt;
            }
            {
                const auto rows = cleanup_entries();
                return selected < rows.size() ? std::optional<std::string>(rows[selected].key()) : std::nullopt;
            }
    }
    return std::nullopt;
}
void App::keep_selection(std::optional<std::string> id) {
    selected = 0;
    if (!id) return;
    const auto rows = ids();
    const auto found = std::find(rows.begin(), rows.end(), *id);
    if (found != rows.end()) selected = static_cast<size_t>(found - rows.begin());
}
void App::move_sel(int delta) {
    const size_t count = len();
    if (count == 0) return;
    if (delta < 0) {
        const size_t step = static_cast<size_t>(-delta);
        selected = selected > step ? selected - step : 0;
    } else {
        selected = std::min(selected + static_cast<size_t>(delta), count - 1);
    }
}
void App::move_logs(int delta) {
    const std::string query = log_filter.str();
    size_t visible = 0;
    for (const std::string& line : log_lines) visible += is_matches(query, line) ? 1 : 0;
    const long long next = static_cast<long long>(log_scroll) + delta;
    const long long limit = static_cast<long long>(visible ? visible - 1 : 0);
    log_scroll = static_cast<size_t>(std::clamp<long long>(next, 0, limit));
    log_follow = log_scroll == 0;
}
void App::begin_filter() {
    filter_before = logs ? log_filter : filter;
    filtering = true;
}
bool App::has_temporary_message() const { return message_until && Clock::now() < *message_until; }
void App::set_message(const std::string& text) {
    message = text;
    message_until = Clock::now() + kMessageLife;
    last_refresh = Clock::now() - std::chrono::seconds(3);
}
void App::paste_text(const std::string& text) {
    if (cleanup_flow && cleanup_flow->stage == cleanup::Stage::Volumes) {
        cleanup_flow->input.paste(text);
    } else if (filtering) {
        const auto id = selected_id();
        if (logs) log_filter.paste(text);
        else filter.paste(text);
        keep_selection(id);
        log_scroll = 0;
    }
}
void App::refresh() {
    if (stopped_by_user || refresh_running || !engine) return;
    refresh_running = true;
    last_refresh = Clock::now();
    const uint64_t epoch = api_epoch;
    const tui::Cancel token = api_cancel_;
    const Engine current = *engine;
    workers_.run([this, current, epoch, token] {
        try {
            current.ping();
            Data data;
            data.containers = current.containers();
            data.images = current.images();
            data.volumes = current.volumes();
            data.info = current.info();
            data.disk = current.disk();
            merge_volume_usage(data.volumes, data.disk);
            enqueue_result([this, epoch, data = std::move(data)] { apply_data(epoch, data); });
        } catch (const std::exception& error) {
            const std::string reason = error.what();
            enqueue_result([this, epoch, reason] { apply_data_error(epoch, reason); });
        }
    });
}
void App::apply_data(uint64_t epoch, Data data) {
    if (!current_epoch(epoch)) return;
    refresh_running = false;
    const auto keep = selected_id();
    online = true;
    load_error.reset();
    if (!has_temporary_message()) message.clear();
    containers = std::move(data.containers);
    std::stable_sort(containers.begin(), containers.end(), [](const Container& a, const Container& b) {
        const auto left = project_of(a);
        const auto right = project_of(b);
        if (left != right) return left < right;
        const auto left_name = a.names.empty() ? std::nullopt : std::optional<std::string>(a.names.front());
        const auto right_name = b.names.empty() ? std::nullopt : std::optional<std::string>(b.names.front());
        return left_name < right_name;
    });
    images = std::move(data.images);
    volumes = std::move(data.volumes);
    info = std::move(data.info);
    disk = std::move(data.disk);
    std::set<std::string> eligible;
    for (const cleanup::Entry& entry : cleanup::entries(disk)) {
        if (entry.selectable()) eligible.insert(entry.key());
    }
    for (auto it = picked.begin(); it != picked.end();) {
        if (!eligible.contains(*it)) it = picked.erase(it);
        else ++it;
    }
    keep_selection(keep);
    const size_t count = len();
    selected = std::min(selected, count ? count - 1 : 0);
    if (!engine) return;
    const uint64_t current = api_epoch;
    const tui::Cancel token = api_cancel_;
    const Engine engine_copy = *engine;
    for (const Container& container : containers) {
        if (container.state != "running" || stats_pending.contains(container.id)) continue;
        stats_pending.insert(container.id);
        const std::string id = container.id;
        workers_.run([this, engine_copy, id, current, token] {
            try {
                const StatView view = engine_copy.stats(id);
                enqueue_result([this, current, id, view] { apply_stats(current, id, view); });
            } catch (const std::exception&) {
                enqueue_result([this, current, id] { apply_stats(current, id, std::nullopt); });
            }
        });
    }
}
void App::apply_data_error(uint64_t epoch, const std::string& reason) {
    if (!current_epoch(epoch)) return;
    refresh_running = false;
    if (has_temporary_message()) return;
    load_error = reason;
    message = online ? "Docker API 暂时不可用" : "Docker 连接失败；检查服务或 socket";
}
void App::apply_stats(uint64_t epoch, const std::string& id, std::optional<StatView> stat) {
    if (!current_epoch(epoch)) return;
    stats_pending.erase(id);
    if (stat) stats[id] = *stat;
}
void App::apply_message(const std::string& text) { set_message(text); }
void App::apply_cleaned(cleanup::Report report) {
    cleaning = false;
    message = std::format("清理完成 · {} 项失败 · Esc 关闭报告", report.failed);
    cleanup_report = std::move(report);
    report_scroll = 0;
    picked.clear();
    last_refresh = Clock::now() - std::chrono::seconds(3);
}
void App::apply_vm(vm::Inventory inventory) {
    vm_running = false;
    const bool keep = page == PageId::Cleanup && vm_section;
    const auto id = keep ? selected_id() : std::nullopt;
    vm = std::move(inventory);
    if (id) {
        const auto rows = vm_rows();
        const auto found = std::find_if(rows.begin(), rows.end(), [&](const vm::Row* row) { return row->key() == *id; });
        selected = found == rows.end() ? 0 : static_cast<size_t>(found - rows.begin());
    }
    const size_t count = len();
    selected = std::min(selected, count ? count - 1 : 0);
}
void App::apply_log(uint64_t epoch, const std::string& chunk) {
    if (!current_epoch(epoch)) return;
    const std::string query = log_filter.str();
    if (!log_follow) {
        size_t added = 0;
        for (const std::string& line : split_lines(chunk)) added += is_matches(query, line) ? 1 : 0;
        log_scroll += added;
    }
    for (std::string& line : split_lines(chunk)) log_lines.push_back(std::move(line));
    size_t bytes = 0;
    for (const std::string& line : log_lines) bytes += line.size();
    size_t discard = 0;
    while (log_lines.size() - discard > kLogLines || bytes > kLogBytes) {
        if (discard >= log_lines.size()) break;
        bytes -= log_lines[discard].size();
        ++discard;
    }
    if (discard > 0) log_lines.erase(log_lines.begin(), log_lines.begin() + static_cast<long>(discard));
    if (log_follow) {
        log_scroll = 0;
    } else {
        size_t visible = 0;
        for (const std::string& line : log_lines) visible += is_matches(query, line) ? 1 : 0;
        log_scroll = std::min(log_scroll, visible ? visible - 1 : 0);
    }
}
void App::apply_log_ended(uint64_t epoch, const std::string& id) {
    log_running = false;
    if (!current_epoch(epoch)) return;
    if (logs && *logs == id) {
        logs.reset();
        message = "日志流已结束";
    }
}
void App::start_vm() {
    if (vm_running) return;
    vm_running = true;
    last_vm = Clock::now();
    const tui::Cancel token = vm_cancel_;
    workers_.run([this, token] {
        vm::Inventory inventory = vm::collect(token);
        enqueue_result([this, inventory = std::move(inventory)]() mutable { apply_vm(std::move(inventory)); });
    });
}
void App::pause_hidden_vm() {
    if (!(page == PageId::Cleanup && vm_section)) {
        if (vm_running) {
            *vm_cancel_ = true;
            vm_cancel_ = std::make_shared<std::atomic<bool>>(false);
            vm_running = false;
        }
    }
}
void App::start_logs() {
    const auto container = selected_container();
    if (!container) return;
    const std::string display = container->names.empty() ? container->id : container->names.front();
    log_lines.clear();
    logs = container->id;
    log_filter.clear();
    message = "正在跟随 " + display + " 日志";
    log_follow = true;
    log_scroll = 0;
    follow_logs(container->id, true);
}
void App::follow_logs(const std::string& id, bool history) {
    *log_cancel_ = true;
    const tui::Cancel token = std::make_shared<std::atomic<bool>>(false);
    log_cancel_ = token;
    log_running = true;
    const uint64_t epoch = api_epoch;
    const Engine current = *engine;
    workers_.run([this, current, id, history, token, epoch] {
        std::string buffer;
        std::vector<std::string> pending;
        auto last_post = Clock::now() - std::chrono::milliseconds(kLogRedrawMs);
        bool tty = false;
        bool truncated = false;
        const auto flush = [&] {
            if (pending.empty()) return;
            const std::string chunk = join_lines(pending);
            pending.clear();
            enqueue_result([this, epoch, chunk] { apply_log(epoch, chunk); });
            last_post = Clock::now();
        };
        try {
            tty = current.inspect_tty(id);
            const long status = current.logs(id, history ? 500 : 0, [&](std::string_view data) {
                if (*token) return false;
                buffer.append(data);
                if (cap_log_buffer(buffer, kLogBuffer) && !truncated) {
                    truncated = true;
                    pending.push_back("[日志缓冲超过 256 KiB，已截断]");
                }
                std::vector<std::string> lines = tty ? drain_raw_log_lines(buffer) : drain_log_frames(buffer);
                for (std::string& line : lines) pending.push_back(std::move(line));
                if (!pending.empty() && Clock::now() - last_post >= std::chrono::milliseconds(kLogRedrawMs)) flush();
                return true;
            });
            flush();
            if (status < 200 || status >= 300) {
                enqueue_result([this] { apply_message("读取日志失败"); });
            }
        } catch (const std::exception& error) {
            const std::string reason = error.what();
            enqueue_result([this, reason] { apply_message(reason); });
        }
        enqueue_result([this, epoch, id] { apply_log_ended(epoch, id); });
    });
}
void App::command(std::function<std::optional<std::string>()> job) {
    if (action_running) {
        message = "操作正在进行";
        return;
    }
    action_running = true;
    const uint64_t epoch = api_epoch;
    const tui::Cancel token = action_cancel_;
    workers_.run([this, job = std::move(job), epoch, token] {
        std::optional<std::string> result;
        try {
            result = job();
        } catch (const std::exception& error) {
            result = std::string(error.what());
        }
        const std::string text = result ? *result : "操作完成，正在刷新";
        enqueue_result([this, epoch, text] {
            if (!current_epoch(epoch)) return;
            action_running = false;
            set_message(text);
        });
    });
}
void App::suspend_api_for_daemon_stop() {
    stopped_by_user = true;
    ++api_epoch;
    online = false;
    filtering = false;
    confirm.reset();
    logs.reset();
    cancel_api(true);
    refresh_running = false;
    action_running = false;
    vm_running = false;
    log_running = false;
    exec_running = false;
    stats_pending.clear();
    message = "正在停止 Docker；下次连接会自动启动。";
}
void App::confirm_action() {
    if (!confirm) return;
    const Confirm chosen = *confirm;
    confirm.reset();
    if (chosen.kind == ConfirmKind::ProjectRestart) {
        const std::vector<std::string> ids = chosen.ids;
        command([this, ids]() -> std::optional<std::string> {
            const Engine current = *engine;
            for (const std::string& id : ids) current.restart(id);
            return std::nullopt;
        });
        return;
    }
    const bool can_stop = engine && engine->can_stop_local_daemon;
    if (!can_stop) {
        message = "自定义 DOCKER_HOST 不能通过本地 systemd units 停止";
        return;
    }
    suspend_api_for_daemon_stop();
    command([this]() -> std::optional<std::string> {
        const int status = run_wait({"systemctl", "--user", "stop", "docker.service", "docker-proxy.service"});
        if (status == 0) return std::string("Docker 已停止；下次连接会自动启动。按 s 恢复查看");
        return std::string("停止服务失败");
    });
}
void App::act(const std::string& what) {
    const auto container = selected_container();
    if (!container) return;
    const Engine current = *engine;
    const std::string id = container->id;
    const bool running = container->state == "running";
    const auto project = project_of(*container);
    if (what == "s") {
        command([this, current, id, running]() -> std::optional<std::string> {
            if (running) current.stop(id);
            else current.start(id);
            return std::nullopt;
        });
    } else if (what == "r") {
        command([this, current, id]() -> std::optional<std::string> {
            current.restart(id);
            return std::nullopt;
        });
    } else if (what == "p") {
        if (!project) {
            message = "所选容器没有 Compose 项目标签";
            return;
        }
        std::vector<std::pair<std::string, bool>> rows;
        for (const Container& row : containers) {
            if (project_of(row) == project) rows.emplace_back(row.id, row.state == "running");
        }
        const bool stop_project = std::all_of(rows.begin(), rows.end(), [](const auto& row) { return row.second; });
        std::vector<std::string> targets;
        for (const auto& [row_id, is_running] : rows) {
            if (is_running == stop_project) targets.push_back(row_id);
        }
        const std::string name = *project;
        command([this, current, targets, stop_project, name]() -> std::optional<std::string> {
            for (const std::string& target : targets) {
                if (stop_project) current.stop(target);
                else current.start(target);
            }
            enqueue_result([this, name] { apply_message(std::format("Compose 项目 {} 操作完成", name)); });
            return std::nullopt;
        });
    }
}
void App::confirm_project_restart() {
    const auto container = selected_container();
    if (!container) return;
    const auto project = project_of(*container);
    if (!project) {
        message = "所选容器没有 Compose 项目标签";
        return;
    }
    confirm = Confirm{ConfirmKind::ProjectRestart, *project, compose_project_ids(containers, *project)};
}
void App::exec_container() {
    const auto container = selected_container();
    if (!container || !engine) return;
    const std::string name = name_of(*container);
    const Engine current = *engine;
    const std::string id = container->id;
    exec_running = true;
    const tui::Cancel token = exec_cancel_;
    workers_.run([this, current, id, name, token] {
        const bool bash = current.exec_has_bash(id);
        std::vector<std::string> args{"kitty", "--class=mayon-docker-exec", "docker", "--host", current.host, "exec", "-it", name, bash ? "bash" : "sh"};
        const bool ok = spawn_detached(args);
        enqueue_result([this, name, ok] {
            exec_running = false;
            set_message(ok ? std::format("已在 Kitty 中打开 {} 的交互 shell", name) : "无法启动 Kitty/docker CLI");
        });
    });
}
void App::copy_vm_path() {
    std::optional<std::string> path;
    if (vm_details) path = vm_details->path;
    else {
        const auto rows = vm_rows();
        if (selected < rows.size()) path = rows[selected]->path;
    }
    if (!path) {
        message = "此项没有本地文件路径";
        return;
    }
    command([this, path = *path]() -> std::optional<std::string> {
        vm::copy_path(path);
        return std::string("已复制完整 VM 路径；未读取或修改文件");
    });
}
std::vector<cleanup::Entry> App::cleanup_entries() const {
    std::vector<cleanup::Entry> out;
    for (const cleanup::Entry& entry : cleanup::entries(disk)) {
        if (!is_matches(filter.str(), std::format("{} {} {}", cleanup::label(entry.kind), entry.id, entry.name))) continue;
        out.push_back(entry);
    }
    return out;
}
std::vector<const vm::Row*> App::vm_rows() const {
    std::vector<const vm::Row*> out;
    for (const vm::Row& row : vm.rows) {
        const std::string text = row.uri + " " + row.owner + " " + row.kind + " " + row.path.value_or("") + " " + row.note;
        if (!is_matches(filter.str(), text)) continue;
        out.push_back(&row);
    }
    return out;
}
void App::preview_cleanup(std::vector<cleanup::Entry> plan) {
    if (action_running) {
        message = "操作正在进行，完成后再预览";
        return;
    }
    cleanup_flow = cleanup::Flow::create(std::move(plan));
    if (!cleanup_flow) message = "没有可清理的选择；运行中、被引用或引用未知的资源已锁定";
}
void App::execute_cleanup(std::vector<cleanup::Entry> plan) {
    cleaning = true;
    message = "正在清理已确认清单…";
    const Engine current = *engine;
    const tui::Cancel token = action_cancel_;
    workers_.run([this, current, plan = std::move(plan), token] {
        cleanup::Report report = cleanup::execute(current, plan);
        enqueue_result([this, report = std::move(report)]() mutable { apply_cleaned(std::move(report)); });
    });
}
void App::action_key(const tui::Key& key) {
    if (!engine) {
        if (key.is(U'R')) {
            init_error.clear();
            try {
                engine = Engine::create(host_request_);
            } catch (const std::exception& error) {
                init_error = error.what();
            }
        } else if (key.is(U'q') || key.code == KeyCode::Escape) {
            quit = true;
        }
        return;
    }
    if (vm_details) {
        if (key.code == KeyCode::Escape) vm_details.reset();
        else if (key.is(U'j') || key.code == KeyCode::Down) ++vm_scroll;
        else if (key.is(U'k') || key.code == KeyCode::Up) vm_scroll = vm_scroll > 0 ? vm_scroll - 1 : 0;
        else if (key.is(U'y')) copy_vm_path();
        return;
    }
    if (cleanup_report) {
        if (key.code == KeyCode::Escape || key.is(U'q')) cleanup_report.reset();
        else if (key.is(U'j') || key.code == KeyCode::Down) ++report_scroll;
        else if (key.is(U'k') || key.code == KeyCode::Up) report_scroll = report_scroll > 0 ? report_scroll - 1 : 0;
        return;
    }
    if (cleanup_flow) {
        if (key.code == KeyCode::Escape) {
            cleanup_flow.reset();
        } else if (auto plan = cleanup_flow->handle_key(key)) {
            cleanup_flow.reset();
            execute_cleanup(std::move(*plan));
        }
        return;
    }
    if (cleaning) {
        if (key.is(U'q')) message = "清理执行中，请等待报告";
        return;
    }
    if (confirm) {
        if (key.code == KeyCode::Escape || key.is(U'n')) confirm.reset();
        else if (key.is(U'y')) confirm_action();
        return;
    }
    if (help) {
        if (key.code == KeyCode::Escape || key.is(U'?')) help = false;
        return;
    }
    if (filtering) {
        const auto id = selected_id();
        bool changed = false;
        if (key.code == KeyCode::Escape) {
            if (logs) log_filter = filter_before;
            else filter = filter_before;
            filtering = false;
            changed = true;
        } else if (key.code == KeyCode::Enter) {
            filtering = false;
        } else if (key.code == KeyCode::Down) {
            if (logs) move_logs(-1);
            else move_sel(1);
        } else if (key.code == KeyCode::Up) {
            if (logs) move_logs(1);
            else move_sel(-1);
        } else if (key.code == KeyCode::PageDown) {
            if (logs) move_logs(-10);
            else move_sel(10);
        } else if (key.code == KeyCode::PageUp) {
            if (logs) move_logs(10);
            else move_sel(-10);
        } else {
            changed = logs ? log_filter.handle(key) : filter.handle(key);
        }
        if (changed) {
            keep_selection(id);
            log_scroll = 0;
        }
        return;
    }
    if (key.ctrl || key.alt) return;
    if (details) {
        if (key.code == KeyCode::Escape) details = false;
        return;
    }
    const bool vm_readonly = page == PageId::Cleanup &&
        (key.code == KeyCode::Tab || key.is(U'v') ||
         (vm_section && (key.code == KeyCode::Enter || key.is(U'y') || key.is(U'r') || key.is(U' ') || key.is(U'd'))));
    if (stopped_by_user && !stopped_key_allowed(key) && !vm_readonly) {
        message = "Docker daemon 已手动停止；按 s 重新连接";
        return;
    }
    if (logs) {
        if (key.code == KeyCode::Escape && !log_filter.empty()) {
            log_filter.clear();
            log_scroll = 0;
        } else if (key.code == KeyCode::Escape || key.is(U'q')) {
            logs.reset();
            if (log_running) {
                *log_cancel_ = true;
                log_cancel_ = std::make_shared<std::atomic<bool>>(false);
                log_running = false;
            }
        } else if (key.is(U'j') || key.code == KeyCode::Down) {
            move_logs(-1);
        } else if (key.is(U'k') || key.code == KeyCode::Up) {
            move_logs(1);
        } else if (key.code == KeyCode::PageDown) {
            move_logs(-10);
        } else if (key.code == KeyCode::PageUp) {
            move_logs(10);
        } else if (key.is(U'g') || key.code == KeyCode::Home) {
            move_logs(std::numeric_limits<int>::max());
        } else if (key.is(U'G')) {
            log_follow = true;
            log_scroll = 0;
        } else if (key.is(U'/')) {
            begin_filter();
        }
        return;
    }
    if (page == PageId::Cleanup) {
        if (key.code == KeyCode::Tab || key.is(U'v')) {
            vm_section = !vm_section;
            selected = 0;
            return;
        }
        if (vm_section) {
            if (key.code == KeyCode::Enter) {
                const auto rows = vm_rows();
                vm_details = selected < rows.size() ? std::optional<vm::Row>(*rows[selected]) : std::nullopt;
                vm_scroll = 0;
                return;
            }
            if (key.is(U'y')) {
                copy_vm_path();
                return;
            }
            if (key.is(U'r')) {
                last_vm = Clock::now() - std::chrono::seconds(31);
                return;
            }
            if (key.is(U' ') || key.is(U'd')) {
                message = "VM 严格只读；不提供虚拟机、镜像、快照或 ISO 删除";
                return;
            }
        }
    }
    switch (key.code) {
        case KeyCode::Char:
            break;
        case KeyCode::Enter:
            if (page == PageId::Containers && selected_container()) {
                details = true;
                return;
            }
            if (page == PageId::Cleanup) {
                preview_cleanup(cleanup::selected(cleanup::entries(disk), picked));
                return;
            }
            return;
        case KeyCode::Escape: {
            const auto id = selected_id();
            filter.clear();
            keep_selection(id);
            return;
        }
        case KeyCode::PageDown:
            move_sel(10);
            return;
        case KeyCode::PageUp:
            move_sel(-10);
            return;
        case KeyCode::Home:
            selected = 0;
            return;
        case KeyCode::End:
            selected = len() ? len() - 1 : 0;
            return;
        case KeyCode::Down:
            move_sel(1);
            return;
        case KeyCode::Up:
            move_sel(-1);
            return;
        default:
            return;
    }
    if (key.is(U'q')) {
        quit = true;
    } else if (key.is(U'?')) {
        help = true;
    } else if (key.is(U'1')) {
        page = PageId::Containers;
        selected = 0;
    } else if (key.is(U'2')) {
        page = PageId::Images;
        selected = 0;
    } else if (key.is(U'3')) {
        page = PageId::Volumes;
        selected = 0;
    } else if (key.is(U'4')) {
        page = PageId::Overview;
        selected = 0;
    } else if (key.is(U'5')) {
        page = PageId::Cleanup;
        selected = 0;
    } else if (key.is(U' ') && page == PageId::Cleanup) {
        const auto rows = cleanup_entries();
        if (selected < rows.size()) {
            const cleanup::Entry& entry = rows[selected];
            if (entry.selectable()) {
                const std::string id = entry.key();
                if (!picked.erase(id)) picked.insert(id);
            } else {
                message = entry.blocked.value_or("");
            }
        }
    } else if ((key.code == KeyCode::Enter || key.is(U'd')) && page == PageId::Cleanup) {
        preview_cleanup(cleanup::selected(cleanup::entries(disk), picked));
    } else if (key.code == KeyCode::Escape) {
        const auto id = selected_id();
        filter.clear();
        keep_selection(id);
    } else if (key.code == KeyCode::PageDown) {
        move_sel(10);
    } else if (key.code == KeyCode::PageUp) {
        move_sel(-10);
    } else if (key.is(U'g') || key.code == KeyCode::Home) {
        selected = 0;
    } else if (key.is(U'G') || key.code == KeyCode::End) {
        selected = len() ? len() - 1 : 0;
    } else if (key.is(U'j') || key.code == KeyCode::Down) {
        move_sel(1);
    } else if (key.is(U'k') || key.code == KeyCode::Up) {
        move_sel(-1);
    } else if (key.is(U'/')) {
        begin_filter();
    } else if (key.is(U'o')) {
        const auto id = selected_id();
        sort = (sort + 1) % 3;
        keep_selection(id);
    } else if (key.is(U's') && stopped_by_user) {
        stopped_by_user = false;
        ++api_epoch;
        message = "正在重新连接 Docker…";
        refresh();
    } else if (key.is(U's') && page == PageId::Containers) {
        act("s");
    } else if (key.is(U'r') && page == PageId::Containers) {
        act("r");
    } else if (key.is(U'R') && page == PageId::Containers) {
        confirm_project_restart();
    } else if (key.is(U'p') && page == PageId::Containers) {
        act("p");
    } else if (key.is(U'l') && page == PageId::Containers) {
        start_logs();
    } else if (key.is(U'e') && page == PageId::Containers) {
        exec_container();
    } else if (key.is(U'd')) {
        const auto id = selected_id();
        if (id) {
            std::optional<cleanup::Kind> kind;
            if (page == PageId::Containers) kind = cleanup::Kind::Container;
            else if (page == PageId::Images) kind = cleanup::Kind::Image;
            else if (page == PageId::Volumes) kind = cleanup::Kind::Volume;
            std::vector<cleanup::Entry> plan;
            for (const cleanup::Entry& entry : cleanup::entries(disk)) {
                if (kind && entry.kind == *kind && entry.id == *id && entry.selectable()) plan.push_back(entry);
            }
            preview_cleanup(std::move(plan));
        }
    } else if (key.is(U'S')) {
        if (engine && engine->can_stop_local_daemon) {
            confirm = Confirm{ConfirmKind::StopDaemon, {}, {}};
        } else {
            message = "自定义 DOCKER_HOST 不能通过本地 systemd units 停止";
        }
    }
}
bool App::handle(const tui::InputEvent& event) {
    if (event.type == tui::InputEvent::Type::Key) {
        if (event.key.ctrl && event.key.ch == U'c') {
            quit = true;
            return true;
        }
        const std::string before = message;
        action_key(event.key);
        if (message != before) message_until = Clock::now() + kMessageLife;
        pause_hidden_vm();
        return quit;
    }
    if (event.type == tui::InputEvent::Type::Paste) {
        paste_text(event.paste);
        return false;
    }
    if (event.type == tui::InputEvent::Type::MouseClick || event.type == tui::InputEvent::Type::WheelUp ||
        event.type == tui::InputEvent::Type::WheelDown) {
        mouse(event, 0, 0);
    }
    return false;
}
void App::handle_mouse_rows(const tui::InputEvent& event) {
    for (const auto& [rect, index] : row_hits_) {
        if (!rect.contains(event.x, event.y)) continue;
        selected = std::min(index, len() ? len() - 1 : 0);
        return;
    }
}
void App::mouse(const tui::InputEvent& event, int, int) {
    if (confirm || help || details || filtering || cleanup_flow || cleaning || vm_details) return;
    if (cleanup_report) {
        if (event.type == tui::InputEvent::Type::WheelDown) report_scroll += 3;
        else if (event.type == tui::InputEvent::Type::WheelUp) report_scroll = report_scroll > 3 ? report_scroll - 3 : 0;
        return;
    }
    if (event.type == tui::InputEvent::Type::WheelDown) {
        if (logs) move_logs(-3);
        else move_sel(1);
        return;
    }
    if (event.type == tui::InputEvent::Type::WheelUp) {
        if (logs) move_logs(3);
        else move_sel(-1);
        return;
    }
    if (event.type != tui::InputEvent::Type::MouseClick) return;
    if (tabs_row_.contains(event.x, event.y)) {
        static const std::vector<std::string> names{"容器", "镜像", "卷", "概览", "空间"};
        if (const auto index = tui::tab_at(event.x, tabs_row_.x + 1, names)) {
            static const std::vector<PageId> pages{PageId::Containers, PageId::Images, PageId::Volumes, PageId::Overview, PageId::Cleanup};
            page = pages[*index];
            selected = 0;
        }
        return;
    }
    handle_mouse_rows(event);
}
std::optional<tui::TimePoint> App::next_deadline() const {
    if (!active_) return std::nullopt;
    if (!engine) return message_until;
    std::optional<tui::TimePoint> deadline;
    if (!stopped_by_user && !refresh_running) deadline = last_refresh + kRefresh;
    if (page == PageId::Cleanup && vm_section && !vm_running) {
        const auto vm_deadline = last_vm + kVmRefresh;
        if (!deadline || vm_deadline < *deadline) deadline = vm_deadline;
    }
    if (message_until && (!deadline || *message_until < *deadline)) deadline = *message_until;
    return deadline;
}
void App::tick() {
    drain_results();
    if (!active_) return;
    if (!engine) {
        if (message_until && Clock::now() >= *message_until) {
            message.clear();
            message_until.reset();
        }
        return;
    }
    pause_hidden_vm();
    if (message_until && Clock::now() >= *message_until) {
        message.clear();
        message_until.reset();
    }
    if (page == PageId::Cleanup && vm_section && Clock::now() - last_vm >= kVmRefresh && !vm_running) start_vm();
    if (!stopped_by_user && Clock::now() - last_refresh >= kRefresh) refresh();
}
std::optional<std::pair<int, int>> App::cursor() const { return cursor_; }

namespace {
tui::Column column(std::string title, int width, bool right = false) { return tui::Column{std::move(title), width, right}; }
int pct_width(int usable, int percent) { return std::max(4, usable * percent / 100 - 1); }
void draw_input_at(ftxui::Screen& screen, int x, int y, int width, const tui::TextInput& input, std::optional<std::pair<int, int>>& cursor) {
    if (width <= 1) return;
    const std::string text = input.str();
    const std::string before = input.before_cursor();
    // Scroll horizontally so the cursor stays visible.
    int skip = 0;
    const auto units = tui::decode(text);
    const auto head = tui::decode(before);
    int used = tui::width_of(before);
    while (used >= width - 1 && static_cast<size_t>(skip) < head.size()) {
        const std::string one = tui::encode(std::u32string_view(head).substr(static_cast<size_t>(skip), 1));
        used -= tui::width_of(one);
        ++skip;
    }
    const int drawn = tui::put(screen, x, y, tui::clip(tui::encode(std::u32string_view(units).substr(static_cast<size_t>(skip))), width), Style{tui::kBrightFg}, width);
    (void)drawn;
    cursor = std::make_pair(std::min(x + used, x + width - 1), y);
}
}  // namespace

void App::draw(ftxui::Screen& screen, tui::Rect area) {
    cursor_.reset();
    row_hits_.clear();
    draw_chrome(screen, area);
    if (!engine) {
        const std::string text = init_error.empty() ? "Docker 不可用" : init_error;
        int y = body_area_.y + 2;
        for (const std::string& line : tui::wrap(safe(text), std::max(body_area_.width - 4, 1), 6)) {
            tui::put(screen, body_area_.x + 2, y++, line, Style{tui::kRed}, body_area_.width - 4);
        }
        tui::put(screen, body_area_.x + 2, y + 1, "检查 DOCKER_HOST / XDG_RUNTIME_DIR；不会回落到其它 daemon。", Style{tui::kMuted}, body_area_.width - 4);
        return;
    }
    if (logs) {
        draw_logs(screen, body_area_);
        return;
    }
    if (vm_details) {
        draw_dialog(screen, "VM 详情 · 严格只读 · j/k 滚动 · Esc 返回", vm_details->details(), vm_scroll);
        return;
    }
    if (cleanup_flow) {
        const int room = std::min(screen.dimx() - 6, 96);
        auto lines = tui::wrap(safe(cleanup_flow->body()), room, 100000);
        const int height = std::min<int>(screen.dimy() - 2, static_cast<int>(lines.size()) + 5);
        const tui::Rect dialog = tui::centered(screen.dimx(), screen.dimy(), std::min(screen.dimx() - 2, room + 4), height);
        tui::fill(screen, dialog, tui::kSurface);
        tui::box(screen, dialog, " 清理 · Esc 取消 ", false, tui::kSurface);
        int y = dialog.y + 2;
        int input_row = -1;
        for (size_t i = 0; i < lines.size() && y < dialog.y + dialog.height - 1; ++i, ++y) {
            if (lines[i] == "输入：") input_row = y + 1;
            tui::put(screen, dialog.x + 3, y, lines[i], Style{tui::kFg, tui::kSurface}, dialog.width - 6);
        }
        if (cleanup_flow->stage == cleanup::Stage::Volumes) {
            if (input_row < 0) input_row = y;
            if (input_row < dialog.y + dialog.height - 1) {
                draw_input_at(screen, dialog.x + 3, input_row, dialog.width - 6, cleanup_flow->input, cursor_);
            }
        }
        return;
    }
    if (cleanup_report) {
        draw_dialog(screen, " 清理报告 · j/k 滚动 · Esc 关闭 ", cleanup_report->body(), report_scroll);
        return;
    }
    switch (page) {
        case PageId::Containers: draw_containers(screen, body_area_); break;
        case PageId::Images: draw_images(screen, body_area_); break;
        case PageId::Volumes: draw_volumes(screen, body_area_); break;
        case PageId::Overview: draw_overview(screen, body_area_); break;
        case PageId::Cleanup: draw_cleanup(screen, body_area_); break;
    }
    if (filtering) {
        const int row = screen.dimy() - 2;
        draw_filter_line(screen, row, tui::Rect{0, row, screen.dimx(), 1}, logs ? log_filter : filter);
    }
    if (help) {
        tui::draw_help(screen, " 帮助 · ? / Esc 关闭 ", {
            "1-5  切页 · j/k 或方向键选择 · / 过滤",
            "Enter  查看容器完整镜像、状态与 IP 端口详情",
            "s  启动/停止容器 · r 单容器重启 · p 项目启停 · R 重启整个 Compose 项目",
            "l  跟随日志 · 日志内 j/k 滚动 / 过滤",
            "e  在新 Kitty 中进入容器 · d 删除并确认",
            "5  Docker + VM 空间：Tab/v 切分区",
            "VM  Enter 完整路径/详情 · y 复制路径 · r 刷新",
            "VM、镜像、快照、孤立候选和 ISO 均严格只读",
            "Docker  Space 多选 · Enter/d 冻结准确清单预览",
            "j/k 看完每项 → y 二次确认 → y 执行",
            "卷默认不选；需另行输入 DELETE 与完整卷名，数据不可恢复",
            "清理前重新验证引用；运行中容器与被引用镜像、卷不可选",
            "S  停止 Docker 与代理服务 · s 恢复连接",
            "q  退出 · ? 关闭帮助",
        });
    }
    if (details) {
        if (const auto container = selected_container()) {
            draw_dialog(screen, " 容器详情 · Esc 关闭 ", container_details(*container));
        }
    }
    if (confirm) tui::draw_confirm(screen, " 确认操作 ", confirm_body(*confirm));
}
void App::draw_chrome(ftxui::Screen& screen, tui::Rect area) {
    if (area.height <= 0) {
        body_area_ = area;
        return;
    }
    const Style bright{tui::kBrightFg};
    const Style muted{tui::kMuted};
    const std::string label = page == PageId::Cleanup ? "Docker + VM" : "Docker";
    int x = tui::put(screen, area.x + 1, area.y, label, Style{tui::kBlue, {}, false, true}, area.width - 2) + 2;
    const std::string state = !engine ? "不可用" : stopped_by_user ? "已停止" : online ? "运行" : "启动中";
    const std::string detail = !engine ? "未配置 socket" : stopped_by_user ? "s 重新连接" : online ? info.version : "等待 daemon";
    x = tui::put(screen, x, area.y, safe(std::format("· {} · {}", state, detail)), muted, std::max(area.x + area.width - x - 1, 0));
    (void)bright;
    if (area.height >= 2) {
        static const std::vector<std::string> names{"容器", "镜像", "卷", "概览", "空间"};
        const size_t index = static_cast<size_t>(page);
        tui::draw_tabs(screen, area.x + 1, area.y + 1, names, index);
        tabs_row_ = tui::Rect{area.x, area.y + 1, area.width, 1};
    }
    const int footer = area.y + std::max(area.height - 2, 1);
    std::vector<tui::Hint> hints;
    if (!engine) {
        hints = {{"R", "重试"}, {"q/Esc", "退出"}};
    } else if (logs) {
        hints = {{"j/k", "滚动"}, {"G", "跟随"}, {"/", "过滤"}, {"Esc", "返回"}};
    } else if (page == PageId::Cleanup && vm_section) {
        hints = {{"Tab", "Docker/VM"}, {"Enter", "详情"}, {"y", "复制路径"}, {"/", "过滤"}, {"r", "刷新"}, {"?", "帮助"}, {"q", "退出"}};
    } else if (page == PageId::Cleanup) {
        hints = {{"Tab", "Docker/VM"}, {"Space", "多选"}, {"Enter", "预览"}, {"j/k", "选择"}, {"/", "过滤"}, {"?", "帮助"}, {"q", "退出"}};
    } else {
        hints = {{"o", "排序"}, {"j/k", "选择"}, {"Enter", "详情"}, {"1-5", "页签"}, {"/", "过滤"}, {"s", "启停"},
                 {"r", "重启"}, {"p", "项目启停"}, {"R", "项目重启"}, {"l", "日志"}, {"e", "exec"}, {"d", "删除"},
                 {"?", "帮助"}, {"q", "退出"}};
    }
    tui::put_hints(screen, area.x + 1, footer, area.width - 2, hints);
    if (!message.empty()) {
        tui::put(screen, area.x + 1, area.y + area.height - 1, tui::clip(safe(message), area.width - 2), Style{tui::kBlue}, area.width - 2);
    }
    body_area_ = tui::Rect{area.x, area.y + 2, area.width, std::max(area.height - 4, 0)};
}
void App::draw_table(ftxui::Screen& screen, tui::Rect area, const std::string& label, const std::vector<tui::Column>& columns,
                     const std::vector<std::vector<std::string>>& cells) {
    if (area.width <= 2 || area.height <= 0) return;
    tui::put(screen, area.x + 1, area.y, tui::clip(label, area.width - 2), Style{tui::kBrightFg}, area.width - 2);
    if (area.height < 2) return;
    const tui::Rect header{area.x, area.y + 1, area.width, 1};
    tui::draw_table_header(screen, header, columns);
    const int viewport = area.height - 2;
    if (cells.empty()) {
        empty_state(screen, tui::Rect{area.x + 2, area.y + 2, area.width - 4, std::max(viewport, 0)});
        return;
    }
    const size_t count = cells.size();
    const size_t chosen = std::min(selected, count - 1);
    const size_t offset = tui::scroll_to(chosen, chosen >= static_cast<size_t>(viewport) ? chosen - static_cast<size_t>(viewport) + 1 : 0,
                                         static_cast<size_t>(std::max(viewport, 0)), count);
    for (int row = 0; row < viewport; ++row) {
        const size_t index = offset + static_cast<size_t>(row);
        if (index >= count) break;
        const tui::Rect rect{area.x, area.y + 2 + row, area.width, 1};
        std::vector<std::string> cleaned = cells[index];
        for (std::string& cell : cleaned) cell = safe(cell);
        tui::draw_table_row(screen, rect, columns, cleaned, index == chosen);
        row_hits_.emplace_back(rect, index);
    }
    tui::put_scroll(screen, area.x + area.width - 1, area.y + 2, viewport, chosen, count);
}
void App::empty_state(ftxui::Screen& screen, tui::Rect area) {
    std::string text;
    uint32_t colour = tui::kMuted;
    if (page == PageId::Cleanup && vm_section) {
        text = "暂无 VM 项目 · r 刷新 · Tab 返回 Docker";
    } else if (load_error) {
        text = *load_error + " · 检查 Docker socket；自动重试中";
        colour = tui::kRed;
    } else if (!online) {
        text = "正在连接 Docker · 可用 1–5 切换子页";
        colour = tui::kBlue;
    } else {
        text = "无匹配项 · Esc 清除过滤；1–5 切换子页";
    }
    int y = area.y + 1;
    for (const std::string& line : tui::wrap(text, std::max(area.width - 2, 1), 4)) {
        tui::put(screen, area.x + 1, y++, line, Style{colour}, area.width - 2);
    }
}
void App::draw_containers(ftxui::Screen& screen, tui::Rect area) {
    const auto rows = filtered_containers();
    const bool narrow = area.width < 80;
    const int usable = std::max(area.width - 2, 10);
    std::vector<tui::Column> columns;
    if (narrow) {
        columns = {column("容器", 0), column("镜像", 14), column("状态", 11), column("CPU", 6, true), column("内存", 12, true)};
    } else {
        columns = {column("项目 / 容器", 0), column("镜像", pct_width(usable, 16)), column("状态", pct_width(usable, 14)),
                   column("端口", pct_width(usable, 17)), column("CPU", pct_width(usable, 7), true),
                   column("内存", pct_width(usable, 18), true)};
    }
    std::vector<std::vector<std::string>> cells;
    for (const Container* container : rows) {
        const auto stat = stats.find(container->id);
        const std::string memory = stat == stats.end()
            ? "--"
            : narrow ? short_bytes(stat->second.memory) + "/" + short_bytes(stat->second.limit)
                     : cleanup::bytes(stat->second.memory) + "/" + cleanup::bytes(stat->second.limit);
        const std::string name = narrow ? name_of(*container) : project_of(*container).value_or("-") + "/" + name_of(*container);
        if (narrow) {
            cells.push_back({name, container->image, compact_status(container->status),
                             stat == stats.end() ? "--" : std::format("{:.0f}%", stat->second.cpu), memory});
        } else {
            cells.push_back({name, container->image, compact_status(container->status), compact_port_mappings(*container),
                             stat == stats.end() ? "--" : std::format("{:.1f}%", stat->second.cpu), memory});
        }
    }
    const std::string suffix = filter.empty() ? "" : std::format(" · {}/{} · /{}", rows.size(), containers.size(), filter.str());
    draw_table(screen, area, std::format("容器 {}", rows.size()) + suffix, columns, cells);
}
void App::draw_images(ftxui::Screen& screen, tui::Rect area) {
    const auto rows = filtered_images();
    const int usable = std::max(area.width - 2, 10);
    std::vector<tui::Column> columns{
        column("ID", pct_width(usable, 30)),
        column("标签", 0),
        column("大小", pct_width(usable, 16), true),
        column("标记", pct_width(usable, 12)),
    };
    std::vector<std::vector<std::string>> cells;
    for (const Image* image : rows) {
        cells.push_back({short_id(image->id), image->tags.empty() ? "<悬空>" : image->tags.front(), cleanup::bytes(image->size),
                         is_dangling(image->tags) ? "悬空" : ""});
    }
    const std::string suffix = filter.empty() ? "" : std::format(" · {}/{} · /{}", rows.size(), images.size(), filter.str());
    draw_table(screen, area, std::format("镜像 {}", images.size()) + suffix, columns, cells);
}
void App::draw_volumes(ftxui::Screen& screen, tui::Rect area) {
    const auto rows = filtered_volumes();
    const int usable = std::max(area.width - 2, 10);
    std::vector<tui::Column> columns{
        column("卷名", 0),
        column("大小", pct_width(usable, 18), true),
        column("状态", pct_width(usable, 20)),
    };
    std::vector<std::vector<std::string>> cells;
    for (const Volume* volume : rows) cells.push_back({volume->name, volume_size(*volume), state_label(*volume)});
    const std::string suffix = filter.empty() ? "" : std::format(" · {}/{} · /{}", rows.size(), volumes.size(), filter.str());
    draw_table(screen, area, std::format("卷 {} · d 预览 · 卷需输入名称确认", volumes.size()) + suffix, columns, cells);
}
void App::draw_overview(ftxui::Screen& screen, tui::Rect area) {
    if (area.height <= 0) return;
    tui::put(screen, area.x + 1, area.y, "Docker Engine 概览", Style{tui::kBrightFg}, area.width - 2);
    const std::string body = safe("Docker Engine " + info.version + "\n\n" + cleanup::summary(disk) + "\n" + vm.summary() +
        "\n\n5 Docker + VM 空间：Tab/v 切分区，VM 严格只读。\nS 停止 daemon + docker-proxy（另行确认）。");
    int y = area.y + 2;
    for (const std::string& line : tui::wrap(body, std::max(area.width - 4, 1), static_cast<size_t>(std::max(area.height - 2, 0)))) {
        if (y >= area.y + area.height) break;
        tui::put(screen, area.x + 2, y++, line, Style{tui::kFg}, area.width - 4);
    }
}
void App::draw_cleanup(ftxui::Screen& screen, tui::Rect area) {
    if (area.height <= 0) return;
    const auto plan = cleanup::selected(cleanup::entries(disk), picked);
    int table_y = area.y;
    if (area.height >= 14) {
        tui::put(screen, area.x + 1, area.y, "Docker + VM 空间 · VM 严格只读", Style{tui::kBrightFg}, area.width - 2);
        int y = area.y + 1;
        for (const std::string& line : split_lines(safe(cleanup::summary(disk)))) {
            tui::put(screen, area.x + 2, y++, tui::clip(line, area.width - 4), Style{tui::kFg}, area.width - 4);
        }
        tui::put(screen, area.x + 2, y++, tui::clip(safe(vm.summary()), area.width - 4), Style{tui::kMuted}, area.width - 4);
        tui::put(screen, area.x + 2, y++, tui::clip(std::format("Docker 所选 {} 项 · 预计释放 {} · 卷数据不可恢复", plan.size(), cleanup::estimate(plan)),
                                                  area.width - 4), Style{tui::kMuted}, area.width - 4);
        table_y = y + 1;
    }
    const tui::Rect table{area.x, table_y, area.width, std::max(area.y + area.height - table_y, 0)};
    if (vm_section) {
        const auto rows = vm_rows();
        std::vector<std::vector<std::string>> cells;
        for (const vm::Row* row : rows) {
            std::string path = row->path ? std::filesystem::path(*row->path).parent_path().filename().string() + "/" +
                                              std::filesystem::path(*row->path).filename().string()
                                        : row->note;
            cells.push_back({std::string(row->uri).substr(std::string("qemu:///").size()), row->kind, row->owner, "…/" + path,
                             clean_bytes(row->actual), clean_bytes(row->virtual_size)});
        }
        const std::string suffix = filter.empty() ? "" : std::format(" · /{}", filter.str());
        draw_table(screen, table, std::format("VM · 大小降序 · Tab 返回 Docker{}", suffix),
                   {column("连接", 7), column("类型", 12), column("虚拟机/池", 15), column("路径（Enter 完整）", 0),
                    column("占用", 9, true), column("虚拟", 9, true)}, cells);
        return;
    }
    const auto rows = cleanup_entries();
    const bool narrow = area.width < 80;
    const int usable = std::max(area.width - 2, 10);
    std::vector<std::vector<std::string>> cells;
    for (const cleanup::Entry& entry : rows) {
        const std::string mark = !entry.selectable() ? "锁" : picked.contains(entry.key()) ? "[x]" : "[ ]";
        std::string status = entry.blocked ? *entry.blocked : entry.kind == cleanup::Kind::Volume ? "需输入卷名" : "可清理";
        std::string kind_label = cleanup::label(entry.kind);
        if (narrow) {
            if (status.find("运行中") != std::string::npos) status = "运行中";
            else if (status.find("被引用") != std::string::npos) status = "被引用";
            else if (status.find("InUse") != std::string::npos) status = "保护";
            else if (status.find("不支持") != std::string::npos) status = "不可清理";
            if (kind_label == "构建缓存") kind_label = "缓存";
        }
        std::string name = entry.kind == cleanup::Kind::Volume || entry.name.empty() ? entry.id : entry.name;
        if (narrow && entry.kind == cleanup::Kind::Container) {
            if (const size_t at = name.find(" ("); at != std::string::npos) name.erase(at);
        }
        cells.push_back({mark, kind_label, name, clean_bytes(entry.size),
                         entry.selectable() ? clean_bytes(entry.reclaim) : "—", status});
    }
    const std::string suffix = filter.empty() ? "" : std::format(" · /{}", filter.str());
    const int name_width = narrow ? 0 : usable * 28 / 100;
    draw_table(screen, table, std::format("Docker · 大小降序 · Space 多选 · Tab VM{}", suffix),
               {column("选", 3), column("类型", narrow ? 5 : 8), column("名称 / ID", name_width),
                column("占用", narrow ? 8 : 9, true), column("可回收", narrow ? 8 : 9, true),
                column("状态", narrow ? 12 : 0)}, cells);
}
void App::draw_logs(ftxui::Screen& screen, tui::Rect area) {
    if (area.height <= 0) return;
    const std::string query = log_filter.str();
    std::vector<size_t> visible;
    for (size_t i = 0; i < log_lines.size(); ++i) {
        if (is_matches(query, log_lines[i])) visible.push_back(i);
    }
    const std::string label = safe(std::format("实时日志 · {} · {}/{} · /{}", logs ? short_id(*logs) : "", visible.size(), log_lines.size(), query));
    tui::put(screen, area.x + 1, area.y, tui::clip(label, area.width - 2), Style{tui::kBrightFg}, area.width - 2);
    const int rows = area.height - 1;
    if (rows <= 0) return;
    const size_t end = visible.size() > log_scroll ? visible.size() - log_scroll : 0;
    const size_t start = end > static_cast<size_t>(rows) ? end - static_cast<size_t>(rows) : 0;
    if (visible.empty()) {
        tui::put(screen, area.x + 2, area.y + 2, "无匹配日志 · Esc 清除过滤", Style{tui::kMuted}, area.width - 4);
    }
    for (size_t i = start; i < end; ++i) {
        const std::string text = tui::clip(safe(log_lines[visible[i]]), area.width - 4);
        std::vector<std::pair<size_t, size_t>> ranges;
        if (!query.empty()) {
            if (const auto hit = tui::match(query, text)) ranges = hit->ranges;
        }
        tui::put_ranges(screen, area.x + 2, area.y + 1 + static_cast<int>(i - start), text, ranges, Style{tui::kFg}, area.width - 4);
    }
    if (filtering) draw_filter_line(screen, screen.dimy() - 2, tui::Rect{0, screen.dimy() - 2, screen.dimx(), 1}, log_filter);
}
void App::draw_dialog(ftxui::Screen& screen, const std::string& title, const std::string& body, size_t scroll) {
    const int room = std::min(screen.dimx() - 8, 92);
    auto lines = tui::wrap(safe(body), room, 100000);
    const int inner = std::min<int>(screen.dimy() - 5, static_cast<int>(lines.size()));
    const tui::Rect area = tui::centered(screen.dimx(), screen.dimy(), std::min(screen.dimx() - 2, room + 4), inner + 5);
    tui::fill(screen, area, tui::kSurface);
    tui::box(screen, area, title, false, tui::kSurface);
    const size_t max_scroll = lines.size() > static_cast<size_t>(inner) ? lines.size() - static_cast<size_t>(inner) : 0;
    const size_t from = std::min(scroll, max_scroll);
    int y = area.y + 2;
    for (size_t i = from; i < lines.size() && y < area.y + area.height - 1; ++i, ++y) {
        tui::put(screen, area.x + 2, y, lines[i], Style{tui::kFg, tui::kSurface}, area.width - 4);
    }
}
void App::draw_filter_line(ftxui::Screen& screen, int y, tui::Rect area, const tui::TextInput& input) {
    const int start = tui::put(screen, area.x + 1, y, "/ 过滤 ", Style{tui::kBlue}, area.width - 2) + 1;
    draw_input_at(screen, start, y, area.x + area.width - start - 1, input, cursor_);
}
}  // namespace dock
