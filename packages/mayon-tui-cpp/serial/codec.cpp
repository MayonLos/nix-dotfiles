#include "codec.hpp"

#include <iconv.h>

#include <array>
#include <cerrno>
#include <charconv>
#include <cmath>
#include <cstdlib>

#include "ui/draw.hpp"
#include "ui/text.hpp"

namespace serial {
namespace {
constexpr std::string_view kReplacement = "\xEF\xBF\xBD";
// iconv handles are not thread safe, so each thread owns its own.
class Iconv {
public:
    Iconv(const char* to, const char* from) : handle_(iconv_open(to, from)) {}
    ~Iconv() {
        if (valid()) iconv_close(handle_);
    }
    Iconv(const Iconv&) = delete;
    Iconv& operator=(const Iconv&) = delete;
    bool valid() const { return handle_ != reinterpret_cast<iconv_t>(-1); }
    void reset() { iconv(handle_, nullptr, nullptr, nullptr, nullptr); }
    size_t run(const char*& in, size_t& in_left, char*& out, size_t& out_left) {
        char* source = const_cast<char*>(in);
        const size_t result = iconv(handle_, &source, &in_left, &out, &out_left);
        in = source;
        return result;
    }

private:
    iconv_t handle_;
};
constexpr size_t kIconvFailed = static_cast<size_t>(-1);
bool ascii_only(std::span<const uint8_t> bytes) {
    for (const uint8_t byte : bytes) {
        if (byte >= 0x80) return false;
    }
    return true;
}
// One U+FFFD per maximal invalid subpart, the same rule as Rust's from_utf8_lossy.
std::string decode_utf8(std::span<const uint8_t> bytes) {
    std::string out;
    out.reserve(bytes.size());
    size_t at = 0;
    while (at < bytes.size()) {
        const uint8_t lead = bytes[at];
        if (lead < 0x80) {
            out.push_back(static_cast<char>(lead));
            ++at;
            continue;
        }
        int extra = 0;
        uint8_t low = 0x80, high = 0xBF;
        if (lead >= 0xC2 && lead <= 0xDF) {
            extra = 1;
        } else if (lead >= 0xE0 && lead <= 0xEF) {
            extra = 2;
            if (lead == 0xE0) low = 0xA0;
            if (lead == 0xED) high = 0x9F;
        } else if (lead >= 0xF0 && lead <= 0xF4) {
            extra = 3;
            if (lead == 0xF0) low = 0x90;
            if (lead == 0xF4) high = 0x8F;
        }
        if (extra == 0) {
            out += kReplacement;
            ++at;
            continue;
        }
        size_t next = at + 1;
        bool valid = true;
        for (int i = 0; i < extra; ++i, ++next) {
            if (next >= bytes.size() || bytes[next] < low || bytes[next] > high) {
                valid = false;
                break;
            }
            low = 0x80;
            high = 0xBF;
        }
        if (valid) out.append(reinterpret_cast<const char*>(bytes.data()) + at, next - at);
        else out += kReplacement;
        at = next;
    }
    return out;
}
// WHATWG "GBK" decodes as GB18030 and maps the single byte 0x80 to the euro sign.
std::string decode_gbk(std::span<const uint8_t> bytes) {
    if (ascii_only(bytes)) return std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    thread_local Iconv converter("UTF-8", "GB18030");
    std::string out;
    out.reserve(bytes.size() * 3 / 2);
    const char* in = reinterpret_cast<const char*>(bytes.data());
    size_t left = bytes.size();
    std::array<char, 4096> buffer;
    if (converter.valid()) converter.reset();
    while (left > 0) {
        char* cursor = buffer.data();
        size_t room = buffer.size();
        size_t result = kIconvFailed;
        int error = EILSEQ;
        if (converter.valid()) {
            errno = 0;
            result = converter.run(in, left, cursor, room);
            error = errno;
        }
        out.append(buffer.data(), static_cast<size_t>(cursor - buffer.data()));
        if (result != kIconvFailed || error == E2BIG) continue;
        if (error == EINVAL) {
            out += kReplacement;
            break;
        }
        const auto byte = static_cast<uint8_t>(*in);
        if (byte == 0x80) out += "€";
        else if (byte < 0x80) out.push_back(*in);
        else out += kReplacement;
        ++in;
        --left;
    }
    return out;
}
// The WHATWG GBK encoder is GB18030 limited to one and two byte forms, plus the euro at 0x80.
std::expected<Bytes, std::string> encode_gbk(std::string_view text) {
    thread_local Iconv converter("GB18030", "UTF-8");
    Bytes out;
    for (const char32_t ch : tui::decode(text)) {
        if (ch < 0x80) {
            out.push_back(static_cast<uint8_t>(ch));
            continue;
        }
        if (ch == U'€') {
            out.push_back(0x80);
            continue;
        }
        std::string one;
        tui::append(one, ch);
        std::array<char, 8> buffer;
        const char* in = one.data();
        size_t left = one.size();
        char* cursor = buffer.data();
        size_t room = buffer.size();
        bool ok = converter.valid();
        if (ok) {
            converter.reset();
            ok = converter.run(in, left, cursor, room) != kIconvFailed;
        }
        if (!ok || cursor - buffer.data() != 2) return std::unexpected("文本包含 GBK 无法表示的字符");
        out.push_back(static_cast<uint8_t>(buffer[0]));
        out.push_back(static_cast<uint8_t>(buffer[1]));
    }
    return out;
}
bool is_space(char32_t ch) {
    return (ch >= 9 && ch <= 13) || ch == 0x20 || ch == 0x85 || ch == 0xA0 || ch == 0x1680 || (ch >= 0x2000 && ch <= 0x200A) || ch == 0x2028 || ch == 0x2029 || ch == 0x202F || ch == 0x205F || ch == 0x3000;
}
bool is_control(char32_t ch) { return ch < 0x20 || (ch >= 0x7F && ch < 0xA0); }
std::vector<std::string> split_on(std::string_view text, char separator) {
    std::vector<std::string> out;
    size_t at = 0;
    while (true) {
        const size_t next = text.find(separator, at);
        if (next == std::string_view::npos) {
            out.emplace_back(text.substr(at));
            return out;
        }
        out.emplace_back(text.substr(at, next - at));
        at = next + 1;
    }
}
// Rust's f64 grammar: an optional sign, no whitespace and no hex.
std::optional<double> parse_float(const std::string& text) {
    std::string_view body = text;
    if (!body.empty() && body[0] == '+') {
        body.remove_prefix(1);
        if (!body.empty() && body[0] == '-') return std::nullopt;
    }
    double value = 0;
    const auto [end, error] = std::from_chars(body.data(), body.data() + body.size(), value);
    if (end != body.data() + body.size()) return std::nullopt;
    if (error == std::errc::result_out_of_range) {
        value = std::strtod(std::string(body).c_str(), nullptr);  // Underflow stays a finite value.
    } else if (error != std::errc{}) {
        return std::nullopt;
    }
    if (!std::isfinite(value)) return std::nullopt;
    return value;
}
// Device colours map onto the palette; the palette has no magenta or cyan, so both read as blue.
uint32_t ansi_colour(int index, bool bright) {
    using namespace tui;
    static constexpr std::array<uint32_t, 8> normal{kBorder, kRed, kGreen, kYellow, kBlue, kBlue, kBlue, kFg};
    static constexpr std::array<uint32_t, 8> vivid{kMuted, kRed, kGreen, kYellow, kBlue, kBlue, kBlue, kBrightFg};
    return (bright ? vivid : normal)[static_cast<size_t>(index) & 7];
}
uint32_t indexed_colour(int index) {
    if (index < 8) return ansi_colour(index, false);
    if (index < 16) return ansi_colour(index - 8, true);
    if (index >= 232) {
        const auto level = static_cast<uint32_t>(8 + (index - 232) * 10);
        return level << 16 | level << 8 | level;
    }
    const int cube = index - 16;
    const auto step = [](int value) { return static_cast<uint32_t>(value == 0 ? 0 : 55 + value * 40); };
    return step(cube / 36) << 16 | step(cube / 6 % 6) << 8 | step(cube % 6);
}
void apply_sgr(AnsiStyle& style, const std::string& sequence) {
    std::vector<uint16_t> params;
    if (sequence.empty()) {
        params.push_back(0);
    } else {
        for (const std::string& part : split_on(sequence, ';')) {
            uint16_t value = 0;
            const auto [end, error] = std::from_chars(part.data(), part.data() + part.size(), value);
            params.push_back(error == std::errc{} && end == part.data() + part.size() ? value : 0);
        }
    }
    for (size_t i = 0; i < params.size(); ++i) {
        const int code = params[i];
        if (code == 0) style = AnsiStyle{};
        else if (code == 1) style.bold = true;
        else if (code == 2) style.dim = true;
        else if (code == 3) style.italic = true;
        else if (code == 4) style.underline = true;
        else if (code == 7) style.reversed = true;
        else if (code == 22) style.bold = style.dim = false;
        else if (code == 23) style.italic = false;
        else if (code == 24) style.underline = false;
        else if (code == 27) style.reversed = false;
        else if (code >= 30 && code <= 37) style.fg = ansi_colour(code - 30, false);
        else if (code == 39) style.fg.reset();
        else if (code >= 40 && code <= 47) style.bg = ansi_colour(code - 40, false);
        else if (code == 49) style.bg.reset();
        else if (code >= 90 && code <= 97) style.fg = ansi_colour(code - 90, true);
        else if (code >= 100 && code <= 107) style.bg = ansi_colour(code - 100, true);
        else if ((code == 38 || code == 48) && i + 1 < params.size()) {
            std::optional<uint32_t> colour;
            if (params[i + 1] == 5 && i + 2 < params.size()) {
                i += 2;
                colour = indexed_colour(params[i] & 255);
            } else if (params[i + 1] == 2 && i + 4 < params.size()) {
                colour = static_cast<uint32_t>(params[i + 2] & 255) << 16 | static_cast<uint32_t>(params[i + 3] & 255) << 8 | static_cast<uint32_t>(params[i + 4] & 255);
                i += 4;
            }
            if (colour) (code == 38 ? style.fg : style.bg) = colour;
        }
    }
}
}  // namespace
const char* encoding_name(Encoding encoding) { return encoding == Encoding::Gbk ? "Gbk" : "Utf8"; }
std::string decode_bytes(Encoding encoding, std::span<const uint8_t> bytes) { return encoding == Encoding::Gbk ? decode_gbk(bytes) : decode_utf8(bytes); }
std::expected<Bytes, std::string> encode_text(Encoding encoding, std::string_view text) {
    if (encoding == Encoding::Gbk) return encode_gbk(text);
    return Bytes(text.begin(), text.end());
}
std::expected<Bytes, std::string> parse_hex(std::string_view input) {
    static const std::string kOdd = "HEX 字节必须由偶数个十六进制数字组成";
    Bytes bytes;
    std::optional<uint8_t> high;
    bool group_start = true;
    const std::u32string chars = tui::decode(input);
    for (size_t i = 0; i < chars.size(); ++i) {
        const char32_t ch = chars[i];
        if (is_space(ch) || ch == U',') {
            if (high) return std::unexpected(kOdd);
            group_start = true;
            continue;
        }
        if (group_start && ch == U'0' && i + 1 < chars.size() && (chars[i + 1] == U'x' || chars[i + 1] == U'X')) {
            ++i;
            group_start = false;
            continue;
        }
        int digit = -1;
        if (ch >= U'0' && ch <= U'9') digit = static_cast<int>(ch - U'0');
        else if (ch >= U'a' && ch <= U'f') digit = static_cast<int>(ch - U'a') + 10;
        else if (ch >= U'A' && ch <= U'F') digit = static_cast<int>(ch - U'A') + 10;
        if (digit < 0) {
            std::string shown;
            tui::append(shown, ch);
            return std::unexpected("非法 HEX 字符：" + shown);
        }
        group_start = false;
        if (high) {
            bytes.push_back(static_cast<uint8_t>(*high << 4 | digit));
            high.reset();
        } else {
            high = static_cast<uint8_t>(digit);
        }
    }
    if (high) return std::unexpected(kOdd);
    if (bytes.empty()) return std::unexpected("HEX 数据不能为空");
    return bytes;
}
std::vector<std::pair<std::string, double>> parse_values(std::string_view input) {
    std::vector<std::string> fields = split_on(trim_text(input), ',');
    if (fields.size() > 16) return {};
    bool named = false;
    for (std::string& field : fields) {
        field = trim_text(field);
        if (field.empty()) return {};
        named = named || field.find('=') != std::string::npos;
    }
    std::vector<std::pair<std::string, double>> parsed;
    parsed.reserve(fields.size());
    for (size_t i = 0; i < fields.size(); ++i) {
        std::string name = "ch" + std::to_string(i + 1);
        std::string value = fields[i];
        if (named) {
            const size_t equals = fields[i].find('=');
            if (equals == std::string::npos) return {};
            name = trim_text(std::string_view(fields[i]).substr(0, equals));
            if (name.empty()) return {};
            for (const char32_t ch : tui::decode(name)) {
                if (is_control(ch)) return {};
            }
            value = trim_text(std::string_view(fields[i]).substr(equals + 1));
        }
        const auto number = parse_float(value);
        if (!number) return {};
        parsed.emplace_back(std::move(name), *number);
    }
    return parsed;
}
std::vector<Bytes> Framer::push(std::span<const uint8_t> bytes) {
    std::vector<Bytes> lines;
    for (const uint8_t byte : bytes) {
        if (after_cr_) {
            after_cr_ = false;
            if (byte == '\n') continue;
        }
        if (byte == '\r' || byte == '\n') {
            lines.push_back(std::exchange(line_, {}));
            truncated_ = false;
            after_cr_ = byte == '\r';
        } else if (line_.size() < kMaxLine) {
            line_.push_back(byte);
        } else {
            truncated_ = true;
        }
    }
    return lines;
}
std::optional<Bytes> Framer::flush() {
    after_cr_ = false;
    if (line_.empty()) return std::nullopt;
    truncated_ = false;
    return std::exchange(line_, {});
}
std::vector<AnsiSpan> ansi_line(std::string_view text) {
    std::vector<AnsiSpan> out;
    std::string current;
    AnsiStyle style;
    const auto flush = [&] {
        if (!current.empty()) out.push_back(AnsiSpan{std::exchange(current, {}), style});
    };
    const std::u32string chars = tui::decode(text);
    size_t i = 0;
    while (i < chars.size()) {
        const char32_t ch = chars[i++];
        if (ch != 0x1B) {
            if (!is_control(ch)) tui::append(current, ch);
            continue;
        }
        flush();
        if (i >= chars.size()) break;
        const char32_t kind = chars[i++];
        if (kind == U'[') {
            std::string sequence;
            char32_t final_byte = 0;
            while (i < chars.size()) {
                const char32_t next = chars[i++];
                if (next >= 0x40 && next <= 0x7E) {
                    final_byte = next;
                    break;
                }
                if (next < 0x20 || next > 0x3F) break;
                sequence.push_back(static_cast<char>(next));
            }
            if (final_byte == U'm') apply_sgr(style, sequence);
        } else if (kind == U']') {
            while (i < chars.size()) {
                const char32_t next = chars[i++];
                if (next == 0x07) break;
                if (next == 0x1B && i < chars.size() && chars[i] == U'\\') {
                    ++i;
                    break;
                }
            }
        }
    }
    flush();
    return out;
}
std::string plain(std::string_view text) {
    // Hot path while filtering: most lines carry no escape or control character at all.
    bool simple = true;
    for (const char c : text) {
        const auto byte = static_cast<unsigned char>(c);
        if (byte < 0x20 || byte == 0x7F || byte == 0xC2) {
            simple = false;
            break;
        }
    }
    if (simple) return std::string(text);
    std::string out;
    for (const AnsiSpan& span : ansi_line(text)) out += span.text;
    return out;
}
std::string trim_text(std::string_view text) {
    const std::u32string chars = tui::decode(text);
    size_t from = 0, to = chars.size();
    while (from < to && is_space(chars[from])) ++from;
    while (to > from && is_space(chars[to - 1])) --to;
    return tui::encode(std::u32string_view(chars).substr(from, to - from));
}
std::vector<std::string> split_whitespace(std::string_view text) {
    std::vector<std::string> out;
    std::string word;
    for (const char32_t ch : tui::decode(text)) {
        if (is_space(ch)) {
            if (!word.empty()) out.push_back(std::exchange(word, {}));
        } else {
            tui::append(word, ch);
        }
    }
    if (!word.empty()) out.push_back(std::move(word));
    return out;
}
std::expected<uint64_t, const char*> parse_unsigned(std::string_view text, uint64_t max) {
    if (text.empty()) return std::unexpected("Empty");
    if (text[0] == '+') text.remove_prefix(1);
    if (text.empty()) return std::unexpected("InvalidDigit");
    uint64_t value = 0;
    for (const char c : text) {
        if (c < '0' || c > '9') return std::unexpected("InvalidDigit");
        const auto digit = static_cast<uint64_t>(c - '0');
        if (digit > max || value > (max - digit) / 10) return std::unexpected("PosOverflow");
        value = value * 10 + digit;
    }
    return value;
}
std::string number_text(double value) {
    std::array<char, 400> buffer;
    const auto result = std::to_chars(buffer.data(), buffer.data() + buffer.size(), value, std::chars_format::fixed);
    return std::string(buffer.data(), result.ptr);
}
}  // namespace serial
