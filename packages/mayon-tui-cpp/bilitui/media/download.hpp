// Serial downloads: stage privately in the target filesystem, merge with FFmpeg, never overwrite.
#pragma once
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "core/model.hpp"
#include "net/api.hpp"

namespace bili {
struct DownloadJob {
    size_t id = 0;
    Video video;
    uint64_t cid = 0;
    uint64_t quality = 0;
    bool audio_only = false;
    std::filesystem::path directory;
};
struct DownloadUpdate {
    size_t id = 0;
    std::string state;
    uint64_t bytes = 0;
};
std::string safe_filename(const std::string& title);
class Downloader {
public:
    Downloader(std::shared_ptr<Api> api, std::function<void(DownloadUpdate)> report);
    ~Downloader();
    void add(DownloadJob job);
    void set_api(std::shared_ptr<Api> api);

private:
    void run();
    void download(const DownloadJob& job);
    std::mutex mutex_;
    std::condition_variable wake_;
    std::shared_ptr<Api> api_;
    std::function<void(DownloadUpdate)> report_;
    std::deque<DownloadJob> jobs_;
    CancelFlag cancel_ = make_cancel();
    bool stop_ = false;
    std::thread thread_;
};
}  // namespace bili
