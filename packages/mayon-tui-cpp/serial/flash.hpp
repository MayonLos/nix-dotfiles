// Runs the user's flash command in a private process group without blocking the UI.
// Readers never wait: when the bounded queue is full, whole lines are dropped so a slow UI
// cannot stall the child on a full pipe. The final message reports how many were lost.
#pragma once
#include <atomic>
#include <expected>
#include <memory>
#include <string>
#include <thread>

#include "transport.hpp"

namespace serial {
struct FlashEvent {
    enum class Kind { Line, Done } kind = Kind::Line;
    std::string text;
};
class Flash {
public:
    static std::expected<std::unique_ptr<Flash>, std::string> start(const std::string& command, const std::string& directory);
    ~Flash();
    Flash(const Flash&) = delete;
    Flash& operator=(const Flash&) = delete;
    // Stops the whole group, reaps the child and drains captured events.
    void cancel();
    bool running() const { return worker_.joinable(); }
    std::shared_ptr<Channel<FlashEvent>> rx;

private:
    Flash() = default;
    pid_t pid_ = 0;
    std::thread worker_;
    std::shared_ptr<std::atomic<bool>> finished_;
};
inline constexpr size_t kFlashMaxLine = 16 * 1024;
inline constexpr const char* kFlashTruncation = " … [输出行已截断]";
void emit_flash_line(Channel<FlashEvent>& tx, std::atomic<size_t>& dropped, const Bytes& bytes, bool truncated);
}  // namespace serial
