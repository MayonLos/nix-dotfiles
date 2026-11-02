// Bounded parser for libvirt XML metadata. It never resolves entities or reads files.
#pragma once
#include <expected>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace dock::xml {
inline constexpr size_t kMaxInput = 4 * 1024 * 1024;
inline constexpr size_t kMaxDepth = 64;
struct Node {
    std::string name;
    std::map<std::string, std::string> attrs;
    std::string text;
    std::vector<Node> children;
    const Node* child(std::string_view wanted) const;
    const std::string* attr(const std::string& key) const;
    // Matching nodes below this node in document order.
    std::vector<const Node*> descendants(std::string_view wanted) const;
};
std::expected<Node, std::string> parse(std::string_view input);
}  // namespace dock::xml
