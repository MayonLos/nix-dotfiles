#include <signal.h>

#include <cstring>
#include <iostream>
#include <memory>

#include "app.hpp"
#include "media/process.hpp"
#include "media/stream.hpp"
#include "store.hpp"

using namespace bili;
static int probe_play(const std::string& bvid) {
    // Anonymous, read-only check: details, stream choice, and a short null-output mpv pull.
    Api api("");
    api.initialize();
    const Video video = parse_video(api.get("/x/web-interface/view", {{"bvid", bvid}}));
    const Stream stream = resolve_stream(api, bvid, video.cid, 16);
    std::vector<std::string> command{"mpv", "--no-config", "--no-terminal", "--vo=null", "--ao=null", "--frames=24", "--network-timeout=15",
                                     "--referrer=" + video.link(), std::string("--user-agent=") + kUserAgent};
    if (!stream.audio.empty()) command.push_back("--audio-file=" + stream.audio);
    command.emplace_back("--");
    command.push_back(stream.video);
    const pid_t pid = spawn_process(command);
    bool success = false;
    for (int i = 0; i < 450 && !try_reap(pid, &success); ++i) {
        ::usleep(100000);
        if (i == 449) {
            stop_process(pid);
            std::cerr << "mpv 超时\n";
            return 1;
        }
    }
    std::cout << (success ? "OK" : "FAILED") << " · Q" << stream.quality << " · 未向 CDN 发送 cookie\n";
    return success ? 0 : 1;
}
int main(int argc, char** argv) {
    signal(SIGPIPE, SIG_IGN);
    bool demo = false;
    bool demo_playing = false;
    try {
        for (int i = 1; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg == "--help" || arg == "-h") {
                std::cout << "bilitui-next — 搜索优先的 B 站终端播放器\n\n"
                             "无参数      交互界面\n"
                             "--demo      离线样例，不读 cookie、不联网\n"
                             "--demo-playing  离线样例并显示播放条\n"
                             "--probe-play BV  匿名验证取流与 mpv 拉流\n\n"
                             "配置：~/.config/bilitui/config.toml\n"
                             "状态：~/.local/share/bilitui/（cookie 0600）\n";
                return 0;
            }
            if (arg == "--demo") {
                demo = true;
            } else if (arg == "--demo-playing") {
                demo = true;
                demo_playing = true;
            } else if (arg == "--probe-play" && i + 1 < argc) {
                return probe_play(argv[++i]);
            } else {
                std::cerr << "未知参数，使用 --help 查看用法\n";
                return 2;
            }
        }
        auto api = std::make_shared<Api>(demo ? std::string{} : read_cookie());
        App app(api, demo ? parse_config("") : load_config(), demo, demo_playing);
        return app.run();
    } catch (const std::exception& error) {
        std::cerr << "bilitui: " << error.what() << "\n";
        return 1;
    }
}
