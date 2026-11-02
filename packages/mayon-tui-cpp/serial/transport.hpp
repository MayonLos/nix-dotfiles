// Port discovery and the worker thread that owns the open port.
#pragma once
#include <sys/eventfd.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "codec.hpp"

namespace serial {
struct Device {
    std::string path;
    uint16_t vid = 0;
    uint16_t pid = 0;
    std::optional<std::string> serial;
    std::string product;
    std::string interface;
    std::string topology;  // Stable physical sysfs location, or a caller's stable alias for PTYs.
    std::string key() const;
};
// Enumerates USB-backed ttyACM/ttyUSB nodes from sysfs. Never opens a device.
std::vector<Device> discover();
// Nothing when no candidate or more than one has the target's identity: never guess.
std::optional<Device> resolve_device(const Device& target, const std::vector<Device>& candidates);
struct Settings {
    uint32_t baud = 115200;
    uint8_t bits = 8;
    std::string parity = "none";
    uint8_t stop = 1;
    std::string flow = "none";
    bool dtr = false;
    bool rts = false;
};
struct Command {
    enum class Kind { Shutdown, Connect, Disconnect, Release, Write, Lines, Pulse } kind = Kind::Shutdown;
    Device device;
    Settings settings;
    uint64_t id = 0;  // Release: acknowledged only after the port has closed.
    Bytes bytes;
    bool dtr = false;
    bool rts = false;
    uint64_t millis = 0;
    static Command connect(Device device, Settings settings);
    static Command disconnect();
    static Command release(uint64_t id);
    static Command write(Bytes bytes);
    static Command lines(bool dtr, bool rts);
    static Command pulse(bool dtr, uint64_t millis);
    static Command shutdown() { return Command{}; }
};
struct Event {
    enum class Kind { Error, Connected, Disconnected, Released, Rx, Tx } kind = Kind::Error;
    std::string text;
    Bytes bytes;
    uint64_t id = 0;
    size_t count = 0;
    static Event connected(std::string path) { return Event{Kind::Connected, std::move(path)}; }
    static Event disconnected(std::string path) { return Event{Kind::Disconnected, std::move(path)}; }
    static Event released(uint64_t id) { return Event{Kind::Released, {}, {}, id}; }
    static Event rx(Bytes bytes) { return Event{Kind::Rx, {}, std::move(bytes)}; }
    static Event tx(size_t count) { return Event{Kind::Tx, {}, {}, 0, count}; }
    static Event error(std::string message) { return Event{Kind::Error, std::move(message)}; }
};
// Bounded queue between threads. A closed queue rejects new items but can still be drained.
template <class T>
class Channel {
public:
    enum class Result { Ok, Full, Closed };
    explicit Channel(size_t capacity) : capacity_(capacity) {}
    // The item is only moved from on success, so a caller can keep it when the queue is full.
    Result try_send(T&& item) {
        {
            const std::lock_guard lock(mutex_);
            if (closed_) return Result::Closed;
            if (items_.size() >= capacity_) return Result::Full;
            items_.push_back(std::move(item));
        }
        ready_.notify_one();
        wake();
        return Result::Ok;
    }
    // Waits for room; false means the queue closed first.
    bool send(T&& item) {
        {
            std::unique_lock lock(mutex_);
            room_.wait(lock, [this] { return closed_ || items_.size() < capacity_; });
            if (closed_) return false;
            items_.push_back(std::move(item));
        }
        ready_.notify_one();
        wake();
        return true;
    }
    std::optional<T> try_recv() {
        const std::lock_guard lock(mutex_);
        return pop();
    }
    std::optional<T> recv_timeout(std::chrono::milliseconds timeout) {
        std::unique_lock lock(mutex_);
        ready_.wait_for(lock, timeout, [this] { return !items_.empty(); });
        return pop();
    }
    void close() {
        {
            const std::lock_guard lock(mutex_);
            closed_ = true;
        }
        room_.notify_all();
    }
    void set_wake_fd(int fd) { wake_fd_ = fd; }

private:
    std::optional<T> pop() {
        if (items_.empty()) return std::nullopt;
        std::optional<T> item(std::move(items_.front()));
        items_.pop_front();
        room_.notify_one();
        return item;
    }
    void wake() {
        if (wake_fd_ < 0) return;
        const uint64_t one = 1;
        [[maybe_unused]] const auto ignored = ::write(wake_fd_, &one, sizeof one);
    }
    size_t capacity_;
    std::mutex mutex_;
    std::condition_variable ready_;
    std::condition_variable room_;
    std::deque<T> items_;
    bool closed_ = false;
    int wake_fd_ = -1;
};
using CommandChannel = Channel<Command>;
using EventChannel = Channel<Event>;
class Worker {
public:
    Worker() = default;
    // `notify` runs on the worker thread when events are ready, at most every 70 ms while streaming.
    static Worker start(std::function<void()> notify = {});
    static Worker from_channels(std::shared_ptr<CommandChannel> tx, std::shared_ptr<EventChannel> rx);
    // Rejects every command until replaced; used while the page is hidden.
    static Worker parked();
    Worker(Worker&& other) noexcept = default;
    Worker& operator=(Worker&& other) noexcept;
    ~Worker();
    void stop();
    std::shared_ptr<CommandChannel> tx;
    std::shared_ptr<EventChannel> rx;

private:
    struct Control {
        std::atomic<bool> stopped{false};
        int wake_fd = -1;
        ~Control();
    };
    std::shared_ptr<Control> control_;
    std::thread thread_;
};
}  // namespace serial
