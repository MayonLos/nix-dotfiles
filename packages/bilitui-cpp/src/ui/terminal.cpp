#include "ui/terminal.hpp"

#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <stdexcept>

namespace bili {
static termios saved_termios;
static const char kEnter[] = "\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[?2004h\x1b[?1004h\x1b]11;#1e2228\x07\x1b[2J";
static const char kLeave[] = "\x1b_Ga=d,d=I,i=42,q=2\x1b\\\x1b]111\x07\x1b[?1004l\x1b[?2004l\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l";
std::string base64(std::string_view data) {
    static constexpr char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((data.size() + 2) / 3 * 4);
    for (size_t i = 0; i < data.size(); i += 3) {
        const auto byte = [&](size_t k) { return k < data.size() ? static_cast<unsigned char>(data[k]) : 0U; };
        const unsigned value = byte(i) << 16 | byte(i + 1) << 8 | byte(i + 2);
        out += table[(value >> 18) & 63];
        out += table[(value >> 12) & 63];
        out += i + 1 < data.size() ? table[(value >> 6) & 63] : '=';
        out += i + 2 < data.size() ? table[value & 63] : '=';
    }
    return out;
}
Terminal::Terminal() {
    if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) throw std::runtime_error("需要在真实终端中运行");
    if (tcgetattr(STDIN_FILENO, &saved_termios) != 0) throw std::runtime_error("无法读取终端设置");
    termios raw = saved_termios;
    cfmakeraw(&raw);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) throw std::runtime_error("无法设置终端模式");
    active_ = true;
    write_raw(kEnter);
}
Terminal::~Terminal() {
    if (!active_) return;
    write_raw(kLeave);
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_termios);
}
std::pair<int, int> Terminal::size() const {
    winsize size{};
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) != 0 || size.ws_col == 0) return {80, 24};
    return {size.ws_col, size.ws_row};
}
void Terminal::write_raw(const std::string& data) {
    size_t written = 0;
    while (written < data.size()) {
        const ssize_t n = ::write(STDOUT_FILENO, data.data() + written, data.size() - written);
        if (n <= 0) return;
        written += static_cast<size_t>(n);
    }
}
void Terminal::present(ftxui::Screen& screen, std::optional<std::pair<int, int>> cursor) {
    const std::string frame = screen.ToString();
    std::vector<std::string> lines;
    size_t at = 0;
    while (true) {
        const auto end = frame.find("\r\n", at);
        lines.push_back(frame.substr(at, end == std::string::npos ? end : end - at));
        if (end == std::string::npos) break;
        at = end + 2;
    }
    std::string out = "\x1b[?2026h\x1b[?25l";
    for (size_t row = 0; row < lines.size(); ++row) {
        if (row < previous_.size() && previous_[row] == lines[row]) continue;
        out += "\x1b[" + std::to_string(row + 1) + ";1H\x1b[0m" + lines[row] + "\x1b[0m";
    }
    previous_ = std::move(lines);
    if (cursor) {
        out += "\x1b[" + std::to_string(cursor->second + 1) + ";" + std::to_string(cursor->first + 1) + "H\x1b[?25h";
    }
    out += "\x1b[?2026l";
    write_raw(out);
}
void Terminal::show_image(const Image& image, const std::string& id, int x, int y, int columns, int rows) {
    const std::string place = id + "@" + std::to_string(x) + "," + std::to_string(y) + "," + std::to_string(columns) + "," + std::to_string(rows);
    if (place == placement_) return;
    placement_ = place;
    std::string out = "\x1b" "7\x1b[" + std::to_string(y + 1) + ";" + std::to_string(x + 1) + "H";
    const std::string size = "c=" + std::to_string(columns) + ",r=" + std::to_string(rows);
    if (id == uploaded_) {
        out += "\x1b_Ga=p,i=42,p=1," + size + ",q=2\x1b\\";
    } else {
        uploaded_ = id;
        const std::string encoded = base64(std::string_view(reinterpret_cast<const char*>(image.rgb.data()), image.rgb.size()));
        for (size_t at = 0; at < encoded.size(); at += 4096) {
            const bool more = at + 4096 < encoded.size();
            if (at == 0) {
                out += "\x1b_Ga=T,f=24,i=42,p=1,s=" + std::to_string(image.width) + ",v=" + std::to_string(image.height) + "," + size + ",q=2,m=" + (more ? "1" : "0") + ";";
            } else {
                out += std::string("\x1b_Gm=") + (more ? "1" : "0") + ";";
            }
            out += encoded.substr(at, 4096) + "\x1b\\";
        }
    }
    out += "\x1b" "8";
    write_raw(out);
}
void Terminal::hide_image() {
    if (placement_.empty() && uploaded_.empty()) return;
    placement_.clear();
    uploaded_.clear();
    write_raw("\x1b_Ga=d,d=I,i=42,q=2\x1b\\");
}
void Terminal::copy(const std::string& text) { write_raw("\x1b]52;c;" + base64(text) + "\x07"); }
}  // namespace bili
