#include "vm_xml.hpp"

#include <charconv>
#include <cstdint>
#include <stdexcept>

#include "ui/text.hpp"

namespace dock::xml {
namespace {
using Fail = std::runtime_error;
bool name_start(unsigned char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == ':'; }
bool name_byte(unsigned char c) { return name_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.'; }
char32_t xml_char(uint32_t value) {
    const bool valid = value == 0x9 || value == 0xA || value == 0xD || (value >= 0x20 && value <= 0xD7FF) || (value >= 0xE000 && value <= 0xFFFD) || (value >= 0x10000 && value <= 0x10FFFF);
    if (!valid) throw Fail("XML character reference is not a valid XML code point");
    return value;
}
uint32_t reference(std::string_view digits, int base, const char* error) {
    if (digits.starts_with('+')) digits.remove_prefix(1);
    uint32_t value = 0;
    const auto [end, code] = std::from_chars(digits.data(), digits.data() + digits.size(), value, base);
    if (digits.empty() || code != std::errc{} || end != digits.data() + digits.size()) throw Fail(error);
    return value;
}
std::string decode_entities(std::string_view raw) {
    std::string out;
    out.reserve(raw.size());
    size_t cursor = 0;
    for (size_t start = 0; (start = raw.find('&', cursor)) != std::string_view::npos;) {
        out += raw.substr(cursor, start - cursor);
        const size_t end = raw.find(';', start + 1);
        if (end == std::string_view::npos) throw Fail("unterminated XML entity");
        const std::string_view entity = raw.substr(start + 1, end - start - 1);
        if (entity == "amp") out += '&';
        else if (entity == "lt") out += '<';
        else if (entity == "gt") out += '>';
        else if (entity == "quot") out += '"';
        else if (entity == "apos") out += '\'';
        else if (entity.starts_with("#x") || entity.starts_with("#X")) tui::append(out, xml_char(reference(entity.substr(2), 16, "invalid hexadecimal XML character reference")));
        else if (entity.starts_with('#')) tui::append(out, xml_char(reference(entity.substr(1), 10, "invalid decimal XML character reference")));
        else throw Fail("unknown XML entity &" + std::string(entity) + ";");
        cursor = end + 1;
    }
    out += raw.substr(cursor);
    return out;
}
struct Parser {
    std::string_view input;
    size_t cursor = 0;
    std::string_view rest() const { return input.substr(cursor); }
    bool starts(std::string_view s) const { return rest().starts_with(s); }
    void skip_space() {
        while (cursor < input.size()) {
            const char c = input[cursor];
            if (c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\f') break;
            ++cursor;
        }
    }
    void skip_until(std::string_view end, const char* error) {
        const size_t offset = rest().find(end);
        if (offset == std::string_view::npos) throw Fail(error);
        cursor += offset + end.size();
    }
    void skip_misc() {
        while (true) {
            skip_space();
            if (starts("<!--")) skip_until("-->", "unterminated XML comment");
            else if (starts("<?")) skip_until("?>", "unterminated XML processing instruction");
            else if (starts("<!")) throw Fail("DTD and declarations are not supported");
            else return;
        }
    }
    void expect(std::string_view token) {
        if (!starts(token)) throw Fail("expected \"" + std::string(token) + "\" in XML");
        cursor += token.size();
    }
    std::string name() {
        const size_t start = cursor;
        if (cursor >= input.size() || !name_start(static_cast<unsigned char>(input[cursor]))) throw Fail("expected XML name");
        ++cursor;
        while (cursor < input.size() && name_byte(static_cast<unsigned char>(input[cursor]))) ++cursor;
        return std::string(input.substr(start, cursor - start));
    }
    Node element(size_t depth) {
        if (depth > kMaxDepth) throw Fail("XML nesting exceeds 64 elements");
        expect("<");
        if (starts("/") || starts("!") || starts("?")) throw Fail("expected opening XML element");
        Node node;
        node.name = name();
        while (true) {
            skip_space();
            if (starts("/>")) {
                cursor += 2;
                return node;
            }
            if (starts(">")) {
                ++cursor;
                break;
            }
            std::string key = name();
            if (node.attrs.contains(key)) throw Fail("duplicate XML attribute " + key);
            skip_space();
            expect("=");
            skip_space();
            if (cursor >= input.size()) throw Fail("missing XML attribute value");
            const char quote = input[cursor];
            if (quote != '\'' && quote != '"') throw Fail("XML attributes must use quotes");
            ++cursor;
            const size_t offset = rest().find(quote);
            if (offset == std::string_view::npos) throw Fail("unterminated XML attribute value");
            const std::string_view raw = input.substr(cursor, offset);
            if (raw.find('<') != std::string_view::npos) throw Fail("XML attribute contains an unescaped '<'");
            node.attrs.emplace(std::move(key), decode_entities(raw));
            cursor += offset + 1;
        }
        while (true) {
            if (cursor >= input.size()) throw Fail("unterminated XML element " + node.name);
            if (starts("</")) {
                cursor += 2;
                const std::string close = name();
                skip_space();
                expect(">");
                if (close != node.name) throw Fail("mismatched closing element: expected " + node.name + ", got " + close);
                return node;
            }
            if (starts("<!--")) {
                skip_until("-->", "unterminated XML comment");
            } else if (starts("<?")) {
                skip_until("?>", "unterminated XML processing instruction");
            } else if (starts("<![CDATA[")) {
                cursor += 9;
                const size_t offset = rest().find("]]>");
                if (offset == std::string_view::npos) throw Fail("unterminated XML CDATA section");
                node.text += input.substr(cursor, offset);
                cursor += offset + 3;
            } else if (starts("<!")) {
                throw Fail("DTD and declarations are not supported");
            } else if (starts("<")) {
                node.children.push_back(element(depth + 1));
            } else {
                const size_t offset = rest().find('<');
                if (offset == std::string_view::npos) throw Fail("unterminated XML element " + node.name);
                node.text += decode_entities(input.substr(cursor, offset));
                cursor += offset;
            }
        }
    }
};
void collect(const Node& node, std::string_view wanted, std::vector<const Node*>& found) {
    for (const Node& child : node.children) {
        if (child.name == wanted) found.push_back(&child);
        collect(child, wanted, found);
    }
}
}  // namespace
const Node* Node::child(std::string_view wanted) const {
    for (const Node& node : children) {
        if (node.name == wanted) return &node;
    }
    return nullptr;
}
const std::string* Node::attr(const std::string& key) const {
    const auto it = attrs.find(key);
    return it == attrs.end() ? nullptr : &it->second;
}
std::vector<const Node*> Node::descendants(std::string_view wanted) const {
    std::vector<const Node*> found;
    collect(*this, wanted, found);
    return found;
}
std::expected<Node, std::string> parse(std::string_view input) {
    if (input.size() > kMaxInput) return std::unexpected("XML exceeds 4 MiB limit");
    try {
        Parser parser{input};
        parser.skip_misc();
        if (parser.cursor == input.size()) return std::unexpected("XML has no root element");
        Node root = parser.element(1);
        parser.skip_misc();
        if (parser.cursor != input.size()) return std::unexpected("content follows the XML root element");
        return root;
    } catch (const Fail& error) {
        return std::unexpected(error.what());
    }
}
}  // namespace dock::xml
