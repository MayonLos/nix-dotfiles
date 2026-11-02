// Minimal YAML 1.1 subset for Clash subscription files and the saved baseline.
// It is deliberately conservative: unsupported syntax (multi-document files, complex
// tags, merge keys) is refused instead of guessed, because the output becomes a
// privileged runtime configuration. Plain and quoted scalars keep their original
// style so proxy values round-trip with the same types.
#pragma once
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace clash::yaml {
struct Node {
    enum class Type { Null, Scalar, Sequence, Mapping };

    Type type = Type::Null;
    std::string value;                  // Decoded text of a scalar.
    bool quoted = false;                // Emit as a double-quoted string.
    std::vector<Node> items;            // Sequence.
    std::vector<std::pair<Node, Node>> entries;  // Mapping; keys are scalars.

    bool is_map() const { return type == Type::Mapping; }
    bool is_seq() const { return type == Type::Sequence; }
    bool is_null() const { return type == Type::Null; }
    const Node* find(std::string_view key) const;
    Node* find(std::string_view key);
    void remove(std::string_view key);
};

// Null on malformed input, duplicate keys, multiple documents or unsupported syntax.
std::optional<Node> parse(std::string_view text);
// Block-style output ending in a newline. Always valid YAML for the same value.
std::string emit(const Node& root);

// A plain scalar (kept unquoted when possible) or a double-quoted string.
Node scalar(std::string text);
Node quoted_scalar(std::string text);
}  // namespace clash::yaml
