// Non-interactive entrypoints use the same transactions as the TUI. A subscription
// URL is read from stdin only, never from argv, so it cannot leak into process lists.
#include <algorithm>
#include <cstdlib>
#include <istream>
#include <ostream>
#include <string>
#include <vector>

#include "app.hpp"

namespace clash {
namespace {
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
std::string read_stdin_url(std::istream& in, std::string& error) {
    char buffer[16385];
    in.read(buffer, sizeof buffer);
    const std::streamsize got = in.gcount();
    if (in.bad() || (!in.eof() && in.fail())) {
        error = "无法读取 URL";
        return {};
    }
    std::string raw(buffer, static_cast<size_t>(std::max<std::streamsize>(got, 0)));
    if (!valid_utf8(raw)) {
        error = "无法读取 URL";
        return {};
    }
    if (raw.size() > 16384) {
        error = "URL 过长";
        return {};
    }
    const auto first = raw.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const auto last = raw.find_last_not_of(" \t\r\n");
    return raw.substr(first, last - first + 1);
}
}  // namespace

int run_cli(const std::vector<std::string>& raw, std::istream& in, std::ostream& out, std::ostream& err) {
    if (raw.empty() || !(raw.front() == "profile" || raw.front() == "settings" || raw.front() == "service")) return -1;
    const auto fail = [&](const std::string& message) {
        err << "Clash TUI：" << message << "\n";
        return 1;
    };
    const char* home = std::getenv("HOME");
    if (!home) return fail("缺少 HOME");
    Native ctx;
    ctx.data = std::filesystem::path(home) / ".local/share/mayon-clash";
    ctx.socket = "/run/mayon-clash/mihomo.sock";
    ctx.mihomo = "mihomo";
    ctx.systemctl = "systemctl";
    std::vector<std::string> args;
    for (size_t i = 0; i < raw.size(); ++i) {
        const std::string& arg = raw[i];
        if (arg == "--data-dir" || arg == "--socket" || arg == "--mihomo" || arg == "--systemctl") {
            if (i + 1 >= raw.size()) return fail(arg == "--socket" ? "缺少 socket" : arg == "--data-dir" ? "缺少目录" : "缺少命令");
            const std::string value = raw[++i];
            if (arg == "--data-dir") ctx.data = value;
            else if (arg == "--socket") ctx.socket = value;
            else if (arg == "--mihomo") ctx.mihomo = value;
            else ctx.systemctl = value;
        } else {
            args.push_back(arg);
        }
    }
    const bool running = Client{ctx.socket, nullptr}.version().has_value();
    const auto get = [&](size_t index) -> std::optional<std::string> {
        if (index >= args.size()) return std::nullopt;
        return args[index];
    };
    const auto missing = [&] { return fail("缺少参数"); };
    if (!get(0)) return missing();
    const std::string command = *get(0);
    if (command == "profile") {
        if (!get(1)) return missing();
        const std::string action = *get(1);
        if (action == "add") {
            std::string error;
            const std::string url = read_stdin_url(in, error);
            if (!error.empty()) return fail(error);
            const auto result = ctx.add(url, get(2).value_or(""), running);
            if (!result) return fail(result.error());
        } else if (action == "list") {
            const auto store = ctx.store();
            if (!store) return fail(store.error());
            for (const Subscription& item : store->items) out << item.id << '\t' << item.name << '\n';
        } else if (action == "update") {
            if (!get(2)) return missing();
            if (*get(2) == "all") {
                const auto store = ctx.store();
                if (!store) return fail(store.error());
                for (const Subscription& item : store->items) {
                    const auto result = ctx.update(item.id, running, std::nullopt);
                    if (!result) return fail(result.error());
                }
            } else {
                const auto result = ctx.update(*get(2), running, std::nullopt);
                if (!result) return fail(result.error());
            }
        } else if (action == "use") {
            if (!get(2)) return missing();
            const auto result = ctx.select(*get(2), running);
            if (!result) return fail(result.error());
        } else if (action == "rename") {
            if (!get(2) || !get(3)) return missing();
            const auto result = ctx.rename(*get(2), *get(3));
            if (!result) return fail(result.error());
        } else if (action == "url") {
            if (!get(2)) return missing();
            std::string error;
            const std::string url = read_stdin_url(in, error);
            if (!error.empty()) return fail(error);
            const auto result = ctx.update(*get(2), running, url);
            if (!result) return fail(result.error());
        } else if (action == "delete") {
            if (!get(2)) return missing();
            if (!get(3)) return missing();
            if (*get(3) != "--yes") return fail("删除需要 --yes；当前订阅不可删除");
            const auto result = ctx.remove(*get(2));
            if (!result) return fail(result.error());
        } else if (action == "generate") {
            const auto result = ctx.generate();
            if (!result) return fail(result.error());
        } else {
            return fail("非交互命令无效，参见 README");
        }
        return 0;
    }
    if (command == "settings") {
        if (!get(1) || !get(2)) return missing();
        const auto result = ctx.change(*get(1), *get(2), running);
        if (!result) return fail(result.error());
        return 0;
    }
    if (command == "service") {
        if (!get(1)) return missing();
        if (*get(1) == "start") {
            const auto generated = ctx.generate();
            if (!generated) return fail(generated.error());
            const auto result = ctx.service("start");
            if (!result) return fail(result.error());
            return 0;
        }
        if (*get(1) == "stop") {
            const auto result = ctx.service("stop");
            if (!result) return fail(result.error());
            return 0;
        }
        return fail("非交互命令无效，参见 README");
    }
    return fail("非交互命令无效，参见 README");
}
}  // namespace clash
