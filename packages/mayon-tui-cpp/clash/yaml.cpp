#include "yaml.hpp"

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cstdint>
#include <map>
#include <unordered_map>

namespace clash::yaml {
namespace {
using Size = std::string_view::size_type;
constexpr Size kNpos = std::string_view::npos;

bool is_space(char c) { return c == ' ' || c == '\t'; }
bool valid_utf8(std::string_view text) {
    size_t at = 0;
    while (at < text.size()) {
        const auto lead = static_cast<unsigned char>(text[at]);
        size_t need = 0;
        char32_t code = 0;
        if (lead < 0x80) {
            ++at;
            continue;
        }
        if ((lead & 0xE0) == 0xC0) {
            need = 1;
            code = lead & 0x1F;
            if (code < 2) return false;
        } else if ((lead & 0xF0) == 0xE0) {
            need = 2;
            code = lead & 0x0F;
        } else if ((lead & 0xF8) == 0xF0) {
            need = 3;
            code = lead & 0x07;
        } else {
            return false;
        }
        if (at + need >= text.size()) return false;
        for (size_t k = 1; k <= need; ++k) {
            const auto next = static_cast<unsigned char>(text[at + k]);
            if ((next & 0xC0) != 0x80) return false;
            code = (code << 6) | (next & 0x3F);
        }
        if ((need == 2 && code < 0x800) || (need == 3 && code < 0x10000) || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return false;
        at += need + 1;
    }
    return true;
}
int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
void append_utf8(std::string& out, char32_t code) {
    if (code <= 0x7F) {
        out += static_cast<char>(code);
    } else if (code <= 0x7FF) {
        out += static_cast<char>(0xC0 | (code >> 6));
        out += static_cast<char>(0x80 | (code & 0x3F));
    } else if (code <= 0xFFFF) {
        out += static_cast<char>(0xE0 | (code >> 12));
        out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (code & 0x3F));
    } else {
        out += static_cast<char>(0xF0 | (code >> 18));
        out += static_cast<char>(0x80 | ((code >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (code & 0x3F));
    }
}
struct Line {
    int indent = 0;
    std::string text;  // Without indentation and without a trailing comment.
};
// Removes a comment that starts at whitespace outside quotes. '#' inside a plain
// URL fragment is only a comment when preceded by whitespace, as in YAML.
std::string strip_comment(std::string_view text) {
    bool single = false;
    bool doubly = false;
    int depth = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (single) {
            if (c == '\'') {
                if (i + 1 < text.size() && text[i + 1] == '\'') {
                    ++i;
                } else {
                    single = false;
                }
            }
        } else if (doubly) {
            if (c == '\\') {
                ++i;
            } else if (c == '"') {
                doubly = false;
            }
        } else if (c == '\'') {
            single = true;
        } else if (c == '"') {
            doubly = true;
        } else if (c == '[' || c == '{') {
            ++depth;
        } else if (c == ']' || c == '}') {
            if (depth > 0) --depth;
        } else if (c == '#' && (i == 0 || is_space(text[i - 1]))) {
            return std::string(text.substr(0, i));
        }
    }
    return std::string(text);
}
std::string trim_plain(std::string_view text) {
    while (!text.empty() && is_space(text.front())) text.remove_prefix(1);
    while (!text.empty() && is_space(text.back())) text.remove_suffix(1);
    return std::string(text);
}
bool is_null_word(std::string_view text) {
    return text.empty() || text == "~" || text == "null" || text == "Null" || text == "NULL";
}
bool unbalanced(std::string_view text) {
    bool single = false, doubly = false;
    int depth = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (single) {
            if (c == '\'') {
                if (i + 1 < text.size() && text[i + 1] == '\'') ++i;
                else single = false;
            }
        } else if (doubly) {
            if (c == '\\') ++i;
            else if (c == '"') doubly = false;
        } else if (c == '\'') {
            single = true;
        } else if (c == '"') {
            doubly = true;
        } else if (c == '[' || c == '{') {
            ++depth;
        } else if (c == ']' || c == '}') {
            --depth;
        }
    }
    return single || doubly || depth != 0;
}
// Finds a top-level ':' that separates a block key from its value.
Size find_colon(std::string_view text) {
    bool single = false, doubly = false;
    int depth = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (single) {
            if (c == '\'') {
                if (i + 1 < text.size() && text[i + 1] == '\'') ++i;
                else single = false;
            }
        } else if (doubly) {
            if (c == '\\') ++i;
            else if (c == '"') doubly = false;
        } else if (c == '\'') {
            single = true;
        } else if (c == '"') {
            doubly = true;
        } else if (c == '[' || c == '{') {
            ++depth;
        } else if (c == ']' || c == '}') {
            if (depth > 0) --depth;
        } else if (c == ':' && depth == 0) {
            if (i + 1 == text.size() || is_space(text[i + 1]) || text[i + 1] == '#' || text[i + 1] == '[' || text[i + 1] == '{') return i;
        }
    }
    return kNpos;
}
bool decode_quoted(std::string_view text, size_t& at, std::string& out) {
    const char quote = text[at];
    ++at;
    while (at < text.size()) {
        const char c = text[at];
        if (quote == '\'') {
            if (c == '\'') {
                if (at + 1 < text.size() && text[at + 1] == '\'') {
                    out += '\'';
                    at += 2;
                    continue;
                }
                ++at;
                return true;
            }
            out += c;
            ++at;
            continue;
        }
        if (c == '"') {
            ++at;
            return true;
        }
        if (c != '\\') {
            out += c;
            ++at;
            continue;
        }
        ++at;
        if (at >= text.size()) return false;
        const char esc = text[at++];
        switch (esc) {
            case '0': out += '\0'; break;
            case 'a': out += '\a'; break;
            case 'b': out += '\b'; break;
            case 't': out += '\t'; break;
            case 'n': out += '\n'; break;
            case 'v': out += '\v'; break;
            case 'f': out += '\f'; break;
            case 'r': out += '\r'; break;
            case 'e': out += '\x1B'; break;
            case '"': out += '"'; break;
            case '/': out += '/'; break;
            case '\\': out += '\\'; break;
            case ' ': out += ' '; break;
            case 'N': append_utf8(out, 0x85); break;
            case '_': append_utf8(out, 0xA0); break;
            case 'L': append_utf8(out, 0x2028); break;
            case 'P': append_utf8(out, 0x2029); break;
            case 'x':
            case 'u':
            case 'U': {
                const int digits = esc == 'x' ? 2 : esc == 'u' ? 4 : 8;
                if (at + static_cast<size_t>(digits) > text.size()) return false;
                char32_t code = 0;
                for (int k = 0; k < digits; ++k) {
                    const int value = hex_value(text[at + k]);
                    if (value < 0) return false;
                    code = (code << 4) | static_cast<char32_t>(value);
                }
                at += static_cast<size_t>(digits);
                if (code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return false;
                append_utf8(out, code);
                break;
            }
            default: return false;
        }
    }
    return false;
}
struct RawScalar {
    std::string text;
    bool quoted = false;
};
bool parse_block_scalar_token(std::string_view text, RawScalar& out) {
    std::string_view value = text;
    while (!value.empty() && is_space(value.front())) value.remove_prefix(1);
    if (value.empty()) return false;
    if (value.front() == '\'' || value.front() == '"') {
        size_t at = 0;
        std::string decoded;
        if (!decode_quoted(value, at, decoded)) return false;
        while (at < value.size() && is_space(value[at])) ++at;
        if (at < value.size() && value[at] != '#') return false;
        out = RawScalar{std::move(decoded), true};
        return true;
    }
    std::string plain = trim_plain(strip_comment(value));
    out = RawScalar{std::move(plain), false};
    return true;
}
Node scalar_node(RawScalar raw) {
    Node node;
    if (!raw.quoted && is_null_word(raw.text)) {
        node.type = Node::Type::Null;
        return node;
    }
    node.type = Node::Type::Scalar;
    node.value = std::move(raw.text);
    node.quoted = raw.quoted;
    return node;
}
size_t count_nodes(const Node& root) {
    size_t count = 0;
    std::vector<const Node*> stack{&root};
    while (!stack.empty()) {
        const Node* node = stack.back();
        stack.pop_back();
        if (++count > 8'000'000) return count;
        for (const Node& item : node->items) stack.push_back(&item);
        for (const auto& entry : node->entries) {
            stack.push_back(&entry.first);
            stack.push_back(&entry.second);
        }
    }
    return count;
}
struct Flow {
    std::string_view text;
    size_t at = 0;
    bool ok = true;
    std::unordered_map<std::string, Node>* anchors = nullptr;
    size_t* nodes = nullptr;
    int depth = 0;
    struct Guard {
        int& value;
        explicit Guard(int& target) : value(target) { ++value; }
        ~Guard() { --value; }
    };
    bool bump(size_t count = 1) {
        if (!nodes) return true;
        *nodes += count;
        return *nodes <= 8'000'000;
    }

    void ws() {
        while (at < text.size()) {
            if (is_space(text[at]) || text[at] == '\n' || text[at] == '\r') {
                ++at;
            } else if (text[at] == '#' && (at == 0 || is_space(text[at - 1]) || text[at - 1] == '\n')) {
                while (at < text.size() && text[at] != '\n') ++at;
            } else {
                break;
            }
        }
    }
    bool take(char c) {
        ws();
        if (at < text.size() && text[at] == c) {
            ++at;
            return true;
        }
        return false;
    }
    Node scalar(bool key) {
        ws();
        Node node;
        if (at < text.size() && (text[at] == '\'' || text[at] == '"')) {
            std::string decoded;
            if (!decode_quoted(text, at, decoded)) {
                ok = false;
                return node;
            }
            node.type = Node::Type::Scalar;
            node.value = std::move(decoded);
            node.quoted = true;
            return node;
        }
        const size_t start = at;
        int depth = 0;
        while (at < text.size()) {
            const char c = text[at];
            if (c == '\'' || c == '"') {
                std::string ignored;
                if (!decode_quoted(text, at, ignored)) {
                    ok = false;
                    return node;
                }
                continue;
            }
            if (c == '[' || c == '{') ++depth;
            if (c == ']' || c == '}') {
                if (depth == 0) break;
                --depth;
            }
            if (depth == 0) {
                if (c == ',' || c == ']' || c == '}') break;
                if (key && c == ':' && (at + 1 >= text.size() || is_space(text[at + 1]) || text[at + 1] == ',' || text[at + 1] == '}' || text[at + 1] == ']')) break;
                if (c == '#' && at > start && is_space(text[at - 1])) break;
            }
            ++at;
        }
        std::string raw = trim_plain(text.substr(start, at - start));
        if (!key && is_null_word(raw)) {
            node.type = Node::Type::Null;
            return node;
        }
        node.type = Node::Type::Scalar;
        node.value = std::move(raw);
        return node;
    }
    Node node(bool key = false) {
        if (depth >= 128 || !bump()) {
            ok = false;
            return {};
        }
        Guard guard(depth);
        ws();
        if (at < text.size()) {
            if (text[at] == '&') {
                ++at;
                const size_t start = at;
                while (at < text.size() && !is_space(text[at]) && text[at] != '[' && text[at] != '{' && text[at] != ',' && text[at] != ']' && text[at] != '}') ++at;
                const std::string name(text.substr(start, at - start));
                Node value = node(key);
                if (anchors && !name.empty()) (*anchors)[name] = value;
                return value;
            }
            if (text[at] == '*') {
                ++at;
                const size_t start = at;
                while (at < text.size() && !is_space(text[at]) && text[at] != ',' && text[at] != ']' && text[at] != '}') ++at;
                const std::string name(text.substr(start, at - start));
                if (!anchors || !anchors->contains(name)) {
                    ok = false;
                    return {};
                }
                const Node& stored = anchors->at(name);
                if (!bump(count_nodes(stored))) {
                    ok = false;
                    return {};
                }
                return stored;
            }
            if (text[at] == '!' && (at + 1 >= text.size() || text[at + 1] != '=')) {
                while (at < text.size() && !is_space(text[at])) ++at;
                return node(key);
            }
            if (text[at] == '[') {
                Node out;
                out.type = Node::Type::Sequence;
                ++at;
                ws();
                if (take(']')) return out;
                while (ok) {
                    out.items.push_back(node());
                    ws();
                    if (take(']')) return out;
                    if (!take(',')) {
                        ok = false;
                        return {};
                    }
                }
                return out;
            }
            if (text[at] == '{') {
                Node out;
                out.type = Node::Type::Mapping;
                ++at;
                ws();
                if (take('}')) return out;
                while (ok) {
                    Node key_node = scalar(true);
                    if (!key_node.is_map() && key_node.type != Node::Type::Scalar) {
                        ok = false;
                        return {};
                    }
                    ws();
                    if (!take(':')) {
                        ok = false;
                        return {};
                    }
                    Node value = node();
                    if (out.find(key_node.value)) {
                        ok = false;
                        return {};
                    }
                    out.entries.emplace_back(std::move(key_node), std::move(value));
                    ws();
                    if (take('}')) return out;
                    if (!take(',')) {
                        ok = false;
                        return {};
                    }
                }
                return out;
            }
        }
        return scalar(key);
    }
};

struct Parser {
    std::vector<Line> lines;
    std::unordered_map<std::string, Node> anchors;
    size_t at = 0;
    bool ok = true;
    size_t nodes = 0;
    int depth = 0;
    struct Guard {
        int& value;
        explicit Guard(int& target) : value(target) { ++value; }
        ~Guard() { --value; }
    };
    bool bump(size_t count = 1) {
        nodes += count;
        return nodes <= 8'000'000;
    }

    bool flow_value(std::string& value, size_t& index) {
        // Pull continuation lines until quotes and flow brackets balance.
        while (unbalanced(value)) {
            if (index + 1 >= lines.size()) return false;
            ++index;
            value += " " + lines[index].text;
        }
        Flow flow{value, 0, true, &anchors, &nodes};
        Node node = flow.node();
        if (!flow.ok) return false;
        flow.ws();
        if (flow.at != value.size()) return false;
        parsed = std::move(node);
        return true;
    }
    Node parsed;

    // Consumes an optional block anchor or alias from the start of a value.
    bool take_anchor(std::string& rest, std::string& name, bool& alias) {
        rest = trim_plain(rest);
        alias = false;
        if (rest.empty() || (rest.front() != '&' && rest.front() != '*')) return true;
        alias = rest.front() == '*';
        size_t end = 1;
        while (end < rest.size() && !is_space(rest[end]) && std::string_view("[{,]}").find(rest[end]) == std::string_view::npos) ++end;
        name = rest.substr(1, end - 1);
        if (name.empty()) return false;
        rest = trim_plain(std::string_view(rest).substr(end));
        return true;
    }
    // Parses one `key: value` entry starting at lines[index]; advances past it.
    bool entry(std::string_view content, size_t& index, Node& key, Node& value) {
        const Size colon = find_colon(content);
        if (colon == kNpos) return false;
        RawScalar key_raw;
        if (!parse_block_scalar_token(content.substr(0, colon), key_raw)) return false;
        key = scalar_node(std::move(key_raw));
        if (key.type != Node::Type::Scalar) return false;
        std::string rest = trim_plain(content.substr(colon + 1));
        std::string anchor;
        bool alias = false;
        if (!take_anchor(rest, anchor, alias)) return false;
        if (alias) {
            const auto found = anchors.find(anchor);
            if (found == anchors.end() || !rest.empty() || !bump(count_nodes(found->second))) return false;
            value = found->second;
            return true;
        }
        const bool anchored = !anchor.empty();
        if (rest.empty()) {
            ++index;
            if (index < lines.size() && lines[index].indent > lines[index - 1].indent) {
                value = block(lines[index].indent);
            } else {
                value = Node{};
            }
        } else if (rest.front() == '[' || rest.front() == '{') {
            if (!flow_value(rest, index)) return false;
            value = std::move(parsed);
            ++index;
        } else if (rest.front() == '|' || rest.front() == '>') {
            const bool literal = rest.front() == '|';
            const int parent = lines[index].indent;
            ++index;
            std::string text;
            bool first = true;
            while (index < lines.size() && lines[index].indent > parent) {
                if (!first) text += literal ? "\n" : " ";
                text += lines[index].text;
                first = false;
                ++index;
            }
            value.type = Node::Type::Scalar;
            value.value = std::move(text);
            value.quoted = true;
        } else {
            RawScalar raw;
            if (!parse_block_scalar_token(rest, raw)) return false;
            value = scalar_node(std::move(raw));
            ++index;
        }
        if (anchored && ok) anchors[anchor] = value;
        return ok;
    }
    Node block(int indent) {
        if (!ok || depth >= 128 || !bump()) {
            ok = false;
            return {};
        }
        Guard guard(depth);
        if (at >= lines.size() || lines[at].indent != indent) return {};
        const std::string& first = lines[at].text;
        if (first == "-" || first.rfind("- ", 0) == 0) return sequence(indent);
        if (find_colon(first) != kNpos) return mapping(indent);
        // A bare scalar document.
        RawScalar raw;
        if (!parse_block_scalar_token(first, raw)) {
            ok = false;
            return {};
        }
        ++at;
        return scalar_node(std::move(raw));
    }
    Node mapping(int indent) {
        Node out;
        out.type = Node::Type::Mapping;
        while (ok && at < lines.size() && lines[at].indent == indent) {
            if (lines[at].text == "-" || lines[at].text.rfind("- ", 0) == 0) break;
            Node key, value;
            const size_t index = at;
            if (!entry(lines[at].text, at, key, value)) {
                ok = false;
                return {};
            }
            if (at == index) {
                ok = false;
                return {};
            }
            if (out.find(key.value)) {
                ok = false;
                return {};
            }
            out.entries.emplace_back(std::move(key), std::move(value));
        }
        return out;
    }
    Node sequence(int indent) {
        Node out;
        out.type = Node::Type::Sequence;
        while (ok && at < lines.size() && lines[at].indent == indent) {
            const std::string& line = lines[at].text;
            if (line != "-" && line.rfind("- ", 0) != 0) break;
            std::string rest = line == "-" ? std::string() : trim_plain(std::string_view(line).substr(2));
            std::string anchor;
            bool alias = false;
            if (!take_anchor(rest, anchor, alias)) {
                ok = false;
                return {};
            }
            if (alias) {
                const auto found = anchors.find(anchor);
                if (found == anchors.end() || !rest.empty() || !bump(count_nodes(found->second))) {
                    ok = false;
                    return {};
                }
                out.items.push_back(found->second);
                ++at;
                continue;
            }
            const bool anchored = !anchor.empty();
            if (rest.empty()) {
                ++at;
                if (at < lines.size() && lines[at].indent > indent) out.items.push_back(block(lines[at].indent));
                else out.items.emplace_back();
                if (anchored) anchors[anchor] = out.items.back();
                continue;
            }
            if (rest.front() == '[' || rest.front() == '{') {
                if (!flow_value(rest, at)) {
                    ok = false;
                    return {};
                }
                out.items.push_back(std::move(parsed));
                ++at;
                if (anchored) anchors[anchor] = out.items.back();
                continue;
            }
            if (find_colon(rest) != kNpos) {
                // A map item whose first entry shares the dash line.
                Node item;
                item.type = Node::Type::Mapping;
                const int map_indent = indent + 2;
                size_t index = at;
                // The first entry uses this line with the dash removed.
                if (!entry(rest, index, item.entries.emplace_back().first, item.entries.back().second)) {
                    ok = false;
                    return {};
                }
                at = index;
                while (ok && at < lines.size() && lines[at].indent == map_indent) {
                    Node key, value;
                    if (!entry(lines[at].text, at, key, value)) {
                        ok = false;
                        return {};
                    }
                    if (item.find(key.value)) {
                        ok = false;
                        return {};
                    }
                    item.entries.emplace_back(std::move(key), std::move(value));
                }
                out.items.push_back(std::move(item));
                if (anchored) anchors[anchor] = out.items.back();
                continue;
            }
            RawScalar raw;
            if (!parse_block_scalar_token(rest, raw)) {
                ok = false;
                return {};
            }
            out.items.push_back(scalar_node(std::move(raw)));
            ++at;
            if (anchored) anchors[anchor] = out.items.back();
        }
        return out;
    }
};
bool safe_plain(std::string_view text, bool key) {
    if (text.empty()) return false;
    if (is_space(text.front()) || is_space(text.back())) return false;
    const std::string_view forbidden = "-?:,[]{}#&*!|>'\"%@`";
    if (forbidden.find(text.front()) != std::string_view::npos) return false;
    for (size_t i = 0; i < text.size(); ++i) {
        const auto c = static_cast<unsigned char>(text[i]);
        if (c < 0x20 || c == 0x7F) return false;
        if (c == ':' && i + 1 < text.size() && is_space(text[i + 1])) return false;
        if (c == '#' && i > 0 && is_space(text[i - 1])) return false;
    }
    if (is_null_word(text)) return false;
    const std::string lower(text);
    if (lower == "true" || lower == "false" || lower == "yes" || lower == "no" || lower == "on" || lower == "off") return false;
    if (key) {
        // A plain numeric key would become a number instead of a string.
        std::string_view number = text;
        if (!number.empty() && (number.front() == '+' || number.front() == '-')) number.remove_prefix(1);
        if (!number.empty() && std::all_of(number.begin(), number.end(), [](char c) { return (c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E'; })) return false;
    }
    return true;
}
std::string quote_text(std::string_view text) {
    std::string out = "\"";
    for (const char c : text) {
        const auto byte = static_cast<unsigned char>(c);
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\t': out += "\\t"; break;
            case '\r': out += "\\r"; break;
            default:
                if (byte < 0x20 || byte == 0x7F) {
                    static constexpr char hex[] = "0123456789abcdef";
                    out += "\\u00";
                    out += hex[byte >> 4];
                    out += hex[byte & 15];
                } else {
                    out += c;
                }
        }
    }
    return out + "\"";
}
std::string inline_node(const Node& node, bool key) {
    if (node.type == Node::Type::Null) return "null";
    if (node.type == Node::Type::Scalar) {
        if (node.quoted || !safe_plain(node.value, key)) return quote_text(node.value);
        return node.value;
    }
    if (node.type == Node::Type::Sequence && node.items.empty()) return "[]";
    if (node.type == Node::Type::Mapping && node.entries.empty()) return "{}";
    return {};
}
void emit_node(std::string& out, const Node& node, int indent) {
    if (node.type == Node::Type::Mapping && !node.entries.empty()) {
        bool first = true;
        for (const auto& [key, value] : node.entries) {
            if (!first) out += "\n";
            first = false;
            out.append(static_cast<size_t>(indent), ' ');
            const std::string inline_key = inline_node(key, true);
            out += inline_key.empty() ? quote_text(key.value) : inline_key;
            out += ':';
            const std::string inline_value = inline_node(value, false);
            if (!inline_value.empty()) {
                out += ' ';
                out += inline_value;
            } else {
                out += '\n';
                emit_node(out, value, indent + 2);
            }
        }
        return;
    }
    if (node.type == Node::Type::Sequence && !node.items.empty()) {
        bool first = true;
        for (const Node& item : node.items) {
            if (!first) out += "\n";
            first = false;
            out.append(static_cast<size_t>(indent), ' ');
            out += '-';
            const std::string inline_item = inline_node(item, false);
            if (!inline_item.empty()) {
                out += ' ';
                out += inline_item;
            } else {
                out += '\n';
                emit_node(out, item, indent + 2);
            }
        }
        return;
    }
    out += inline_node(node, false);
}
}  // namespace

const Node* Node::find(std::string_view key) const {
    for (const auto& [candidate, value] : entries) {
        if (candidate.value == key) return &value;
    }
    return nullptr;
}
Node* Node::find(std::string_view key) {
    for (auto& [candidate, value] : entries) {
        if (candidate.value == key) return &value;
    }
    return nullptr;
}
void Node::remove(std::string_view key) {
    std::erase_if(entries, [&](const auto& item) { return item.first.value == key; });
}
std::optional<Node> parse(std::string_view text) {
    if (!valid_utf8(text)) return std::nullopt;
    std::vector<Line> lines;
    bool saw_content = false;
    size_t at = 0;
    while (at <= text.size()) {
        const size_t end = std::min(text.find('\n', at), text.size());
        std::string_view raw = text.substr(at, end - at);
        if (!raw.empty() && raw.back() == '\r') raw.remove_suffix(1);
        int indent = 0;
        size_t lead = 0;
        while (lead < raw.size() && raw[lead] == ' ') {
            ++indent;
            ++lead;
        }
        if (lead < raw.size() && raw[lead] == '\t') return std::nullopt;  // Tabs as indentation are refused.
        std::string content = strip_comment(raw.substr(lead));
        while (!content.empty() && is_space(content.back())) content.pop_back();
        if (content.empty()) {
            at = end + 1;
            continue;
        }
        const std::string trimmed = trim_plain(content);
        if (trimmed == "---" || trimmed == "...") {
            if (saw_content) return std::nullopt;  // Only a single document is supported.
            at = end + 1;
            continue;
        }
        if (trimmed.rfind('%', 0) == 0) {
            at = end + 1;
            continue;
        }
        // Reject a second document within the body.
        if (saw_content && indent == 0 && content.rfind("---", 0) == 0) return std::nullopt;
        saw_content = true;
        lines.push_back(Line{indent, std::move(content)});
        at = end + 1;
        if (end == text.size()) break;
    }
    if (lines.empty()) return Node{};
    Parser parser;
    parser.lines = std::move(lines);
    Node root = parser.block(parser.lines.front().indent);
    if (!parser.ok || parser.at != parser.lines.size()) return std::nullopt;
    return root;
}
std::string emit(const Node& root) {
    std::string out;
    emit_node(out, root, 0);
    out += '\n';
    return out;
}
Node scalar(std::string text) {
    Node node;
    if (is_null_word(text)) {
        node.type = Node::Type::Null;
        return node;
    }
    node.type = Node::Type::Scalar;
    node.value = std::move(text);
    node.quoted = false;
    return node;
}
Node quoted_scalar(std::string text) {
    Node node;
    node.type = Node::Type::Scalar;
    node.value = std::move(text);
    node.quoted = true;
    return node;
}
}  // namespace clash::yaml
