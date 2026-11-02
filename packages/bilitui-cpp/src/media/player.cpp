#include "media/player.hpp"

#include <poll.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <chrono>
#include <cstring>
#include <optional>
#include <thread>

#include "media/process.hpp"
#include "media/stream.hpp"

namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
namespace bili {
std::optional<PlayItem> next_in_series(const PlayItem& current) {
    if (current.part + 1 < current.video.parts.size()) {
        PlayItem next = current;
        ++next.part;
        next.start = 0;
        return next;
    }
    const auto& episodes = current.video.collection;
    for (size_t i = 0; i + 1 < episodes.size(); ++i) {
        if (episodes[i].bvid == current.video.bvid) {
            PlayItem next;
            next.video = episodes[i + 1];
            next.video.collection = episodes;
            return next;
        }
    }
    return std::nullopt;
}
Player::Player(std::shared_ptr<Api> api, Config config, std::function<void(PlayerStatus)> report)
    : api_(std::move(api)), config_(std::move(config)), report_(std::move(report)), wake_fd_(eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK)), thread_([this] { run(); }) {}
Player::~Player() {
    {
        const std::lock_guard lock(mutex_);
        stop_ = true;
    }
    wake_.notify_all();
    const uint64_t one = 1;
    [[maybe_unused]] const auto ignored = ::write(wake_fd_, &one, sizeof one);
    thread_.join();
    ::close(wake_fd_);
}
std::shared_ptr<Api> Player::api() {
    const std::lock_guard lock(mutex_);
    return api_;
}
void Player::set_api(std::shared_ptr<Api> api) {
    const std::lock_guard lock(mutex_);
    api_ = std::move(api);
}
void Player::set_config(Config config) {
    const std::lock_guard lock(mutex_);
    config_ = std::move(config);
}
void Player::play_now(PlayItem item) {
    {
        const std::lock_guard lock(mutex_);
        pending_now_ = std::move(item);
    }
    wake_.notify_all();
    const uint64_t one = 1;
    [[maybe_unused]] const auto ignored = ::write(wake_fd_, &one, sizeof one);
}
void Player::enqueue(PlayItem item) {
    {
        const std::lock_guard lock(mutex_);
        if (queue_.size() < 200) queue_.push_back(std::move(item));
    }
    publish();
    wake_.notify_all();
}
void Player::publish(const std::string& notice, bool error) {
    PlayerStatus status;
    {
        const std::lock_guard lock(mutex_);
        status.running = active_;
        status.title = title_;
        status.queued = queue_.size();
        status.finished_bvid = std::exchange(finished_, {});
    }
    status.notice = notice;
    status.error = error;
    report_(std::move(status));
}
void Player::send(int socket_fd, const std::string& command) {
    std::string line = command + "\n";
    size_t sent = 0;
    while (sent < line.size()) {
        const ssize_t n = ::send(socket_fd, line.data() + sent, line.size() - sent, MSG_NOSIGNAL);
        if (n <= 0) return;
        sent += static_cast<size_t>(n);
    }
}
void Player::heartbeat(const PlayItem& item, uint64_t cid, uint64_t seconds, uint64_t delta) {
    bool report = false;
    std::shared_ptr<Api> client;
    {
        const std::lock_guard lock(mutex_);
        report = config_.report_history;
        client = api_;
    }
    if (!report || !client->logged_in() || item.video.aid == 0) return;
    try {
        client->post("/x/click-interface/web/heartbeat", {{"aid", std::to_string(item.video.aid)},
                                                          {"cid", std::to_string(cid)},
                                                          {"played_time", std::to_string(seconds)},
                                                          {"realtime", std::to_string(delta)},
                                                          {"type", "3"},
                                                          {"dt", "2"}});
    } catch (const std::exception&) {
        publish("播放正常，进度上报失败");
    }
}
static std::string title_of(const PlayItem& item) {
    std::string title = item.video.title;
    if (item.video.parts.size() > 1 && item.part < item.video.parts.size()) {
        title += " · P" + std::to_string(item.part + 1) + " " + item.video.parts[item.part].title;
    }
    return title;
}
namespace {
struct Session {
    pid_t pid = -1;
    int socket = -1;
    fs::path dir;
    std::string buffer;
    ~Session() {
        if (socket >= 0) ::close(socket);
        if (pid > 0) stop_process(pid);
        std::error_code ignored;
        if (!dir.empty()) fs::remove_all(dir, ignored);
    }
};
int connect_socket(const fs::path& path) {
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (path.string().size() >= sizeof address.sun_path) return -1;
    std::strcpy(address.sun_path, path.c_str());
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    if (::connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof address) != 0) {
        ::close(fd);
        return -1;
    }
    return fd;
}
std::atomic<uint64_t> sequence{0};
}  // namespace
void Player::run() {
    std::unique_ptr<Session> session;
    std::optional<PlayItem> current;
    uint64_t current_cid = 0;
    uint64_t position = 0;
    uint64_t reported = 0;
    bool loaded = false;
    auto last_query = Clock::now();
    auto last_report = Clock::now();
    const auto clear_active = [&] {
        const std::lock_guard lock(mutex_);
        active_ = false;
        title_.clear();
    };
    const auto load = [&](PlayItem item) -> bool {
        try {
            const auto client = api();
            uint64_t quality = 0;
            bool subtitles = true;
            fs::path cache;
            {
                const std::lock_guard lock(mutex_);
                quality = config_.quality;
                subtitles = config_.subtitles;
            }
            uint64_t cid = item.part < item.video.parts.size() ? item.video.parts[item.part].cid : item.video.cid;
            if (cid == 0 || (item.video.parts.empty() && item.video.aid == 0)) {
                const Video full = parse_video(client->get("/x/web-interface/view", {{"bvid", item.video.bvid}}));
                const auto collection = item.video.collection;
                item.video = full;
                if (item.video.collection.empty()) item.video.collection = collection;
                cid = item.part < item.video.parts.size() ? item.video.parts[item.part].cid : item.video.cid;
            }
            const Stream stream = resolve_stream(*client, item.video.bvid, cid, quality);
            if (!session) {
                session = std::make_unique<Session>();
                session->dir = cache_dir() / ("player-" + std::to_string(getpid()) + "-" + std::to_string(sequence.fetch_add(1)));
                private_dir(session->dir);
                const fs::path socket_path = session->dir / "mpv.sock";
                session->pid = spawn_process({"mpv", "--no-terminal", "--really-quiet", "--idle=yes", "--force-window=yes", "--hwdec=auto-safe",
                                              "--keep-open=no", std::string("--user-agent=") + kUserAgent, "--input-ipc-server=" + socket_path.string()});
                for (int i = 0; i < 100 && session->socket < 0; ++i) {
                    session->socket = connect_socket(socket_path);
                    if (session->socket < 0) std::this_thread::sleep_for(std::chrono::milliseconds(50));
                }
                if (session->socket < 0) throw std::runtime_error("mpv 未能启动");
                send(session->socket, R"({"command":["disable_event","all"]})");
                send(session->socket, R"({"command":["enable_event","end-file"]})");
                send(session->socket, R"({"command":["enable_event","file-loaded"]})");
            }
            Json options = Json::object();
            options["force-media-title"] = title_of(item);
            options["referrer"] = item.video.link();
            if (!stream.audio.empty()) options["audio-file"] = stream.audio;
            if (item.start > 0) options["start"] = std::to_string(item.start);
            Json command;
            command["command"] = {{"name", "loadfile"}, {"url", stream.video}, {"flags", "replace"}, {"options", options}};
            send(session->socket, command.dump(-1, ' ', false, Json::error_handler_t::replace));
            current = item;
            current_cid = cid;
            position = item.start;
            reported = item.start;
            loaded = false;
            last_report = Clock::now();
            {
                const std::lock_guard lock(mutex_);
                active_ = true;
                title_ = title_of(item);
            }
            publish("正在播放 · 清晰度 Q" + std::to_string(stream.quality));
            if (subtitles && client->logged_in()) {
                try {
                    const PlayerInfo info = fetch_player_info(*client, item.video.bvid, cid);
                    if (const auto chosen = preferred_subtitle(info.subtitles)) {
                        const std::string srt = fetch_subtitle_srt(*chosen);
                        if (!srt.empty()) {
                            const fs::path path = session->dir / ("sub-" + std::to_string(cid) + ".srt");
                            write_private(path, srt);
                            Json add;
                            add["command"] = {"sub-add", path.string(), "select", chosen->title.empty() ? "字幕" : chosen->title};
                            send(session->socket, add.dump(-1, ' ', false, Json::error_handler_t::replace));
                        }
                    }
                } catch (const std::exception&) {
                    // Subtitles are optional; playback continues without them.
                }
            }
            return true;
        } catch (const std::exception& error) {
            publish(error.what(), true);
            return false;
        }
    };
    const auto finish_report = [&] {
        if (current && position > reported) {
            heartbeat(*current, current_cid, position, position - reported);
            reported = position;
        }
    };
    const auto next_item = [&]() -> std::optional<PlayItem> {
        {
            const std::lock_guard lock(mutex_);
            if (!queue_.empty()) {
                PlayItem item = std::move(queue_.front());
                queue_.pop_front();
                return item;
            }
        }
        return current ? next_in_series(*current) : std::nullopt;
    };
    while (true) {
        if (!session) {
            std::unique_lock lock(mutex_);
            wake_.wait(lock, [this] { return stop_ || pending_now_ || !queue_.empty(); });
            if (stop_) return;
        }
        std::optional<PlayItem> now;
        bool idle_queue = false;
        {
            const std::lock_guard lock(mutex_);
            if (stop_) break;
            now = std::exchange(pending_now_, std::nullopt);
            if (!now && !current && !queue_.empty()) {
                now = std::move(queue_.front());
                queue_.pop_front();
                idle_queue = true;
            }
        }
        (void)idle_queue;
        if (now) {
            finish_report();
            if (current && current->video.bvid != now->video.bvid) {
                const std::lock_guard lock(mutex_);
                finished_ = current->video.bvid;
            }
            if (!load(std::move(*now)) && !current) {
                session.reset();
                clear_active();
                publish();
            }
            continue;
        }
        if (!session) continue;
        pollfd fds[2]{{session->socket, POLLIN, 0}, {wake_fd_, POLLIN, 0}};
        const int ready = ::poll(fds, 2, 1000);
        if (ready > 0 && (fds[1].revents & POLLIN)) {
            uint64_t value = 0;
            [[maybe_unused]] const auto ignored = ::read(wake_fd_, &value, sizeof value);
        }
        bool closed = false;
        if (ready > 0 && (fds[0].revents & (POLLIN | POLLHUP | POLLERR))) {
            char chunk[4096];
            const ssize_t got = ::recv(session->socket, chunk, sizeof chunk, 0);
            if (got <= 0) {
                closed = true;
            } else {
                session->buffer.append(chunk, static_cast<size_t>(got));
                if (session->buffer.size() > 1024 * 1024) session->buffer.clear();
            }
        }
        size_t newline = 0;
        bool ended_eof = false;
        bool ended_error = false;
        while ((newline = session->buffer.find('\n')) != std::string::npos) {
            const std::string line = session->buffer.substr(0, newline);
            session->buffer.erase(0, newline + 1);
            const Json message = Json::parse(line, nullptr, false);
            if (!message.is_object()) continue;
            const std::string event = str(message, "event");
            if (event == "file-loaded") {
                loaded = true;
            } else if (event == "end-file") {
                const std::string reason = str(message, "reason");
                ended_eof = reason == "eof";
                ended_error = reason == "error";
            } else if (message.value("request_id", 0) == 7 && message.contains("data") && message["data"].is_number()) {
                position = static_cast<uint64_t>(std::max(message["data"].get<double>(), 0.0));
            }
        }
        const auto now_time = Clock::now();
        if (loaded && now_time - last_query >= std::chrono::seconds(5)) {
            send(session->socket, R"({"command":["get_property","time-pos"],"request_id":7})");
            last_query = now_time;
        }
        if (loaded && now_time - last_report >= std::chrono::seconds(15) && position > reported) {
            finish_report();
            last_report = now_time;
        }
        if (ended_error) publish("这一集播放失败，可能是地区或权限限制", true);
        if (ended_eof || ended_error) {
            finish_report();
            auto next = ended_eof ? next_item() : std::nullopt;
            if (current) {
                const std::lock_guard lock(mutex_);
                finished_ = current->video.bvid;
            }
            if (next && load(std::move(*next))) continue;
            closed = true;
        }
        bool exited = false;
        if (session->pid > 0 && try_reap(session->pid, nullptr)) {
            session->pid = -1;
            exited = true;
        }
        if (closed || exited) {
            finish_report();
            if (current) {
                const std::lock_guard lock(mutex_);
                finished_ = current->video.bvid;
            }
            session.reset();
            current.reset();
            clear_active();
            publish("mpv 已结束");
        }
    }
    finish_report();
}
}  // namespace bili
