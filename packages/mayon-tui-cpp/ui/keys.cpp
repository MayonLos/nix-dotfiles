#include "ui/keys.hpp"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <utility>

#include "ui/text.hpp"

namespace tui {
namespace {
InputEvent key_event(KeyCode code, char32_t ch = 0, bool ctrl = false, bool alt = false) {
    InputEvent event;
    event.key = {code, ch, ctrl, alt};
    return event;
}
InputEvent simple(InputEvent::Type type) {
    InputEvent event;
    event.type = type;
    return event;
}
// Sizes an incomplete or complete UTF-8 character from its lead byte.
size_t utf8_length(unsigned char lead) {
    if (lead < 0x80) return 1;
    if ((lead >> 5) == 6) return 2;
    if ((lead >> 4) == 14) return 3;
    if ((lead >> 3) == 30) return 4;
    return 1;
}
}  // namespace
std::vector<InputEvent> InputParser::feed(std::string_view bytes) {
    static const std::string paste_end = "\x1b[201~";
    std::vector<InputEvent> out;
    buffer_.append(bytes);
    size_t at = 0;
    const auto consume = [&](size_t count) { at += count; };
    while (at < buffer_.size()) {
        if (in_paste_) {
            const auto end = buffer_.find(paste_end, at);
            if (end == std::string::npos) {
                // Keep a possible partial terminator; everything before it is paste text.
                const size_t keep = std::min(buffer_.size() - at, paste_end.size() - 1);
                paste_.append(buffer_, at, buffer_.size() - at - keep);
                at = buffer_.size() - keep;
                break;
            }
            paste_.append(buffer_, at, end - at);
            InputEvent event = simple(InputEvent::Type::Paste);
            event.paste = std::exchange(paste_, {});
            out.push_back(std::move(event));
            in_paste_ = false;
            consume(end + paste_end.size() - at);
            continue;
        }
        const auto c = static_cast<unsigned char>(buffer_[at]);
        if (c == 0x1B) {
            if (at + 1 >= buffer_.size()) break;
            const char next = buffer_[at + 1];
            if (next == '[') {
                size_t end = at + 2;
                while (end < buffer_.size() && !(buffer_[end] >= 0x40 && buffer_[end] <= 0x7E)) ++end;
                if (end >= buffer_.size()) {
                    if (buffer_.size() - at > 64) at = buffer_.size();
                    break;
                }
                const std::string body = buffer_.substr(at + 2, end - at - 2);
                const char final = buffer_[end];
                consume(end + 1 - at);
                if (final == '<' || (!body.empty() && body[0] == '<')) {
                    // SGR mouse: <button;x;y(M|m)
                    int button = 0, x = 0, y = 0;
                    if (std::sscanf(body.c_str(), "<%d;%d;%d", &button, &x, &y) == 3 && final == 'M') {
                        InputEvent event;
                        if (button == 64) event = simple(InputEvent::Type::WheelUp);
                        else if (button == 65) event = simple(InputEvent::Type::WheelDown);
                        else if (button == 0) event = simple(InputEvent::Type::MouseClick);
                        else continue;
                        event.x = x - 1;
                        event.y = y - 1;
                        out.push_back(std::move(event));
                    }
                    continue;
                }
                if (final == 'I') { out.push_back(simple(InputEvent::Type::FocusIn)); continue; }
                if (final == 'O') { out.push_back(simple(InputEvent::Type::FocusOut)); continue; }
                if (final == 'Z') { out.push_back(key_event(KeyCode::BackTab)); continue; }
                if (final == '~') {
                    const int number = std::atoi(body.c_str());
                    if (number == 200) { in_paste_ = true; continue; }
                    if (number == 1 || number == 7) out.push_back(key_event(KeyCode::Home));
                    if (number == 3) out.push_back(key_event(KeyCode::Delete));
                    if (number == 4 || number == 8) out.push_back(key_event(KeyCode::End));
                    if (number == 5) out.push_back(key_event(KeyCode::PageUp));
                    if (number == 6) out.push_back(key_event(KeyCode::PageDown));
                    continue;
                }
                const KeyCode code = final == 'A' ? KeyCode::Up : final == 'B' ? KeyCode::Down : final == 'C' ? KeyCode::Right : final == 'D' ? KeyCode::Left
                                     : final == 'H' ? KeyCode::Home : final == 'F' ? KeyCode::End : KeyCode::None;
                if (code != KeyCode::None) out.push_back(key_event(code));
                continue;
            }
            if (next == 'O') {
                if (at + 2 >= buffer_.size()) break;
                const char final = buffer_[at + 2];
                consume(3);
                const KeyCode code = final == 'A' ? KeyCode::Up : final == 'B' ? KeyCode::Down : final == 'C' ? KeyCode::Right : final == 'D' ? KeyCode::Left
                                     : final == 'H' ? KeyCode::Home : final == 'F' ? KeyCode::End : KeyCode::None;
                if (code != KeyCode::None) out.push_back(key_event(code));
                continue;
            }
            // Alt+key.
            consume(1);
            const auto second = static_cast<unsigned char>(buffer_[at]);
            if (second == 0x7F || second == 0x08) {
                consume(1);
                out.push_back(key_event(KeyCode::Backspace, 0, false, true));
            } else if (second >= 0x20) {
                const size_t length = utf8_length(second);
                if (at + length > buffer_.size()) { at -= 1; break; }
                const auto text = decode(std::string_view(buffer_).substr(at, length));
                consume(length);
                out.push_back(key_event(KeyCode::Char, text.empty() ? 0 : text[0], false, true));
            }
            continue;
        }
        if (c == '\r' || c == '\n') { consume(1); out.push_back(key_event(KeyCode::Enter)); continue; }
        if (c == '\t') { consume(1); out.push_back(key_event(KeyCode::Tab)); continue; }
        if (c == 0x7F || c == 0x08) { consume(1); out.push_back(key_event(KeyCode::Backspace)); continue; }
        if (c < 0x20) { consume(1); out.push_back(key_event(KeyCode::Char, static_cast<char32_t>(c + 0x60), true)); continue; }
        const size_t length = utf8_length(c);
        if (at + length > buffer_.size()) break;
        const auto text = decode(std::string_view(buffer_).substr(at, length));
        consume(length);
        if (!text.empty() && text[0] != U'�') out.push_back(key_event(KeyCode::Char, text[0]));
    }
    buffer_.erase(0, at);
    return out;
}
std::vector<InputEvent> InputParser::flush() {
    std::vector<InputEvent> out;
    if (!in_paste_ && buffer_ == "\x1b") {
        buffer_.clear();
        out.push_back(key_event(KeyCode::Escape));
    } else if (!in_paste_) {
        buffer_.clear();
    }
    return out;
}
}  // namespace tui
