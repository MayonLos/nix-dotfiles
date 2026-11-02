#include "core/wbi.hpp"

#include <array>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <map>
#include <stdexcept>

#include "ui/text.hpp"

namespace bili {
using tui::form_encode;
std::string md5_hex(std::string_view data) {
    static constexpr std::array<uint32_t, 64> k = [] {
        // floor(2^32 * abs(sin(i + 1))), published in RFC 1321.
        return std::array<uint32_t, 64>{
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1,
            0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453,
            0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942,
            0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
            0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d,
            0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391};
    }();
    static constexpr std::array<uint8_t, 16> shifts{7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21};
    std::string message(data);
    const uint64_t bits = static_cast<uint64_t>(data.size()) * 8;
    message.push_back(static_cast<char>(0x80));
    while (message.size() % 64 != 56) message.push_back('\0');
    for (int i = 0; i < 8; ++i) message.push_back(static_cast<char>((bits >> (8 * i)) & 0xFF));
    uint32_t a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
    for (size_t chunk = 0; chunk < message.size(); chunk += 64) {
        std::array<uint32_t, 16> m{};
        for (size_t i = 0; i < 16; ++i) {
            for (size_t b = 0; b < 4; ++b) m[i] |= static_cast<uint32_t>(static_cast<unsigned char>(message[chunk + i * 4 + b])) << (8 * b);
        }
        uint32_t a = a0, b = b0, c = c0, d = d0;
        for (uint32_t i = 0; i < 64; ++i) {
            uint32_t f = 0, g = 0;
            switch (i / 16) {
                case 0: f = (b & c) | (~b & d); g = i; break;
                case 1: f = (d & b) | (~d & c); g = (5 * i + 1) % 16; break;
                case 2: f = b ^ c ^ d; g = (3 * i + 5) % 16; break;
                default: f = c ^ (b | ~d); g = (7 * i) % 16; break;
            }
            f = f + a + k[i] + m[g];
            a = d;
            d = c;
            c = b;
            const uint32_t s = shifts[(i / 16) * 4 + i % 4];
            b = b + ((f << s) | (f >> (32 - s)));
        }
        a0 += a;
        b0 += b;
        c0 += c;
        d0 += d;
    }
    char out[33];
    const std::array<uint32_t, 4> words{a0, b0, c0, d0};
    for (size_t w = 0; w < 4; ++w) {
        for (size_t b = 0; b < 4; ++b) std::snprintf(out + (w * 8 + b * 2), 3, "%02x", (words[w] >> (8 * b)) & 0xFF);
    }
    return out;
}
Params wbi_sign(const Params& params, const std::string& img, const std::string& sub, uint64_t timestamp) {
    static constexpr std::array<uint8_t, 32> mixin{46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
                                                   27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13};
    const std::string raw = img + sub;
    if (img.size() != 32 || sub.size() != 32) throw std::runtime_error("WBI 密钥格式无效");
    for (const char c : raw) {
        if (!std::isalnum(static_cast<unsigned char>(c))) throw std::runtime_error("WBI 密钥格式无效");
    }
    std::string key;
    for (const uint8_t index : mixin) key += raw[index];
    std::map<std::string, std::string> values;
    for (const auto& [name, value] : params) {
        if (name.empty() || name == "w_rid" || name == "wts" || name.find_first_of("&=") != std::string::npos) continue;
        std::string cleaned;
        for (const char c : value) {
            if (!std::strchr("!'()*", c) || c == '\0') cleaned += c;
        }
        values[name] = std::move(cleaned);
    }
    values["wts"] = std::to_string(timestamp);
    std::string query;
    Params out;
    for (const auto& [name, value] : values) {
        if (!query.empty()) query += '&';
        query += form_encode(name) + "=" + form_encode(value);
        out.emplace_back(name, value);
    }
    out.emplace_back("w_rid", md5_hex(query + key));
    return out;
}
}  // namespace bili
