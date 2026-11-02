// Disk accounting and a frozen, explicitly reviewed cleanup plan. Private to this tool.
#pragma once
#include <array>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "api.hpp"
#include "ui/input.hpp"

namespace dock {
enum class Kind { Image, Container, Volume, Cache };
inline constexpr std::array<Kind, 4> kAllKinds{Kind::Image, Kind::Container, Kind::Volume, Kind::Cache};
const char* label(Kind kind);
std::string human_bytes(uint64_t value);
std::string bytes(std::optional<uint64_t> size);
struct Entry {
    Kind kind = Kind::Image;
    std::string id, name;
    std::optional<uint64_t> size, reclaim;
    std::optional<std::string> blocked;
    std::string key() const;
    bool selectable() const { return !id.empty() && !blocked; }
    std::string description() const;
    bool operator==(const Entry&) const = default;
};
// Unknown reference counts fail closed. Referenced images and volumes stay locked even when
// the referring container is stopped; deleting that container is a separate plan.
std::vector<Entry> entries(const Disk& disk);
std::vector<Entry> selected(const std::vector<Entry>& rows, const std::set<std::string>& keys);
std::string estimate(const std::vector<Entry>& plan);
// (total, unknown count); saturates instead of wrapping.
std::pair<uint64_t, size_t> sum_sizes(const std::vector<std::optional<uint64_t>>& values);
struct SummaryRow {
    std::string label, total, reclaim;
};
std::vector<SummaryRow> summary_rows(const Disk& disk);
std::string summary(const Disk& disk);
std::optional<uint64_t> physical_usage(const Disk& disk);
enum class Stage { Preview, Confirm, Volumes };
class Flow {
public:
    static std::optional<Flow> create(std::vector<Entry> plan);
    std::string volume_phrase() const;
    // Returns the authorized frozen plan only after preview AND second confirmation.
    std::optional<std::vector<Entry>> handle_key(const tui::Key& key);
    std::string body() const;
    std::vector<Entry> plan;
    Stage stage = Stage::Preview;
    size_t cursor = 0;
    tui::TextInput input;

private:
    size_t seen_ = 0;
    size_t volume_cursor_ = 0;
};
struct Report {
    std::vector<std::string> lines;
    size_t failed = 0;
    std::string body() const;
};
// Every mutation is scoped to one reviewed ID, non-forcing, and preceded by a fresh snapshot.
// Engine conflict checks remain the final race protection.
Report execute(const Engine& engine, const std::vector<Entry>& plan);
}  // namespace dock
