// The real terminal: raw mode, line-diffed frames and Kitty graphics.
#pragma once
#include <ftxui/screen/screen.hpp>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tui {
struct Image {
    int width = 0;
    int height = 0;
    std::vector<unsigned char> rgb;
};
std::string base64(std::string_view data);
class Terminal {
public:
    Terminal();
    ~Terminal();
    Terminal(const Terminal&) = delete;
    Terminal& operator=(const Terminal&) = delete;
    std::pair<int, int> size() const;
    void invalidate() { previous_.clear(); }
    void present(ftxui::Screen& screen, std::optional<std::pair<int, int>> cursor);
    void write_raw(const std::string& data);
    // Uploads once and only re-places the image when its position changes.
    void show_image(const Image& image, const std::string& id, int x, int y, int columns, int rows);
    void hide_image();
    void copy(const std::string& text);

private:
    std::vector<std::string> previous_;
    std::string uploaded_;
    std::string placement_;
    bool active_ = false;
};
}  // namespace tui
