// Worker threads hand closures to the UI thread. Only that thread changes application state.
#pragma once
#include <sys/eventfd.h>
#include <unistd.h>

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

namespace bili {
class App;
class Mailbox {
public:
    Mailbox() : fd_(eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK)) {}
    ~Mailbox() { ::close(fd_); }
    Mailbox(const Mailbox&) = delete;
    Mailbox& operator=(const Mailbox&) = delete;
    int fd() const { return fd_; }
    void post(std::function<void(App&)> job) {
        {
            const std::lock_guard lock(mutex_);
            jobs_.push_back(std::move(job));
        }
        const uint64_t one = 1;
        [[maybe_unused]] const auto ignored = ::write(fd_, &one, sizeof one);
    }
    std::deque<std::function<void(App&)>> take() {
        uint64_t value = 0;
        [[maybe_unused]] const auto ignored = ::read(fd_, &value, sizeof value);
        const std::lock_guard lock(mutex_);
        return std::exchange(jobs_, {});
    }

private:
    int fd_;
    std::mutex mutex_;
    std::deque<std::function<void(App&)>> jobs_;
};
class Pool {
public:
    explicit Pool(size_t threads) {
        for (size_t i = 0; i < threads; ++i) {
            threads_.emplace_back([this] {
                while (true) {
                    std::function<void()> job;
                    {
                        std::unique_lock lock(mutex_);
                        ready_.wait(lock, [this] { return stop_ || !jobs_.empty(); });
                        if (stop_) return;
                        job = std::move(jobs_.front());
                        jobs_.pop_front();
                    }
                    job();
                }
            });
        }
    }
    ~Pool() {
        {
            const std::lock_guard lock(mutex_);
            stop_ = true;
        }
        ready_.notify_all();
        for (auto& thread : threads_) thread.join();
    }
    void run(std::function<void()> job) {
        {
            const std::lock_guard lock(mutex_);
            jobs_.push_back(std::move(job));
        }
        ready_.notify_one();
    }

private:
    std::mutex mutex_;
    std::condition_variable ready_;
    std::deque<std::function<void()>> jobs_;
    std::vector<std::thread> threads_;
    bool stop_ = false;
};
}  // namespace bili
