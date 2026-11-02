// Terminal input decoding, independent of the real terminal so it can be tested.
#pragma once
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace tui {
enum class KeyCode { None, Char, Enter, Escape, Tab, BackTab, Backspace, Delete, Up, Down, Left, Right, Home, End, PageUp, PageDown, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12 };
struct Key {
    KeyCode code = KeyCode::None;
    char32_t ch = 0;
    bool ctrl = false;
    bool alt = false;
    bool is(char32_t c) const { return code == KeyCode::Char && ch == c && !ctrl && !alt; }
};
struct InputEvent {
    enum class Type { Key, Paste, MouseClick, WheelUp, WheelDown, FocusIn, FocusOut } type = Type::Key;
    Key key;
    std::string paste;
    int x = 0;
    int y = 0;
};
class InputParser {
public:
    std::vector<InputEvent> feed(std::string_view bytes);
    // A lone ESC can only be told apart from a sequence after a short silence.
    std::vector<InputEvent> flush();
    bool pending() const { return !buffer_.empty(); }

private:
    std::string buffer_;
    std::string paste_;
    bool in_paste_ = false;
};
}  // namespace tui
