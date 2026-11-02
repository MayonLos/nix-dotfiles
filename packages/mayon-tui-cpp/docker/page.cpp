// Public entry of the docker tool: the page the toolbox embeds and its command line.
// Everything else in this directory is private.
#include "page.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "app.hpp"
#include "cli.hpp"

namespace dock {
namespace {
const char* const kHelp =
    "mayon-tools docker 0.2.0\n"
    "\n"
    "--host unix:///path/docker.sock  Docker socket (overrides DOCKER_HOST)\n"
    "--help · --version\n"
    "\n"
    "无子命令：TUI，1 容器 · 2 镜像 · 3 卷 · 4 概览 · 5 清理 · ? 帮助\n"
    "\n"
    "df                              Docker + VM 只读空间总览与明细\n"
    "clean --image ID --container ID --cache ID --volume NAME [--yes]\n"
    "  可重复指定完整 ID/卷名；不支持全清，卷必须显式指定名字。\n"
    "  默认仅预览准确清单。执行必须 --yes，预览后输入 DELETE 再确认。\n"
    "  含卷还需单独输入 DELETE 与所有完整卷名；卷数据不可恢复。\n"
    "  运行中容器、被引用的镜像/卷、Shared/InUse 缓存不可清理。\n"
    "\n"
    "5 空间面板 Tab/v 切换 Docker / VM · VM 严格只读，Enter 详情/y 复制路径。\n"
    "VM 查询 qemu:///session 与 qemu:///system；绝不删除 VM、镜像、快照或 ISO。\n";

bool read_line(std::string& value) {
    if (!std::getline(std::cin, value)) return false;
    while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) value.pop_back();
    return true;
}
bool confirm_input(const std::string& prompt, const std::string& expected) {
    std::cout << prompt << "\n> " << std::flush;
    std::string value;
    read_line(value);
    return value == expected;
}
int run_df(const std::optional<std::string>& host) {
    try {
        Engine engine = Engine::create(host);
        const Disk disk = engine.disk();
        std::cout << cleanup::summary(disk) << "\n\nDocker 明细（占用降序；锁定项不可选）：\n";
        for (const cleanup::Entry& entry : cleanup::entries(disk)) {
            std::cout << entry.description() << "\n" << entry.blocked.value_or("可清理（卷默认不选）") << "\n\n";
        }
    } catch (const std::exception& error) {
        std::cout << "Docker 不可用：" << error.what() << "\n";
    }
    const vm::Inventory inventory = vm::collect();
    std::cout << "\n" << inventory.cli() << "\n";
    return 0;
}
int run_clean(const CliArgs& args) {
    Engine engine = Engine::create(args.host);
    const Disk disk = engine.disk();
    const std::vector<cleanup::Entry> entries = cleanup::entries(disk);
    const std::vector<cleanup::Entry> plan = plan_for(entries, args.targets);
    std::cout << "准确删除清单（预计释放 " << cleanup::estimate(plan) << "）：\n";
    for (const cleanup::Entry& entry : plan) std::cout << entry.description() << "\n\n";
    std::cout << std::flush;
    if (!args.yes) {
        std::cout << "仅预览；未执行。执行需要显式 --yes 和预览后二次确认。\n";
        return 0;
    }
    if (!confirm_input("二次确认：输入 DELETE 执行以上清单（Esc / 其它输入取消）", "DELETE")) {
        std::cout << "已取消；未执行\n";
        return 0;
    }
    std::vector<std::string> volumes;
    for (const cleanup::Entry& entry : plan) {
        if (entry.kind == cleanup::Kind::Volume) volumes.push_back(entry.id);
    }
    if (!volumes.empty()) {
        std::string phrase = "DELETE";
        for (const std::string& volume : volumes) phrase += " " + volume;
        if (!confirm_input("卷数据不可恢复！另行输入完整文本：" + phrase, phrase)) {
            std::cout << "已取消；未执行\n";
            return 0;
        }
    }
    const cleanup::Report report = cleanup::execute(engine, plan);
    std::cout << report.body() << "\n";
    if (report.failed > 0) throw std::runtime_error("部分项目清理失败；见上方准确清单");
    return 0;
}
std::optional<std::string> host_from_args(const std::vector<std::string>& args) {
    CliArgs parsed;
    std::string error;
    if (!parse_cli_args(args, parsed, error)) return std::nullopt;
    return parsed.host;
}
int run_cli(const std::vector<std::string>& args) {
    for (const std::string& arg : args) {
        if (arg == "--help" || arg == "-h") {
            std::cout << kHelp;
            return 0;
        }
    }
    for (const std::string& arg : args) {
        if (arg == "--version") {
            std::cout << "mayon-tools docker 0.2.0\n";
            return 0;
        }
    }
    CliArgs parsed;
    std::string error;
    if (!parse_cli_args(args, parsed, error)) {
        std::cerr << "Error: " << error << "\n";
        return 1;
    }
    if (!parsed.command) return -1;
    try {
        if (*parsed.command == "df") return run_df(parsed.host);
        return run_clean(parsed);
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << "\n";
        return 1;
    }
}
}  // namespace
}  // namespace dock

std::unique_ptr<tui::Page> make_docker_page() { return std::make_unique<dock::App>(std::nullopt); }
std::unique_ptr<tui::Page> make_docker_page(const std::vector<std::string>& args) {
    return std::make_unique<dock::App>(dock::host_from_args(args));
}
int docker_cli(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return dock::run_cli(args);
}
