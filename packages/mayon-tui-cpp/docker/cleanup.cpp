#include "cleanup.hpp"

#include <algorithm>
#include <format>
#include <limits>

#include "ui/draw.hpp"

namespace dock {
namespace {
std::optional<uint64_t> positive(std::optional<int64_t> value) {
    if (!value || *value < 0) return std::nullopt;
    return static_cast<uint64_t>(*value);
}
const json* get(const json& value, const char* name) {
    if (!value.is_object()) return nullptr;
    const auto it = value.find(name);
    return it == value.end() ? nullptr : &*it;
}
std::optional<uint64_t> number(const json& value, const char* name) {
    const json* item = get(value, name);
    if (!item || !item->is_number_integer()) return std::nullopt;
    if (item->is_number_unsigned() && item->get<uint64_t>() > static_cast<uint64_t>(std::numeric_limits<int64_t>::max())) return std::nullopt;
    return positive(item->get<int64_t>());
}
std::string text(const json& value, const char* name) {
    const json* item = get(value, name);
    return item && item->is_string() ? item->get<std::string>() : std::string();
}
uint64_t add_saturating(uint64_t a, uint64_t b) { return a > std::numeric_limits<uint64_t>::max() - b ? std::numeric_limits<uint64_t>::max() : a + b; }
bool add_checked(uint64_t& total, uint64_t n) {
    if (total > std::numeric_limits<uint64_t>::max() - n) return false;
    total += n;
    return true;
}
std::string join(const std::vector<std::string>& items, std::string_view by) {
    std::string out;
    for (size_t i = 0; i < items.size(); ++i) {
        if (i) out += by;
        out += items[i];
    }
    return out;
}
size_t volume_count(const std::vector<Entry>& plan) {
    return static_cast<size_t>(std::count_if(plan.begin(), plan.end(), [](const Entry& e) { return e.kind == Kind::Volume; }));
}
}  // namespace
const char* label(Kind kind) {
    switch (kind) {
        case Kind::Image: return "镜像";
        case Kind::Container: return "容器";
        case Kind::Volume: return "卷";
        case Kind::Cache: return "构建缓存";
    }
    return "";
}
std::string human_bytes(uint64_t value) {
    auto size = static_cast<double>(value);
    const char* unit = "B";
    for (const char* next : {"KiB", "MiB", "GiB", "TiB"}) {
        if (size < 1024.0) break;
        size /= 1024.0;
        unit = next;
    }
    return std::format("{:.1f} {}", size, unit);
}
std::string bytes(std::optional<uint64_t> size) { return size ? human_bytes(*size) : "未知"; }
std::string Entry::key() const { return std::string(label(kind)) + ":" + id; }
std::string Entry::description() const { return std::format("{} · ID / 名称：{}\n{}\n占用 {} · 预计释放 {}", label(kind), id, tui::clip(name, 64), bytes(size), bytes(reclaim)); }
std::vector<Entry> entries(const Disk& disk) {
    std::vector<Entry> out;
    for (const ImageDisk& image : disk.images) {
        const bool used = image.containers != 0 || std::any_of(disk.containers.begin(), disk.containers.end(), [&](const json& c) { return text(c, "ImageID") == image.id; });
        Entry row;
        row.kind = Kind::Image;
        row.id = image.id;
        row.name = is_dangling(image.tags) ? "<悬空>" : join(image.tags, ", ");
        row.size = image.size;
        if (const auto shared = positive(image.shared)) row.reclaim = image.size > *shared ? image.size - *shared : 0;
        if (used) row.blocked = "被引用 / 未知";
        out.push_back(std::move(row));
    }
    for (const json& c : disk.containers) {
        const std::string state = text(c, "State");
        const bool stopped = state == "exited" || state == "created" || state == "dead";
        std::string name;
        if (const json* names = get(c, "Names"); names && names->is_array() && !names->empty() && names->front().is_string()) name = names->front().get<std::string>();
        while (name.starts_with('/')) name.erase(0, 1);
        Entry row;
        row.kind = Kind::Container;
        row.id = text(c, "Id");
        row.name = std::format("{} ({})", name, state);
        row.size = number(c, "SizeRw");
        row.reclaim = row.size;
        if (!stopped) row.blocked = "运行中 / 未知";
        out.push_back(std::move(row));
    }
    for (const Volume& v : disk.volumes) {
        const bool referenced = std::any_of(disk.containers.begin(), disk.containers.end(), [&](const json& c) {
            const json* mounts = get(c, "Mounts");
            return mounts && mounts->is_array() && std::any_of(mounts->begin(), mounts->end(), [&](const json& m) { return text(m, "Type") == "volume" && text(m, "Name") == v.name; });
        });
        const bool unused = v.usage && v.usage->refs == 0 && !referenced;
        Entry row;
        row.kind = Kind::Volume;
        row.id = v.name;
        row.name = v.name;
        if (v.usage) row.size = positive(v.usage->size);
        row.reclaim = row.size;
        if (!unused) row.blocked = "被引用 / 未知";
        out.push_back(std::move(row));
    }
    for (const BuildDisk& b : disk.build_cache) {
        Entry row;
        row.kind = Kind::Cache;
        row.id = b.id;
        row.name = b.description;
        row.size = b.size;
        row.reclaim = b.is_shared ? 0 : b.size;
        if (b.in_use || b.is_shared) {
            row.blocked = "InUse / Shared：保护";
        } else {
            try {
                cache_prune_path(b.id);
            } catch (const std::exception&) {
                row.blocked = "ID 不支持精确清理";
            }
        }
        out.push_back(std::move(row));
    }
    std::stable_sort(out.begin(), out.end(), [](const Entry& a, const Entry& b) {
        if (a.size != b.size) return a.size > b.size;  // Unknown sorts last.
        return a.key() < b.key();
    });
    return out;
}
std::vector<Entry> selected(const std::vector<Entry>& rows, const std::set<std::string>& keys) {
    std::vector<Entry> out;
    for (const Entry& row : rows) {
        if (row.selectable() && keys.contains(row.key())) out.push_back(row);
    }
    return out;
}
std::pair<uint64_t, size_t> sum_sizes(const std::vector<std::optional<uint64_t>>& values) {
    uint64_t total = 0;
    size_t unknown = 0;
    for (const auto& value : values) {
        if (value) total = add_saturating(total, *value);
        else ++unknown;
    }
    return {total, unknown};
}
std::string estimate(const std::vector<Entry>& plan) {
    std::vector<std::optional<uint64_t>> values;
    for (const Entry& row : plan) values.push_back(row.reclaim);
    const auto [size, unknown] = sum_sizes(values);
    return human_bytes(size) + (unknown > 0 ? std::format(" + {} 项未知", unknown) : "");
}
std::vector<SummaryRow> summary_rows(const Disk& disk) {
    const auto rows = entries(disk);
    std::vector<SummaryRow> out;
    for (const Kind kind : kAllKinds) {
        std::vector<std::optional<uint64_t>> sizes;
        std::vector<Entry> reclaim;
        for (const Entry& row : rows) {
            if (row.kind != kind) continue;
            sizes.push_back(row.size);
            if (row.selectable()) reclaim.push_back(row);
        }
        std::string total;
        if (kind == Kind::Image) {
            total = human_bytes(disk.layers_size);
        } else {
            const auto [n, unknown] = sum_sizes(sizes);
            total = human_bytes(n) + (unknown > 0 ? " + 未知" : "");
        }
        out.push_back(SummaryRow{label(kind), std::move(total), estimate(reclaim)});
    }
    return out;
}
std::string summary(const Disk& disk) {
    std::vector<std::string> lines{"分类         占用               安全可回收（估计）"};
    for (const SummaryRow& row : summary_rows(disk)) lines.push_back(std::format("{}：占用 {} · 可回收 {}", row.label, row.total, row.reclaim));
    lines.emplace_back("共享镜像层只计独占部分；Shared 缓存不清理；卷默认不选。");
    return join(lines, "\n");
}
// Excludes shared build cache, which image layers already account for.
std::optional<uint64_t> physical_usage(const Disk& disk) {
    uint64_t total = disk.layers_size;
    for (const json& c : disk.containers) {
        const auto n = number(c, "SizeRw");
        if (!n || !add_checked(total, *n)) return std::nullopt;
    }
    for (const Volume& v : disk.volumes) {
        if (!v.usage) return std::nullopt;
        const auto n = positive(v.usage->size);
        if (!n || !add_checked(total, *n)) return std::nullopt;
    }
    for (const BuildDisk& b : disk.build_cache) {
        if (!b.is_shared && !add_checked(total, b.size)) return std::nullopt;
    }
    return total;
}
std::optional<Flow> Flow::create(std::vector<Entry> plan) {
    if (plan.empty() || !std::all_of(plan.begin(), plan.end(), [](const Entry& e) { return e.selectable(); })) return std::nullopt;
    Flow flow;
    flow.plan = std::move(plan);
    return flow;
}
std::string Flow::volume_phrase() const {
    size_t index = 0;
    for (const Entry& e : plan) {
        if (e.kind != Kind::Volume) continue;
        if (index++ == volume_cursor_) return "DELETE " + e.id;
    }
    return "DELETE ";
}
std::optional<std::vector<Entry>> Flow::handle_key(const tui::Key& key) {
    using tui::KeyCode;
    if (stage != Stage::Volumes && (key.ctrl || key.alt)) return std::nullopt;
    switch (stage) {
        case Stage::Preview:
            if (key.code == KeyCode::Down || key.is(U'j')) {
                cursor = std::min(cursor + 1, plan.size() - 1);
                seen_ = std::max(seen_, cursor);
            } else if (key.code == KeyCode::Up || key.is(U'k')) {
                if (cursor > 0) --cursor;
            } else if (key.is(U'y') && seen_ + 1 == plan.size()) {
                stage = Stage::Confirm;
            }
            break;
        case Stage::Confirm:
            if (key.is(U'y')) {
                if (volume_count(plan) == 0) return plan;
                stage = Stage::Volumes;
            }
            break;
        case Stage::Volumes:
            if (key.code == KeyCode::Enter && input.str() == volume_phrase()) {
                ++volume_cursor_;
                if (volume_cursor_ == volume_count(plan)) return plan;
                input.clear();
            } else {
                input.handle(key);
            }
            break;
    }
    return std::nullopt;
}
std::string Flow::body() const {
    switch (stage) {
        case Stage::Preview:
            return std::format("预览准确清单 {}/{} · 总预计释放 {}\n\n{}\n\n只删除清单内 ID，不停止容器，不删除容器关联卷。\n卷数据不可恢复；卷需要另行输入名称确认。\n\nj/k 逐项查看 · 查看全部后 y 进入二次确认 · Esc 取消", cursor + 1, plan.size(), estimate(plan), plan[cursor].description());
        case Stage::Confirm:
            return std::format("二次确认：删除已预览的 {} 项？\n预计释放 {}（共享层、并发活动可能影响实际值）\n\n容器 writable layer、卷内数据删除后不可恢复。\n执行前重新验证引用状态；状态改变的项目跳过。\n\ny 确认 · Esc 取消", plan.size(), estimate(plan));
        case Stage::Volumes:
            return std::format("卷数据不可恢复！每个卷均需单独确认。\n输入以下完整文本，再按 Enter：\n\n{}\n\n输入：\n\nEsc 取消", volume_phrase());
    }
    return {};
}
std::string Report::body() const { return join(lines, "\n"); }
Report execute(const Engine& engine, const std::vector<Entry>& plan) {
    const auto usage = [&]() -> std::optional<uint64_t> {
        try {
            return physical_usage(engine.disk());
        } catch (const std::exception&) {
            return std::nullopt;
        }
    };
    Report report;
    const auto before = usage();
    uint64_t cache_reclaimed = 0;
    for (const Entry& entry : plan) {
        try {
            const auto fresh = entries(engine.disk());
            if (std::none_of(fresh.begin(), fresh.end(), [&](const Entry& e) { return e.kind == entry.kind && e.id == entry.id && e.selectable(); })) {
                throw std::runtime_error("状态改变、被引用或已不存在；跳过");
            }
            switch (entry.kind) {
                case Kind::Container: engine.remove_container(entry.id); break;
                case Kind::Image: engine.remove_image(entry.id); break;
                case Kind::Volume: engine.remove_volume(entry.id); break;
                case Kind::Cache: {
                    const json response = engine.remove_cache(entry.id);
                    const json* deleted = get(response, "CachesDeleted");
                    const bool confirmed = deleted && deleted->is_array() && std::any_of(deleted->begin(), deleted->end(), [&](const json& v) { return v.is_string() && v.get<std::string>() == entry.id; });
                    if (!confirmed) throw std::runtime_error("daemon 未确认删除此缓存（可能已在使用）");
                    const json* space = get(response, "SpaceReclaimed");
                    if (space && space->is_number_unsigned()) cache_reclaimed = add_saturating(cache_reclaimed, space->get<uint64_t>());
                    break;
                }
            }
            report.lines.push_back(std::format("已删除 {} {}", label(entry.kind), entry.id));
        } catch (const std::exception& error) {
            ++report.failed;
            report.lines.push_back(std::format("失败 {} {}：{}", label(entry.kind), entry.id, error.what()));
        }
    }
    const auto after = usage();
    std::optional<uint64_t> actual;
    if (before && after) actual = *before > *after ? *before - *after : 0;
    const std::vector<std::string> head{
        std::format("完成 {} 项 · 失败 {} 项", plan.size() - report.failed, report.failed),
        std::format("实际释放（daemon 占用前后差值）：{}", bytes(actual)),
        std::format("其中缓存 API SpaceReclaimed：{}", bytes(cache_reclaimed)),
        "占用差值受并发活动影响；未知大小或查询失败时不推算实际值。",
    };
    report.lines.insert(report.lines.begin(), head.begin(), head.end());
    return report;
}
}  // namespace dock
