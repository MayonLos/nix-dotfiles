#include "app.hpp"

#include <fcntl.h>
#include <poll.h>
#include <qrencode.h>
#include <signal.h>
#include <sys/eventfd.h>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <stdexcept>

#include "ui/search.hpp"
#include "ui/text.hpp"
#include "media/process.hpp"
#include "ui/terminal.hpp"

using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;
namespace bili {
const std::array<const char*, 3> kOrderNames{"最相关", "最新发布", "最多播放"};
const std::array<const char*, 5> kDurationNames{"不限时长", "10 分钟内", "10–30 分钟", "30–60 分钟", "60 分钟以上"};
static const char* const kHelp =
    "搜索框：输入后 Enter 搜索 · ↑↓ 选历史 · Tab 取建议 · Esc 回到列表\n"
    "\n"
    "Enter  播放（有进度就续播）· 打开 UP 或收藏夹\n"
    "→ / ←  进出分 P 与合集列表\n"
    "j k ↑↓  移动，滚到底自动加载更多\n"
    "1 2 3 / Tab  搜索、学习、关注\n"
    "s  回到搜索框        /  本地过滤（支持拼音）\n"
    "o  切换排序          t  切换时长\n"
    "a  加入播放队列      w  加入稍后再看\n"
    "u  这个 UP 的投稿    R  刷新\n"
    "Space  更多：清晰度、字幕、收藏、复制链接、浏览器、下载、登录\n"
    "Esc  清除过滤 / 返回上一层    q  退出\n"
    "\n"
    "连续播放：放完自动接队列，没有队列就接下一分 P 或合集下一集。";

static std::vector<Video> demo_videos() {
    struct Row { const char* title; const char* up; uint64_t views; const char* duration; int64_t progress; };
    static const Row rows[] = {{"信号与系统 全 124 讲", "某大学公开课", 860000, "52:31:13", 0},
                               {"傅里叶变换的直观理解", "数学漫游", 216800, "18:20", 660},
                               {"拉普拉斯变换精讲", "电路自习室", 126700, "42:10", -1},
                               {"从零理解 Rust 的所有权与借用", "代码漫游", 96500, "24:36", 0},
                               {"用 Nix 搭建可以复现的开发环境", "Linux 日常", 184300, "18:27", 0},
                               {"线性代数的本质：一个很长很长的标题，用来检查列表在窄终端里能否正确截断而不错列", "数学漫游", 1520000, "3:12:40", 2400},
                               {"高等数学 同济七版 完整课程", "考研数学", 3400000, "68:05:11", 0},
                               {"操作系统导论 OSTEP 精读", "计算机自习室", 88200, "1:45:02", 0},
                               {"计算机网络：从 TCP 到 QUIC", "计算机自习室", 141000, "58:47", 900},
                               {"C++ 现代内存模型入门", "代码漫游", 53100, "37:15", 0},
                               {"数字电路 FPGA 实战", "电路自习室", 72400, "2:08:33", 0},
                               {"概率论与数理统计 重点串讲", "考研数学", 410000, "6:30:00", 0},
                               {"嵌入式 STM32 从点灯到 RTOS", "电路自习室", 267000, "11:20:45", 0},
                               {"编译原理 龙书导读", "计算机自习室", 39800, "49:12", 0},
                               {"英语语法新思维 第一讲", "外语角", 95000, "27:03", 0}};
    std::vector<Video> out;
    uint64_t index = 0;
    for (const Row& row : rows) {
        Video video;
        video.bvid = "BV1demo" + std::to_string(index);
        video.aid = 1000 + index;
        video.cid = 2000 + index;
        video.title = row.title;
        video.up = row.up;
        video.mid = 42;
        video.views = row.views;
        video.duration = row.duration;
        video.pubdate = 1700000000;
        video.progress = row.progress;
        video.description = "这里是离线展示数据，不访问网络，也不读取登录状态。";
        if (index == 0) {
            video.count = 6;
            for (uint64_t page = 1; page <= 6; ++page) video.parts.push_back({2000 + page, page, "第 " + std::to_string(page) + " 讲", 2700});
        }
        out.push_back(std::move(video));
        ++index;
    }
    return out;
}
static std::vector<Video> demo_learning() {
    const auto header = [](const char* title) {
        Video row;
        row.kind = Kind::Header;
        row.title = title;
        return row;
    };
    const std::vector<Video> all = demo_videos();
    std::vector<Video> out{header("继续观看"), all[1], all[5], all[8], header("稍后再看"), all[3], all[7]};
    Video folder;
    folder.kind = Kind::Folder;
    folder.title = "数学";
    folder.count = 32;
    folder.mid = 7;
    out.push_back(header("收藏夹"));
    out.push_back(folder);
    return out;
}
Page fetch_page(Api& api, const Source& source, const CancelFlag& cancel) {
    Page page;
    const std::string pn = std::to_string(source.page);
    switch (source.type) {
        case Source::Type::None:
            return page;
        case Source::Type::Search: {
            static constexpr std::array<const char*, 3> orders{"", "pubdate", "click"};
            page.heading = "搜索 · " + source.query;
            Params params{{"search_type", "video"}, {"keyword", source.query}, {"page", pn}, {"page_size", "20"}};
            if (source.order != 0) params.emplace_back("order", orders[static_cast<size_t>(source.order)]);
            if (source.duration != 0) params.emplace_back("duration", std::to_string(source.duration));
            const Json data = api.signed_get("/x/web-interface/wbi/search/type", params, cancel);
            // A risk-control challenge arrives as code 0 without results; never show it as "no content".
            if (data.is_object() && data.contains("v_voucher")) throw std::runtime_error("B 站要求人机验证，请稍后重试或登录后再搜索");
            if (data.is_object() && data.contains("result")) page.items = parse_videos(data["result"]);
            if (source.page == 1 && source.order == 0 && source.duration == 0) {
                // Best effort: only accounts named after the query are worth pinning above videos.
                try {
                    const Json found = api.signed_get("/x/web-interface/wbi/search/type",
                                                      {{"search_type", "bili_user"}, {"keyword", source.query}, {"page", "1"}, {"page_size", "5"}}, cancel);
                    std::vector<Video> users;
                    if (found.is_object() && found.contains("result") && found["result"].is_array()) {
                        for (const Json& item : found["result"]) {
                            Video user;
                            user.kind = Kind::User;
                            user.mid = number(item.value("mid", Json()));
                            user.title = clean(str(item, "uname"));
                            user.up = "UP 主";
                            const auto hit = match(source.query, user.title);
                            if (user.mid != 0 && hit && hit->score >= 300 && users.size() < 2) users.push_back(std::move(user));
                        }
                    }
                    page.items.insert(page.items.begin(), users.begin(), users.end());
                } catch (const std::exception&) {
                }
            }
            page.more = !page.items.empty() && source.page < 50;
            return page;
        }
        case Source::Type::Up: {
            const Json data = api.signed_get("/x/space/wbi/arc/search",
                                             {{"mid", std::to_string(source.id)}, {"pn", pn}, {"ps", "20"}, {"order", "pubdate"}}, cancel);
            if (data.is_object() && data.contains("list") && data["list"].is_object() && data["list"].contains("vlist")) {
                page.items = parse_videos(data["list"]["vlist"]);
            }
            page.heading = source.query.empty() ? "UP 投稿" : source.query + " 的投稿";
            page.more = page.items.size() == 20;
            return page;
        }
        case Source::Type::Folder: {
            const Json data = api.get("/x/v3/fav/resource/list",
                                      {{"media_id", std::to_string(source.id)}, {"pn", pn}, {"ps", "20"}, {"platform", "web"}}, cancel);
            if (data.is_object() && data.contains("medias")) page.items = parse_videos(data["medias"]);
            page.heading = source.query.empty() ? "收藏夹" : source.query;
            page.more = data.is_object() && data.value("has_more", false);
            return page;
        }
        case Source::Type::Feed: {
            Params params{{"type", "video"}};
            if (!source.cursor.empty()) params.emplace_back("offset", source.cursor);
            const Json data = api.get("/x/polymer/web-dynamic/v1/feed/all", params, cancel);
            page.heading = "关注动态";
            if (data.is_object() && data.contains("items") && data["items"].is_array()) {
                for (const Json& item : data["items"]) {
                    const Json archive = item.value("modules", Json::object()).value("module_dynamic", Json::object()).value("major", Json::object()).value("archive", Json());
                    if (!archive.is_object()) continue;
                    Video video = parse_video(archive);
                    const Json author = item.value("modules", Json::object()).value("module_author", Json::object());
                    video.up = clean(str(author, "name"));
                    video.mid = number(author.value("mid", Json()));
                    if (!video.bvid.empty()) page.items.push_back(std::move(video));
                }
            }
            page.cursor = data.is_object() ? str(data, "offset") : "";
            page.more = !page.cursor.empty() && page.cursor != source.cursor && data.value("has_more", false);
            return page;
        }
        case Source::Type::Learning: {
            page.heading = "学习";
            const auto header = [](std::string title) {
                Video row;
                row.kind = Kind::Header;
                row.title = std::move(title);
                return row;
            };
            const Json history = api.get("/x/web-interface/history/cursor", {{"ps", "20"}, {"type", "archive"}}, cancel);
            std::vector<Video> recent;
            if (history.is_object() && history.contains("list") && history["list"].is_array()) {
                for (const Json& item : history["list"]) {
                    const Json info = item.value("history", Json::object());
                    if (str(info, "business") != "archive") continue;
                    Video video = parse_video(item);
                    video.bvid = clean(str(info, "bvid"));
                    video.aid = number(info.value("oid", Json()));
                    video.cid = number(info.value("cid", Json()));
                    video.count = number(item.value("videos", Json()));
                    if (!video.bvid.empty() && video.progress != -1 && recent.size() < 8) recent.push_back(std::move(video));
                }
            }
            const Json later = api.get("/x/v2/history/toview", {}, cancel);
            std::vector<Video> queued;
            if (later.is_object() && later.contains("list")) queued = parse_videos(later["list"]);
            std::vector<Video> folders;
            if (const auto uid = api.user_id()) {
                const Json data = api.get("/x/v3/fav/folder/created/list-all", {{"up_mid", *uid}}, cancel);
                if (data.is_object() && data.contains("list") && data["list"].is_array()) {
                    for (const Json& item : data["list"]) {
                        Video folder;
                        folder.kind = Kind::Folder;
                        folder.aid = number(item.value("id", Json()));
                        folder.title = clean(str(item, "title"));
                        folder.count = number(item.value("media_count", Json()));
                        folder.up = "收藏夹";
                        folders.push_back(std::move(folder));
                    }
                }
            }
            page.items.push_back(header("稍后再看 · " + std::to_string(queued.size())));
            page.items.insert(page.items.end(), queued.begin(), queued.end());
            page.items.push_back(header("继续学习"));
            page.items.insert(page.items.end(), recent.begin(), recent.end());
            page.items.push_back(header("收藏夹"));
            page.items.insert(page.items.end(), folders.begin(), folders.end());
            return page;
        }
    }
    return page;
}
std::pair<size_t, uint64_t> resume_point(const Details& details) {
    const Video& video = details.video;
    size_t part = 0;
    uint64_t start = details.info.last_seconds;
    if (details.info.last_cid != 0) {
        for (size_t i = 0; i < video.parts.size(); ++i) {
            if (video.parts[i].cid == details.info.last_cid) part = i;
        }
    }
    if (part < video.parts.size() && video.parts[part].seconds != 0 && start + 15 >= video.parts[part].seconds) {
        // That part was finished: move on, or start over when it was the last one.
        start = 0;
        if (part + 1 < video.parts.size()) ++part;
    }
    return {part, start};
}
App::App(std::shared_ptr<Api> api, Config config, bool demo, bool demo_playing) : api_(std::move(api)), config_(std::move(config)), demo_(demo) {
    for (const TabId id : {TabId::Search, TabId::Learn, TabId::Follow}) {
        ListState state;
        state.id = next_list_id_++;
        if (id == TabId::Search) state.heading = "搜索";
        if (id == TabId::Learn) {
            state.heading = "学习";
            state.source.type = Source::Type::Learning;
        }
        if (id == TabId::Follow) {
            state.heading = "关注动态";
            state.source.type = Source::Type::Feed;
        }
        tabs_[static_cast<size_t>(id)].push_back(std::move(state));
    }
    if (demo_) {
        tabs_[1].back().items = demo_learning();
        tabs_[1].back().loaded = true;
        rebuild_visible(tabs_[1].back(), "");
        tabs_[2].back().items = demo_videos();
        tabs_[2].back().loaded = true;
        rebuild_visible(tabs_[2].back(), "");
        choices_ = {"信号与系统", "线性代数", "傅里叶变换", "STM32 入门"};
        if (demo_playing) player_status_ = PlayerStatus{.running = true, .title = "傅里叶变换的直观理解", .queued = 2, .position = 660, .duration = 1100};
    } else {
        pool_ = std::make_unique<Pool>(3);
        player_ = std::make_unique<Player>(api_, config_, [this](PlayerStatus status) {
            mailbox_.post([status = std::move(status)](App& app) {
                app.player_status_ = status;
                if (!status.finished_bvid.empty()) app.details_.erase(status.finished_bvid);
                if (!status.notice.empty()) app.set_notice(status.notice, status.error);
            });
        });
        downloader_ = std::make_unique<Downloader>(api_, [this](DownloadUpdate update) {
            mailbox_.post([update = std::move(update)](App& app) {
                if (update.id < app.downloads_.size()) {
                    app.downloads_[update.id].state = update.state;
                    if (update.bytes > 0) app.downloads_[update.id].bytes = update.bytes;
                }
            });
        });
        choices_ = search_history();
    }
}
App::~App() {
    for (const CancelFlag& flag : {list_task_, details_task_, cover_task_, login_task_, misc_task_}) {
        if (flag) flag->store(true);
    }
    pool_.reset();
    player_.reset();
    downloader_.reset();
}
ListState& App::list() { return tabs_[static_cast<size_t>(tab_)].back(); }
const ListState& App::list() const { return tabs_[static_cast<size_t>(tab_)].back(); }
void App::set_notice(std::string text, bool error) {
    notice_ = std::move(text);
    notice_error_ = error;
    notice_until_ = Clock::now() + (error ? 8s : 5s);
}
void App::set_size(int width, int height) {
    width_ = width;
    height_ = height;
}
void App::run_task(CancelFlag& slot, std::function<std::function<void(App&)>(const CancelFlag&)> work, bool show_error) {
    if (slot) slot->store(true);
    slot = make_cancel();
    if (!pool_) return;
    pool_->run([this, cancel = slot, work = std::move(work), show_error] {
        if (cancel->load()) return;
        try {
            auto done = work(cancel);
            mailbox_.post([cancel, done = std::move(done)](App& app) {
                if (!cancel->load()) done(app);
            });
        } catch (const std::exception& error) {
            if (cancel->load()) return;
            mailbox_.post([cancel, message = std::string(error.what()), show_error](App& app) {
                if (cancel->load()) return;
                for (auto& tab : app.tabs_) {
                    for (auto& state : tab) state.loading = false;
                }
                app.login_polling_ = false;
                if (show_error) app.list().error = message;
                if (show_error) app.set_notice(message, true);
            });
        }
    });
}
void App::fire_and_report(std::function<std::string()> work) {
    if (!pool_) return;
    pool_->run([this, work = std::move(work)] {
        try {
            mailbox_.post([message = work()](App& app) { app.set_notice(message); });
        } catch (const std::exception& error) {
            mailbox_.post([message = std::string(error.what())](App& app) { app.set_notice(message, true); });
        }
    });
}
void App::start() {
    if (demo_) return;
    fire_and_report([api = api_] {
        api->initialize();
        return std::string{};
    });
}
void App::drain() {
    for (auto& job : mailbox_.take()) job(*this);
}
void App::rebuild_visible(ListState& state, const std::string& keep_key) {
    state.visible.clear();
    const std::string query = state.filter.str();
    std::vector<std::pair<uint32_t, size_t>> scored;
    for (size_t i = 0; i < state.items.size(); ++i) {
        const Video& item = state.items[i];
        if (query.empty()) {
            state.visible.push_back(i);
        } else if (item.kind != Kind::Header) {
            if (const auto hit = match(query, item.title + " " + item.up + " " + item.bvid)) scored.emplace_back(hit->score, i);
        }
    }
    std::stable_sort(scored.begin(), scored.end(), [](const auto& a, const auto& b) { return a.first > b.first; });
    for (const auto& [score, index] : scored) state.visible.push_back(index);
    state.selected = 0;
    bool found = false;
    if (!keep_key.empty()) {
        for (size_t i = 0; i < state.visible.size(); ++i) {
            if (state.items[state.visible[i]].key() == keep_key) {
                state.selected = i;
                found = true;
            }
        }
    }
    if (!found) {
        // Start on the first video: Enter should play, not open a pinned UP account.
        const auto selectable = [&](bool video_only) {
            for (size_t i = 0; i < state.visible.size(); ++i) {
                const Kind kind = state.items[state.visible[i]].kind;
                if (video_only ? kind == Kind::Video : kind != Kind::Header) return std::optional<size_t>(i);
            }
            return std::optional<size_t>{};
        };
        state.selected = selectable(true).value_or(selectable(false).value_or(0));
    }
}
const Video* App::selected_video() const {
    const ListState& state = list();
    if (state.selected >= state.visible.size()) return nullptr;
    const Video& video = state.items[state.visible[state.selected]];
    return video.kind == Kind::Header ? nullptr : &video;
}
const Details* App::selected_details() const {
    const Video* video = selected_video();
    if (!video || video->kind != Kind::Video) return nullptr;
    const auto found = details_.find(video->bvid);
    return found == details_.end() ? nullptr : &found->second;
}
void App::move(int delta) {
    ListState& state = list();
    if (state.visible.empty()) return;
    int at = static_cast<int>(state.selected);
    const int last = static_cast<int>(state.visible.size()) - 1;
    const int direction = delta > 0 ? 1 : -1;
    at = std::clamp(at + delta, 0, last);
    while (state.items[state.visible[static_cast<size_t>(at)]].kind == Kind::Header) {
        at += direction;
        if (at < 0 || at > last) {
            // Nothing selectable that way: stay where we were.
            at = static_cast<int>(state.selected);
            break;
        }
    }
    state.selected = static_cast<size_t>(at);
    selection_changed();
    if (state.selected + 5 >= state.visible.size()) load_more();
}
void App::selection_changed() {
    series_selected_ = 0;
    series_offset_ = 0;
    const auto now = Clock::now();
    preview_due_ = now + 300ms;
    cover_due_ = now + 300ms;
}
void App::load_more() {
    ListState& state = list();
    if (!state.source.more || state.loading || !state.filter.empty() || state.items.size() >= 1000) return;
    ++state.source.page;
    refresh(state, true);
}
void App::refresh(ListState& state, bool append) {
    if (demo_) {
        set_notice("离线样例不访问网络");
        return;
    }
    if (state.source.type == Source::Type::None) return;
    const bool needs_login = state.source.type == Source::Type::Learning || state.source.type == Source::Type::Feed || state.source.type == Source::Type::Folder;
    if (needs_login && !api_->logged_in()) {
        state.loaded = true;
        state.error = "这一页需要登录；Space 打开菜单扫码登录";
        return;
    }
    if (!append) {
        state.source.page = 1;
        state.source.cursor.clear();
    }
    state.loading = true;
    state.error.clear();
    run_task(list_task_, [api = api_, source = state.source, id = state.id, append](const CancelFlag& cancel) {
        Page page = fetch_page(*api, source, cancel);
        return std::function<void(App&)>([id, append, page = std::move(page)](App& app) mutable { app.apply_page(id, std::move(page), append); });
    });
}
void App::apply_page(uint64_t list_id, Page page, bool append) {
    for (auto& tab : tabs_) {
        for (auto& state : tab) {
            if (state.id != list_id) continue;
            state.loading = false;
            state.loaded = true;
            state.error.clear();
            if (!page.heading.empty()) state.heading = page.heading;
            state.source.more = page.more;
            state.source.cursor = page.cursor;
            std::string keep;
            if (state.selected < state.visible.size()) keep = state.items[state.visible[state.selected]].key();
            if (append) {
                // Search pages can repeat results across page boundaries.
                for (auto& item : page.items) {
                    const bool duplicate = std::any_of(state.items.begin(), state.items.end(), [&](const Video& other) { return other.key() == item.key(); });
                    if (!duplicate) state.items.push_back(std::move(item));
                }
            } else {
                state.items = std::move(page.items);
                state.offset = 0;
            }
            rebuild_visible(state, keep);
            if (&state == &list()) selection_changed();
            return;
        }
    }
}
void App::select_tab(TabId tab) {
    tab_ = tab;
    if (focus_ == Focus::Parts || focus_ == Focus::Filter) focus_ = Focus::List;
    if (tab != TabId::Search && focus_ == Focus::Input) focus_ = Focus::List;
    cover_requested_.clear();
    ListState& state = list();
    if (!state.loaded && !state.loading) refresh(state, false);
    selection_changed();
}
void App::update_choices() {
    choice_.reset();
    const std::string typed = search_.str();
    std::vector<std::string> all = demo_ ? std::vector<std::string>{"信号与系统", "线性代数"} : search_history();
    choices_.clear();
    for (auto& item : all) {
        if (item != typed && (typed.empty() || match(typed, item))) choices_.push_back(std::move(item));
    }
    if (choices_.size() > 10) choices_.resize(10);
    choices_open_ = !choices_.empty();
}
void App::submit_search() {
    const std::string query = trim(search_.str());
    choices_open_ = false;
    choice_.reset();
    if (query.empty()) return;
    search_.set(query);
    focus_ = Focus::List;
    if (tab_ != TabId::Search) tab_ = TabId::Search;
    auto& stack = tabs_[0];
    stack.resize(1);
    ListState& state = stack.back();
    state.source.type = Source::Type::Search;
    state.source.query = query;
    state.source.order = order_;
    state.source.duration = duration_;
    state.heading = "搜索 · " + query;
    state.filter.clear();
    state.selected = 0;
    state.offset = 0;
    state.items.clear();
    state.visible.clear();
    if (demo_) {
        state.items = demo_videos();
        state.loaded = true;
        rebuild_visible(state, "");
        return;
    }
    try {
        add_search(query);
    } catch (const std::exception&) {
        // History is a convenience; searching must still work.
    }
    refresh(state, false);
}
void App::request_details(const std::string& bvid) {
    if (demo_) {
        for (const auto& video : demo_videos()) {
            if (video.bvid == bvid) put_details({video, {}});
        }
        return;
    }
    if (bvid.empty()) return;
    run_task(details_task_, [api = api_, bvid](const CancelFlag& cancel) {
        Details details;
        details.video = parse_video(api->get("/x/web-interface/view", {{"bvid", bvid}}, cancel));
        if (api->logged_in() && details.video.cid != 0) details.info = fetch_player_info(*api, bvid, details.video.cid, cancel);
        return std::function<void(App&)>([details = std::move(details)](App& app) { app.put_details(details); });
    }, !pending_play_.empty());
}
void App::put_details(Details details) {
    if (details_.size() >= 64) details_.clear();
    const std::string bvid = details.video.bvid;
    details_[bvid] = std::move(details);
    if (pending_play_ == bvid) {
        const std::string target = std::exchange(pending_play_, {});
        const size_t part = std::exchange(pending_part_, SIZE_MAX);
        const bool queue = std::exchange(pending_queue_, false);
        const Details& loaded = details_[target];
        PlayItem item;
        item.video = loaded.video;
        const auto [resume, start] = resume_point(loaded);
        item.part = part == SIZE_MAX ? resume : part;
        item.start = part == SIZE_MAX || part == resume ? start : 0;
        if (demo_) {
            demo_played_.push_back(std::move(item));
        } else if (queue) {
            player_->enqueue(std::move(item));
            set_notice("已加入播放队列");
        } else {
            player_->play_now(std::move(item));
            set_notice("正在解析播放地址…");
        }
    }
}
void App::play_selected() {
    const Video* video = selected_video();
    if (!video) return;
    if (video->kind != Kind::Video) {
        open_row(*video);
        return;
    }
    pending_play_ = video->bvid;
    pending_part_ = SIZE_MAX;
    pending_queue_ = false;
    const auto found = details_.find(video->bvid);
    if (found != details_.end()) {
        Details copy = found->second;
        put_details(std::move(copy));
    } else {
        set_notice("正在加载…");
        request_details(video->bvid);
    }
}
void App::play_part(size_t index) {
    const Details* details = selected_details();
    if (!details) return;
    const Video& video = details->video;
    if (video.parts.size() > 1) {
        pending_play_ = video.bvid;
        pending_part_ = index;
        pending_queue_ = false;
        Details copy = *details;
        put_details(std::move(copy));
    } else if (index < video.collection.size()) {
        PlayItem item;
        item.video = video.collection[index];
        item.video.collection = video.collection;
        if (demo_) {
            demo_played_.push_back(std::move(item));
        } else {
            player_->play_now(std::move(item));
            set_notice("正在解析播放地址…");
        }
    }
}
void App::queue_selected() {
    const Video* video = selected_video();
    if (!video || video->kind != Kind::Video) return;
    pending_play_ = video->bvid;
    pending_part_ = 0;
    pending_queue_ = true;
    const auto found = details_.find(video->bvid);
    if (found != details_.end()) {
        Details copy = found->second;
        put_details(std::move(copy));
    } else {
        request_details(video->bvid);
    }
}
void App::add_to_view_later() {
    const Video* video = selected_video();
    if (!video || video->kind != Kind::Video) return;
    if (demo_) {
        set_notice("离线样例不会执行操作");
        return;
    }
    if (!api_->logged_in()) {
        set_notice("需要登录；Space 打开菜单扫码登录");
        return;
    }
    fire_and_report([api = api_, bvid = video->bvid, aid = video->aid] {
        Params params{{"bvid", bvid}};
        if (aid != 0) params.emplace_back("aid", std::to_string(aid));
        api->post("/x/v2/history/toview/add", params);
        return std::string("已加入稍后再看");
    });
    tabs_[1].front().loaded = false;
}
void App::open_row(const Video& row) {
    ListState next;
    next.id = next_list_id_++;
    if (row.kind == Kind::User) {
        next.source.type = Source::Type::Up;
        next.source.id = row.mid;
        next.source.query = row.title;
        next.heading = row.title + " 的投稿";
    } else if (row.kind == Kind::Folder) {
        next.source.type = Source::Type::Folder;
        next.source.id = row.aid;
        next.source.query = row.title;
        next.heading = row.title;
    } else {
        return;
    }
    auto& stack = tabs_[static_cast<size_t>(tab_)];
    if (stack.size() >= 8) return;
    stack.push_back(std::move(next));
    focus_ = Focus::List;
    refresh(list(), false);
}
void App::open_up() {
    const Video* video = selected_video();
    if (!video || video->mid == 0) return;
    Video row;
    row.kind = Kind::User;
    row.mid = video->mid;
    row.title = video->up;
    open_row(row);
}
bool App::back() {
    ListState& state = list();
    if (!state.filter.empty()) {
        const std::string keep = selected_video() ? selected_video()->key() : "";
        state.filter.clear();
        rebuild_visible(state, keep);
        return true;
    }
    auto& stack = tabs_[static_cast<size_t>(tab_)];
    if (stack.size() > 1) {
        stack.pop_back();
        selection_changed();
        return true;
    }
    return false;
}
void App::copy_link() {
    const Video* video = selected_video();
    if (!video || video->kind != Kind::Video) return;
    if (terminal_) terminal_->copy(video->link());
    set_notice("已复制链接");
}
void App::open_browser() {
    const Video* video = selected_video();
    if (!video || video->kind != Kind::Video || demo_) return;
    try {
        const pid_t pid = spawn_process({"xdg-open", video->link()});
        pool_->run([pid] {
            while (!try_reap(pid, nullptr)) ::usleep(200000);
        });
        set_notice("已在浏览器打开");
    } catch (const std::exception& error) {
        set_notice(error.what(), true);
    }
}
void App::enqueue_download(char mode) {
    const Details* details = selected_details();
    const Video* selected = selected_video();
    if (!selected || selected->kind != Kind::Video || demo_) return;
    if (!details) {
        set_notice("详情还在加载，稍后再试");
        return;
    }
    const Video& video = details->video;
    std::vector<std::pair<Video, uint64_t>> entries;
    if (mode == 'A' && !video.parts.empty()) {
        for (const Part& part : video.parts) entries.emplace_back(video, part.cid);
    } else if (mode == 'G') {
        for (const Video& episode : video.collection) entries.emplace_back(episode, episode.cid);
    } else {
        const size_t part = video.parts.size() > 1 && series_selected_ < video.parts.size() ? series_selected_ : 0;
        entries.emplace_back(video, part < video.parts.size() ? video.parts[part].cid : video.cid);
    }
    if (entries.empty() || entries.size() > 500) {
        set_notice("没有可下载内容，或超过 500 集上限", true);
        return;
    }
    for (auto& [target, cid] : entries) {
        DownloadJob job;
        job.id = downloads_.size();
        job.cid = cid;
        job.quality = config_.quality;
        job.audio_only = mode == 'a';
        job.directory = config_.download_dir;
        downloads_.push_back({target.title + (job.audio_only ? " · 音频" : ""), "等待中", 0});
        job.video = std::move(target);
        downloader_->add(std::move(job));
    }
    set_notice("已加入下载队列");
}
void App::change_quality() {
    const Video* video = selected_video();
    const Details* details = selected_details();
    if (demo_ || !video || !details) {
        set_notice("先选中视频，等详情加载完");
        return;
    }
    run_task(misc_task_, [api = api_, bvid = video->bvid, cid = details->video.cid, current = config_.quality](const CancelFlag& cancel) {
        const Stream stream = resolve_stream(*api, bvid, cid, 0, cancel);
        return std::function<void(App&)>([choices = stream.choices, current](App& app) {
            Modal modal;
            modal.kind = Modal::Kind::Menu;
            modal.title = "清晰度（当前 " + (current == 0 ? std::string("最高可用") : "Q" + std::to_string(current)) + "）";
            auto add = [&](std::string label, uint64_t quality) {
                modal.items.push_back({std::move(label), [quality](App& target) {
                                           target.config_.quality = quality;
                                           if (target.player_) target.player_->set_config(target.config_);
                                           target.set_notice("下一次播放或下载生效");
                                       }});
            };
            add("最高可用", 0);
            for (const auto& [quality, name] : choices) add(name, quality);
            app.modal_ = std::move(modal);
        });
    });
}
void App::add_to_favourite() {
    const Video* video = selected_video();
    if (demo_ || !video || video->kind != Kind::Video || !api_->logged_in()) {
        set_notice("需要登录，并选中一个视频");
        return;
    }
    run_task(misc_task_, [api = api_, aid = video->aid, title = video->title](const CancelFlag& cancel) {
        const auto uid = api->user_id();
        if (!uid) throw std::runtime_error("登录状态缺少用户 ID，请重新登录");
        const Json data = api->get("/x/v3/fav/folder/created/list-all", {{"up_mid", *uid}}, cancel);
        std::vector<std::pair<uint64_t, std::string>> folders;
        if (data.is_object() && data.contains("list") && data["list"].is_array()) {
            for (const Json& item : data["list"]) folders.emplace_back(number(item.value("id", Json())), clean(str(item, "title")));
        }
        return std::function<void(App&)>([folders, aid, title](App& app) {
            if (folders.empty()) {
                app.set_notice("还没有收藏夹，请先在官方客户端创建", true);
                return;
            }
            Modal modal;
            modal.kind = Modal::Kind::Menu;
            modal.title = "收藏到…";
            for (const auto& [id, name] : folders) {
                modal.items.push_back({name, [id = id, aid](App& target) {
                                           target.fire_and_report([api = target.api_, id, aid] {
                                               api->post("/x/v3/fav/resource/deal",
                                                         {{"rid", std::to_string(aid)}, {"type", "2"}, {"add_media_ids", std::to_string(id)}, {"del_media_ids", ""}});
                                               return std::string("已加入收藏夹");
                                           });
                                           target.tabs_[1].front().loaded = false;
                                       }});
            }
            app.modal_ = std::move(modal);
        });
    });
}
static std::string qr_art(const std::string& url) {
    QRcode* code = QRcode_encodeString(url.c_str(), 0, QR_ECLEVEL_L, QR_MODE_8, 1);
    if (!code) throw std::runtime_error("无法生成二维码");
    const int width = code->width;
    const int quiet = 4;
    const int size = width + quiet * 2;
    const auto dark = [&](int x, int y) {
        if (x < quiet || y < quiet || x >= width + quiet || y >= width + quiet) return false;
        return (code->data[(y - quiet) * width + (x - quiet)] & 1) != 0;
    };
    std::string out;
    for (int y = 0; y < size; y += 2) {
        for (int x = 0; x < size; ++x) {
            const bool top = dark(x, y);
            const bool bottom = y + 1 < size && dark(x, y + 1);
            out += top && bottom ? " " : top ? "▄" : bottom ? "▀" : "█";
        }
        out += '\n';
    }
    QRcode_free(code);
    return out;
}
void App::start_login() {
    if (demo_) {
        set_notice("离线样例禁用登录");
        return;
    }
    if (player_status_.running) {
        set_notice("请先关闭播放器，再切换账号");
        return;
    }
    Modal modal;
    modal.kind = Modal::Kind::Qr;
    modal.title = "手机扫码登录";
    modal.text = "正在获取二维码…";
    modal.qr_last = Clock::now();
    modal_ = std::move(modal);
    run_task(login_task_, [api = api_](const CancelFlag& cancel) {
        const auto [url, key] = api->qr_generate(cancel);
        return std::function<void(App&)>([art = qr_art(url), key = key](App& app) {
            if (!app.modal_ || app.modal_->kind != Modal::Kind::Qr) return;
            app.modal_->qr_art = art;
            app.modal_->qr_key = key;
            app.modal_->text = "用哔哩哔哩 App 扫码，并在手机确认";
            app.modal_->qr_last = Clock::now();
        });
    });
}
void App::poll_login() {
    if (!focused_ || !modal_ || modal_->kind != Modal::Kind::Qr || modal_->qr_key.empty() || login_polling_) return;
    if (Clock::now() - modal_->qr_last < 3s) return;
    login_polling_ = true;
    run_task(login_task_, [api = api_, key = modal_->qr_key](const CancelFlag& cancel) {
        auto [state, cookie] = api->qr_poll(key, cancel);
        return std::function<void(App&)>([state = state, cookie = std::move(cookie)](App& app) {
            app.login_polling_ = false;
            if (!app.modal_ || app.modal_->kind != Modal::Kind::Qr) return;
            app.modal_->qr_last = Clock::now();
            if (state == 0 && cookie) {
                try {
                    save_cookie(*cookie);
                    app.api_ = std::make_shared<Api>(*cookie);
                    app.player_->set_api(app.api_);
                    app.downloader_->set_api(app.api_);
                    app.modal_.reset();
                    app.details_.clear();
                    for (auto index : {1, 2}) app.tabs_[static_cast<size_t>(index)].front().loaded = false;
                    app.set_notice("登录成功");
                } catch (const std::exception& error) {
                    app.modal_.reset();
                    app.set_notice(error.what(), true);
                }
            } else if (state == 86038) {
                app.modal_->qr_key.clear();
                app.modal_->text = "二维码已过期，Esc 后重新登录";
            } else if (state == 86090) {
                app.modal_->text = "已扫码，请在手机确认";
            } else if (state == 86101) {
                app.modal_->text = "等待扫码";
            } else {
                app.modal_->text = "二维码状态 " + std::to_string(state) + "，请稍后重试";
            }
        });
    });
}
void App::open_menu() {
    Modal modal;
    modal.kind = Modal::Kind::Menu;
    modal.title = "更多";
    const auto add = [&](std::string label, std::function<void(App&)> action) { modal.items.push_back({std::move(label), std::move(action)}); };
    if (selected_video() && selected_video()->kind == Kind::Video) {
        add("加入收藏夹…", [](App& app) { app.add_to_favourite(); });
        add("复制链接", [](App& app) { app.copy_link(); });
        add("在浏览器打开", [](App& app) { app.open_browser(); });
        add("清晰度…", [](App& app) { app.change_quality(); });
    }
    add(std::string("字幕：") + (config_.subtitles ? "开" : "关"), [](App& app) {
        app.config_.subtitles = !app.config_.subtitles;
        if (app.player_) app.player_->set_config(app.config_);
        app.set_notice(std::string("字幕 ") + (app.config_.subtitles ? "开启" : "关闭") + "，下一集生效");
    });
    add(std::string("进度上报：") + (config_.report_history ? "开" : "关"), [](App& app) {
        app.config_.report_history = !app.config_.report_history;
        if (app.player_) app.player_->set_config(app.config_);
        app.set_notice(std::string("进度上报 ") + (app.config_.report_history ? "开启" : "关闭"));
    });
    if (selected_video() && selected_video()->kind == Kind::Video) {
        add("下载当前分 P", [](App& app) { app.enqueue_download('v'); });
        add("下载音频", [](App& app) { app.enqueue_download('a'); });
        add("下载全部分 P", [](App& app) { app.enqueue_download('A'); });
        add("下载合集", [](App& app) { app.enqueue_download('G'); });
    }
    add("查看下载队列 · " + std::to_string(downloads_.size()), [](App& app) {
        Modal view;
        view.kind = Modal::Kind::Downloads;
        view.title = "下载队列";
        app.modal_ = std::move(view);
    });
    add(api_->logged_in() ? "切换账号（扫码）" : "扫码登录", [](App& app) { app.start_login(); });
    modal_ = std::move(modal);
}
bool App::handle(const InputEvent& event) {
    using Type = InputEvent::Type;
    if (event.type == Type::FocusIn) { set_focus_state(true); return false; }
    if (event.type == Type::FocusOut) { set_focus_state(false); return false; }
    if (event.type == Type::Paste) {
        if (modal_) return false;
        if (focus_ == Focus::Input) {
            search_.paste(event.paste);
            update_choices();
        } else if (focus_ == Focus::Filter) {
            const std::string keep = selected_video() ? selected_video()->key() : filter_keep_;
            list().filter.paste(event.paste);
            rebuild_visible(list(), keep);
        }
        return false;
    }
    if (event.type == Type::WheelUp || event.type == Type::WheelDown) {
        if (!modal_) move(event.type == Type::WheelUp ? -1 : 1);
        return false;
    }
    if (event.type == Type::MouseClick) {
        if (modal_) return false;
        if (event.y == 0) {
            int x = 1;
            for (const TabId id : {TabId::Search, TabId::Learn, TabId::Follow}) {
                if (event.x >= x && event.x < x + 8) {
                    select_tab(id);
                    return false;
                }
                x += 8;
            }
        }
        if (list_rect_.contains(event.x, event.y)) {
            ListState& state = list();
            // Entries are one or two rows tall; the last one starting at or above the click wins.
            for (auto entry = list_rows_.rbegin(); entry != list_rows_.rend(); ++entry) {
                if (entry->first > event.y) continue;
                if (state.items[state.visible[entry->second]].kind != Kind::Header) {
                    state.selected = entry->second;
                    if (focus_ != Focus::Filter) focus_ = Focus::List;
                    selection_changed();
                }
                break;
            }
        }
        return false;
    }
    const Key& key = event.key;
    if (modal_) {
        Modal& modal = *modal_;
        if (key.code == KeyCode::Escape || (modal.kind != Modal::Kind::Qr && key.is(U'q'))) {
            if (modal.kind == Modal::Kind::Qr) {
                if (login_task_) login_task_->store(true);
                login_polling_ = false;
            }
            modal_.reset();
            return false;
        }
        if (modal.kind == Modal::Kind::Menu) {
            if (key.code == KeyCode::Down || key.is(U'j')) modal.selected = std::min(modal.selected + 1, modal.items.size() - 1);
            if (key.code == KeyCode::Up || key.is(U'k')) modal.selected = modal.selected == 0 ? 0 : modal.selected - 1;
            if (key.code == KeyCode::Enter && modal.selected < modal.items.size()) {
                auto action = modal.items[modal.selected].action;
                modal_.reset();
                action(*this);
            }
        } else if (key.code == KeyCode::Enter || key.is(U'?')) {
            if (modal.kind != Modal::Kind::Qr) modal_.reset();
        }
        return false;
    }
    if (focus_ == Focus::Input) {
        if (key.code == KeyCode::Enter) {
            if (choices_open_ && choice_ && *choice_ < choices_.size()) search_.set(choices_[*choice_]);
            submit_search();
            return false;
        }
        if (key.code == KeyCode::Escape) {
            if (choices_open_ && !list().items.empty()) {
                choices_open_ = false;
            } else {
                choices_open_ = false;
                focus_ = Focus::List;
            }
            if (!list().items.empty()) focus_ = Focus::List;
            return false;
        }
        if (key.code == KeyCode::Down) {
            if (choices_open_ && !choices_.empty()) {
                choice_ = choice_ ? std::min(*choice_ + 1, choices_.size() - 1) : 0;
            } else if (!list().items.empty()) {
                focus_ = Focus::List;
            }
            return false;
        }
        if (key.code == KeyCode::Up) {
            if (choice_) choice_ = *choice_ == 0 ? std::optional<size_t>{} : std::optional<size_t>{*choice_ - 1};
            return false;
        }
        if (key.code == KeyCode::Tab) {
            if (demo_) return false;
            run_task(misc_task_, [api = api_, query = search_.str()](const CancelFlag& cancel) {
                auto values = api->suggest(query, cancel);
                return std::function<void(App&)>([values = std::move(values)](App& app) {
                    app.choices_ = values;
                    if (app.choices_.size() > 10) app.choices_.resize(10);
                    app.choice_.reset();
                    app.choices_open_ = !app.choices_.empty();
                });
            });
            return false;
        }
        if (search_.handle(key)) update_choices();
        return false;
    }
    if (focus_ == Focus::Filter) {
        ListState& state = list();
        // The selection can vanish while typing; Esc still returns to where the filter started.
        const std::string keep = selected_video() ? selected_video()->key() : filter_keep_;
        if (key.code == KeyCode::Escape) {
            state.filter = filter_before_;
            focus_ = Focus::List;
            rebuild_visible(state, keep);
        } else if (key.code == KeyCode::Enter) {
            focus_ = Focus::List;
        } else if (key.code == KeyCode::Down) {
            move(1);
        } else if (key.code == KeyCode::Up) {
            move(-1);
        } else if (state.filter.handle(key)) {
            rebuild_visible(state, keep);
            selection_changed();
        }
        return false;
    }
    if (key.ctrl || key.alt) return false;
    if (focus_ == Focus::Parts) {
        const Details* details = selected_details();
        const size_t count = !details ? 0 : details->video.parts.size() > 1 ? details->video.parts.size() : details->video.collection.size();
        if (key.code == KeyCode::Left || key.code == KeyCode::Escape || key.is(U'h')) focus_ = Focus::List;
        else if ((key.code == KeyCode::Down || key.is(U'j')) && series_selected_ + 1 < count) ++series_selected_;
        else if ((key.code == KeyCode::Up || key.is(U'k')) && series_selected_ > 0) --series_selected_;
        else if (key.code == KeyCode::PageDown && count > 0) series_selected_ = std::min(series_selected_ + 10, count - 1);
        else if (key.code == KeyCode::PageUp) series_selected_ = series_selected_ > 10 ? series_selected_ - 10 : 0;
        else if (key.code == KeyCode::Enter && count > 0) play_part(series_selected_);
        else if (key.is(U'q')) return true;
        return false;
    }
    if (key.is(U'q')) return true;
    if (key.is(U'?')) {
        Modal modal;
        modal.kind = Modal::Kind::Help;
        modal.title = "帮助";
        modal.text = kHelp;
        modal_ = std::move(modal);
    } else if (key.code == KeyCode::Down || key.is(U'j')) {
        move(1);
    } else if (key.code == KeyCode::Up || key.is(U'k')) {
        move(-1);
    } else if (key.code == KeyCode::PageDown) {
        move(std::max(static_cast<int>(list_rows_.size()) - 1, 1));
    } else if (key.code == KeyCode::PageUp) {
        move(-std::max(static_cast<int>(list_rows_.size()) - 1, 1));
    } else if (key.code == KeyCode::Home) {
        list().selected = 0;
        move(0);
    } else if (key.code == KeyCode::End) {
        list().selected = list().visible.empty() ? 0 : list().visible.size() - 1;
        move(0);
    } else if (key.code == KeyCode::Enter) {
        play_selected();
    } else if (key.code == KeyCode::Right || key.is(U'l')) {
        const Details* details = selected_details();
        if (details && (details->video.parts.size() > 1 || !details->video.collection.empty())) {
            const auto [resume, start] = resume_point(*details);
            (void)start;
            series_selected_ = details->video.parts.size() > 1 ? resume : 0;
            if (details->video.parts.size() <= 1) {
                for (size_t i = 0; i < details->video.collection.size(); ++i) {
                    if (details->video.collection[i].bvid == details->video.bvid) series_selected_ = i;
                }
            }
            focus_ = Focus::Parts;
        }
    } else if (key.code == KeyCode::Tab) {
        select_tab(static_cast<TabId>((static_cast<int>(tab_) + 1) % 3));
    } else if (key.code == KeyCode::BackTab) {
        select_tab(static_cast<TabId>((static_cast<int>(tab_) + 2) % 3));
    } else if (key.is(U'1')) {
        select_tab(TabId::Search);
    } else if (key.is(U'2')) {
        select_tab(TabId::Learn);
    } else if (key.is(U'3')) {
        select_tab(TabId::Follow);
    } else if (key.is(U's')) {
        tab_ = TabId::Search;
        focus_ = Focus::Input;
        update_choices();
    } else if (key.is(U'/')) {
        filter_before_ = list().filter;
        filter_keep_ = selected_video() ? selected_video()->key() : "";
        focus_ = Focus::Filter;
    } else if (key.is(U'o') || key.is(U't')) {
        if (key.is(U'o')) order_ = (order_ + 1) % 3;
        else duration_ = (duration_ + 1) % 5;
        if (tab_ == TabId::Search && list().source.type == Source::Type::Search) submit_search();
    } else if (key.is(U'a')) {
        queue_selected();
    } else if (key.is(U'w')) {
        add_to_view_later();
    } else if (key.is(U'u')) {
        open_up();
    } else if (key.is(U'R')) {
        refresh(list(), false);
    } else if (key.is(U' ')) {
        open_menu();
    } else if (key.code == KeyCode::Escape) {
        back();
    }
    return false;
}
void App::set_focus_state(bool focused) {
    focused_ = focused;
    if (!focused) {
        // Passive reads stop while unfocused; explicit playback and downloads continue.
        if (details_task_ && pending_play_.empty()) details_task_->store(true);
        if (cover_task_) cover_task_->store(true);
        if (login_task_) login_task_->store(true);
        login_polling_ = false;
        preview_due_.reset();
        cover_due_.reset();
        cover_requested_.clear();
    } else {
        selection_changed();
        if (modal_ && modal_->kind == Modal::Kind::Qr) modal_->qr_last = Clock::now();
    }
}
std::optional<TimePoint> App::next_deadline() const {
    std::optional<TimePoint> out;
    const auto consider = [&](TimePoint when) {
        if (!out || when < *out) out = when;
    };
    if (!notice_.empty()) consider(notice_until_);
    if (focused_) {
        if (preview_due_) consider(*preview_due_);
        if (cover_due_) consider(*cover_due_);
        if (modal_ && modal_->kind == Modal::Kind::Qr && !modal_->qr_key.empty() && !login_polling_) consider(modal_->qr_last + 3s);
    }
    return out;
}
void App::tick() {
    const auto now = Clock::now();
    if (!notice_.empty() && now >= notice_until_) notice_.clear();
    if (!focused_) return;
    poll_login();
    if (preview_due_ && now >= *preview_due_) {
        preview_due_.reset();
        const Video* video = selected_video();
        if (video && video->kind == Kind::Video && !details_.count(video->bvid)) request_details(video->bvid);
    }
    if (cover_due_ && now >= *cover_due_) {
        cover_due_.reset();
        const Video* video = selected_video();
        const bool kitty = std::getenv("KITTY_WINDOW_ID") != nullptr;
        if (kitty && !demo_ && video && video->kind == Kind::Video && !video->cover.empty() && video->cover != cover_requested_ && width_ >= 110) {
            cover_requested_ = video->cover;
            run_task(cover_task_, [url = video->cover](const CancelFlag& cancel) {
                auto image = fetch_cover(url, cancel);
                return std::function<void(App&)>([url, image = std::move(image)](App& app) {
                    if (image) app.cover_ = std::make_pair(url, *image);
                });
            }, false);
        }
    }
}
void App::paint_cover(Terminal& terminal) {
    const Video* video = selected_video();
    if (modal_ || !focused_ || !cover_rect_ || !cover_ || !video || cover_->first != video->cover) {
        terminal.hide_image();
        return;
    }
    terminal.show_image(cover_->second, cover_->first, cover_rect_->x, cover_rect_->y, cover_rect_->width, cover_rect_->height);
}
static int wake_pipe[2] = {-1, -1};
static void on_signal(int number) {
    const unsigned char byte = number == SIGWINCH ? 'w' : 'q';
    [[maybe_unused]] const auto ignored = ::write(wake_pipe[1], &byte, 1);
}
int App::run() {
    if (::pipe2(wake_pipe, O_CLOEXEC | O_NONBLOCK) != 0) throw std::runtime_error("无法初始化事件循环");
    struct sigaction action {};
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    sigaction(SIGWINCH, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGHUP, &action, nullptr);
    Terminal terminal;
    terminal_ = &terminal;
    InputParser parser;
    start();
    bool dirty = true;
    bool quit = false;
    while (!quit) {
        tick();
        if (dirty && focused_) {
            const auto [width, height] = terminal.size();
            set_size(width, height);
            ftxui::Screen screen(width, height);
            draw(screen);
            terminal.present(screen, cursor_);
            paint_cover(terminal);
            dirty = false;
        }
        int timeout = -1;
        if (parser.pending()) {
            timeout = 30;
        } else if (const auto deadline = next_deadline()) {
            timeout = static_cast<int>(std::clamp<int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(*deadline - Clock::now()).count() + 1, 0, 60000));
        }
        pollfd fds[3]{{STDIN_FILENO, POLLIN, 0}, {mailbox_.fd(), POLLIN, 0}, {wake_pipe[0], POLLIN, 0}};
        const int ready = ::poll(fds, 3, timeout);
        if (ready < 0 && errno != EINTR) break;
        if (ready == 0) {
            if (parser.pending()) {
                for (const auto& event : parser.flush()) {
                    quit = handle(event) || quit;
                }
            }
            dirty = true;
            continue;
        }
        if (ready < 0) continue;
        if (fds[2].revents & POLLIN) {
            unsigned char bytes[16];
            const ssize_t got = ::read(wake_pipe[0], bytes, sizeof bytes);
            for (ssize_t i = 0; i < got; ++i) {
                if (bytes[i] == 'q') quit = true;
                if (bytes[i] == 'w') terminal.invalidate();
            }
            dirty = true;
        }
        if (fds[1].revents & POLLIN) {
            drain();
            dirty = true;
        }
        if (fds[0].revents & (POLLIN | POLLHUP)) {
            char buffer[4096];
            const ssize_t got = ::read(STDIN_FILENO, buffer, sizeof buffer);
            if (got == 0 && (fds[0].revents & POLLHUP)) break;
            if (got > 0) {
                const bool was_focused = focused_;
                for (const auto& event : parser.feed(std::string_view(buffer, static_cast<size_t>(got)))) {
                    quit = handle(event) || quit;
                }
                if (!was_focused && focused_) terminal.invalidate();
                if (was_focused && !focused_) terminal.hide_image();
                dirty = true;
            }
        }
    }
    terminal_ = nullptr;
    return 0;
}
}  // namespace bili
