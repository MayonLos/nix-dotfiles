// One long-lived mpv window: a queue, automatic next episode, resume and progress reporting.
#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "core/model.hpp"
#include "net/api.hpp"
#include "store.hpp"

namespace bili {
struct PlayItem {
    Video video;  // Full details: parts and collection drive automatic continuation.
    size_t part = 0;
    uint64_t start = 0;
    std::string collection_owner;
};
struct PlayerStatus {
    bool running = false;
    std::string title;
    size_t queued = 0;
    uint64_t position = 0;
    uint64_t duration = 0;  // 0 until mpv reports it.
    std::string finished_bvid;  // Set when progress changed, so cached details can be refreshed.
    std::string notice;
    bool error = false;
};
// What to play after `current`: the next part, or the next episode of its collection.
std::optional<PlayItem> next_in_series(const PlayItem& current);
class Player {
public:
    Player(std::shared_ptr<Api> api, Config config, std::function<void(PlayerStatus)> report);
    ~Player();
    void play_now(PlayItem item);
    void enqueue(PlayItem item);
    void set_config(Config config);
    void set_api(std::shared_ptr<Api> api);

private:
    void run();
    void send(int socket_fd, const std::string& command);
    void heartbeat(const PlayItem& item, uint64_t cid, uint64_t seconds, uint64_t delta);
    void publish(const std::string& notice = {}, bool error = false);
    std::shared_ptr<Api> api();

    std::mutex mutex_;
    std::condition_variable wake_;
    std::shared_ptr<Api> api_;
    Config config_;
    std::function<void(PlayerStatus)> report_;
    std::deque<PlayItem> queue_;
    std::optional<PlayItem> pending_now_;
    bool stop_ = false;
    int wake_fd_ = -1;
    std::thread thread_;
    std::string title_;
    bool active_ = false;
    std::string finished_;
    uint64_t position_ = 0;
    uint64_t duration_ = 0;
};
}  // namespace bili
