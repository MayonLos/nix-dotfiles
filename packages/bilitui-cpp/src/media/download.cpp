#include "media/download.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <stdexcept>
#include <thread>

#include "core/text.hpp"
#include "media/process.hpp"
#include "media/stream.hpp"
#include "store.hpp"

namespace fs = std::filesystem;
namespace bili {
std::string safe_filename(const std::string& title) {
    std::u32string kept;
    for (const char32_t ch : decode(title)) {
        if (ch < 0x20 || ch == 0x7F || kept.size() >= 70) continue;
        kept.push_back(std::u32string_view(U"/\\:*?\"<>|").find(ch) != std::u32string_view::npos ? U'_' : ch);
    }
    std::string out = encode(kept);
    const auto first = out.find_first_not_of(". ");
    if (first == std::string::npos) return "video";
    return out.substr(first, out.find_last_not_of(". ") - first + 1);
}
Downloader::Downloader(std::shared_ptr<Api> api, std::function<void(DownloadUpdate)> report)
    : api_(std::move(api)), report_(std::move(report)), thread_([this] { run(); }) {}
Downloader::~Downloader() {
    {
        const std::lock_guard lock(mutex_);
        stop_ = true;
    }
    cancel_->store(true);
    wake_.notify_all();
    thread_.join();
}
void Downloader::add(DownloadJob job) {
    {
        const std::lock_guard lock(mutex_);
        jobs_.push_back(std::move(job));
    }
    wake_.notify_all();
}
void Downloader::set_api(std::shared_ptr<Api> api) {
    const std::lock_guard lock(mutex_);
    api_ = std::move(api);
}
void Downloader::run() {
    while (true) {
        DownloadJob job;
        {
            std::unique_lock lock(mutex_);
            wake_.wait(lock, [this] { return stop_ || !jobs_.empty(); });
            if (stop_) return;
            job = std::move(jobs_.front());
            jobs_.pop_front();
        }
        try {
            download(job);
            report_({job.id, "已完成", 0});
        } catch (const std::exception& error) {
            report_({job.id, std::string("失败：") + error.what(), 0});
        }
    }
}
namespace {
struct StagingDir {
    fs::path path;
    ~StagingDir() {
        std::error_code ignored;
        fs::remove_all(path, ignored);
    }
};
}  // namespace
void Downloader::download(const DownloadJob& job) {
    std::shared_ptr<Api> client;
    {
        const std::lock_guard lock(mutex_);
        client = api_;
    }
    const Stream stream = resolve_stream(*client, job.video.bvid, job.cid, job.quality, cancel_);
    fs::create_directories(job.directory);
    const fs::path target = job.directory / (safe_filename(job.video.title) + "-" + job.video.bvid + "-" + std::to_string(job.cid) + (job.audio_only ? ".m4a" : ".mkv"));
    if (fs::exists(target)) throw std::runtime_error("目标已存在，未覆盖");
    static std::atomic<uint64_t> sequence{0};
    StagingDir staging{job.directory / (".bilitui-" + std::to_string(getpid()) + "-" + std::to_string(sequence.fetch_add(1)))};
    private_dir(staging.path);
    const auto fetch = [&](const std::string& url, const fs::path& path) {
        const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        if (fd < 0) throw std::runtime_error("无法创建下载暂存文件");
        uint64_t bytes = 0;
        auto last = std::chrono::steady_clock::now();
        HttpRequest request;
        request.url = trusted_media_url(url);
        request.cancel = cancel_;
        request.timeout_seconds = 0;
        request.headers.push_back("Referer: " + job.video.link());
        request.sink = [&](const char* data, size_t size) {
            size_t done = 0;
            while (done < size) {
                const ssize_t n = ::write(fd, data + done, size - done);
                if (n <= 0) return false;
                done += static_cast<size_t>(n);
            }
            bytes += size;
            const auto now = std::chrono::steady_clock::now();
            if (now - last > std::chrono::milliseconds(500)) {
                report_({job.id, "下载中", bytes});
                last = now;
            }
            return true;
        };
        HttpResponse response;
        try {
            response = http_perform(request);
        } catch (...) {
            ::close(fd);
            throw;
        }
        const bool synced = ::fsync(fd) == 0;
        ::close(fd);
        if (response.status < 200 || response.status >= 300) throw std::runtime_error("下载 HTTP " + std::to_string(response.status));
        if (!synced) throw std::runtime_error("下载暂存文件写入失败");
    };
    const fs::path video = staging.path / "video";
    const fs::path audio = staging.path / "audio";
    const fs::path output = staging.path / "output";
    const bool has_audio = !stream.audio.empty();
    if (!job.audio_only || !has_audio) fetch(stream.video, video);
    if (has_audio) fetch(stream.audio, audio);
    report_({job.id, "FFmpeg 合并中", 0});
    std::vector<std::string> command{"ffmpeg", "-nostdin", "-v", "error", "-n"};
    if (job.audio_only) {
        command.insert(command.end(), {"-i", has_audio ? audio.string() : video.string(), "-vn", "-c:a", "copy", "-f", "ipod"});
    } else {
        command.insert(command.end(), {"-i", video.string()});
        if (has_audio) command.insert(command.end(), {"-i", audio.string(), "-map", "0:v:0", "-map", "1:a:0"});
        command.insert(command.end(), {"-c", "copy", "-f", "matroska"});
    }
    command.push_back(output.string());
    const pid_t pid = spawn_process(command);
    bool success = false;
    while (!try_reap(pid, &success)) {
        if (cancel_->load()) {
            stop_process(pid);
            throw std::runtime_error("已取消");
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (!success) throw std::runtime_error("FFmpeg 合并失败");
    // A hard link fails on an existing target, so the final step cannot overwrite.
    if (::link(output.c_str(), target.c_str()) != 0) throw std::runtime_error("保存失败，目标可能已存在");
}
}  // namespace bili
