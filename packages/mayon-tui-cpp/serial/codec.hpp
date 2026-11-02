// Text and byte handling for the serial stream: encodings, framing, telemetry and safe ANSI.
#pragma once
#include <cstdint>
#include <expected>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace serial {
using Bytes = std::vector<uint8_t>;
enum class Encoding { Utf8, Gbk };
const char* encoding_name(Encoding encoding);
// Never fails: bytes that do not decode become U+FFFD.
std::string decode_bytes(Encoding encoding, std::span<const uint8_t> bytes);
std::expected<Bytes, std::string> encode_text(Encoding encoding, std::string_view text);
// Whitespace and commas separate groups; 0x may start a group; adjacent digits form bytes.
std::expected<Bytes, std::string> parse_hex(std::string_view input);
// name=value telemetry or a numeric CSV row. One bad field rejects the row; at most 16 channels.
std::vector<std::pair<std::string, double>> parse_values(std::string_view input);
// Splits on LF, CRLF or CR across chunks. Lines stop growing at 16 KiB until their delimiter.
class Framer {
public:
    static constexpr size_t kMaxLine = 16 * 1024;
    std::vector<Bytes> push(std::span<const uint8_t> bytes);
    std::optional<Bytes> flush();
    const Bytes& pending() const { return line_; }
    bool truncated() const { return truncated_; }

private:
    Bytes line_;
    bool after_cr_ = false;
    bool truncated_ = false;
};
struct AnsiStyle {
    std::optional<uint32_t> fg, bg;
    bool bold = false, dim = false, italic = false, underline = false, reversed = false;
};
struct AnsiSpan {
    std::string text;
    AnsiStyle style;
};
// Only SGR colour and emphasis survive; OSC, cursor movement and other controls are dropped.
std::vector<AnsiSpan> ansi_line(std::string_view text);
std::string plain(std::string_view text);
// Unicode-aware helpers with the semantics the input formats rely on.
std::string trim_text(std::string_view text);
std::vector<std::string> split_whitespace(std::string_view text);
// Decimal digits with an optional '+'. The error is the name of the failure kind.
std::expected<uint64_t, const char*> parse_unsigned(std::string_view text, uint64_t max);
// Shortest round-trip decimal without an exponent.
std::string number_text(double value);
}  // namespace serial
