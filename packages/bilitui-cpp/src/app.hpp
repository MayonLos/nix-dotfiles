// Application state and input handling. Everything here runs on the UI thread.
#pragma once
#include <array>
#include <chrono>
#include <deque>
#include <ftxui/screen/screen.hpp>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "core/model.hpp"
#include "mailbox.hpp"
#include "media/download.hpp"
#include "media/player.hpp"
#include "media/stream.hpp"
#include "net/api.hpp"
#include "store.hpp"
#include "ui/input.hpp"
#include "ui/keys.hpp"

namespace bili {
class Terminal;
using TimePoint = std::chrono::steady_clock::time_point;
enum class TabId { Search = 0, Learn = 1, Follow = 2 };
enum class Focus { Input, List, Parts, Filter };
struct Rect {
    int x = 0, y = 0, width = 0, height = 0;
    bool contains(int px, int py) const { return px >= x && py >= y && px < x + width && py < y + height; }
};
struct Source {
    enum class Type { None, Search, Up, Folder, Feed, Learning } type = Type::None;
    std::string query;
    int order = 0;
    int duration = 0;
    uint64_t id = 0;
    uint64_t page = 1;
    std::string cursor;
    bool more = false;
};
struct ListState {
    uint64_t id = 0;
    std::string heading;
    std::vector<Video> items;
    std::vector<size_t> visible;
    size_t selected = 0;
    size_t offset = 0;
    TextInput filter;
    Source source;
    bool loading = false;
    bool loaded = false;
    std::string error;
};
struct Details {
    Video video;
    PlayerInfo info;
};
struct MenuItem {
    std::string label;
    std::function<void(App&)> action;
};
struct Modal {
    enum class Kind { Help, Error, Menu, Qr, Downloads } kind = Kind::Help;
    std::string title;
    std::string text;
    std::vector<MenuItem> items;
    size_t selected = 0;
    std::string qr_key;
    std::string qr_art;
    TimePoint qr_last{};
};
struct DownloadRow {
    std::string title;
    std::string state;
    uint64_t bytes = 0;
};
extern const std::array<const char*, 3> kOrderNames;
extern const std::array<const char*, 5> kDurationNames;
struct Page {
    std::vector<Video> items;
    std::string heading;
    std::string cursor;
    bool more = false;
};
Page fetch_page(Api& api, const Source& source, const CancelFlag& cancel);
std::pair<size_t, uint64_t> resume_point(const Details& details);

class App {
public:
    App(std::shared_ptr<Api> api, Config config, bool demo);
    ~App();
    int run();
    // The pieces below are the tested surface of the interface.
    bool handle(const InputEvent& event);
    void draw(ftxui::Screen& screen);
    void start();
    void drain();
    void tick();
    std::optional<TimePoint> next_deadline() const;
    ListState& list();
    const ListState& list() const;
    Focus focus() const { return focus_; }
    TabId tab() const { return tab_; }
    const std::optional<Modal>& modal() const { return modal_; }
    const std::string& notice() const { return notice_; }
    void set_notice(std::string text, bool error = false);
    void apply_page(uint64_t list_id, Page page, bool append);
    void put_details(Details details);
    const Video* selected_video() const;
    void select_tab(TabId tab);
    void set_size(int width, int height);
    void set_focus_state(bool focused);
    bool focused() const { return focused_; }
    std::string input_text() const { return search_.str(); }
    const std::vector<PlayItem>& demo_played() const { return demo_played_; }

private:
    friend struct Actions;
    void rebuild_visible(ListState& state, const std::string& keep_key);
    void move(int delta);
    void selection_changed();
    void load_more();
    void refresh(ListState& state, bool append);
    void submit_search();
    void update_choices();
    void play_selected();
    void play_part(size_t index);
    void queue_selected();
    void add_to_view_later();
    void open_up();
    void open_row(const Video& row);
    void open_menu();
    void start_login();
    void poll_login();
    void change_quality();
    void add_to_favourite();
    void enqueue_download(char mode);
    void copy_link();
    void open_browser();
    bool back();
    void run_task(CancelFlag& slot, std::function<std::function<void(App&)>(const CancelFlag&)> work, bool show_error = true);
    void fire_and_report(std::function<std::string()> work);
    void request_details(const std::string& bvid);
    void draw_list(ftxui::Screen& screen, Rect area);
    void draw_preview(ftxui::Screen& screen, Rect area);
    void draw_modal(ftxui::Screen& screen);
    void paint_cover(Terminal& terminal);
    std::vector<std::string> series_rows(const Details& details) const;
    const Details* selected_details() const;

    std::shared_ptr<Api> api_;
    Config config_;
    bool demo_;
    Mailbox mailbox_;
    std::array<std::vector<ListState>, 3> tabs_;
    TabId tab_ = TabId::Search;
    Focus focus_ = Focus::Input;
    TextInput search_;
    TextInput filter_before_;
    std::string filter_keep_;
    std::vector<std::string> choices_;
    std::optional<size_t> choice_;
    bool choices_open_ = true;
    int order_ = 0;
    int duration_ = 0;
    std::optional<Modal> modal_;
    std::string notice_;
    bool notice_error_ = false;
    TimePoint notice_until_{};
    bool focused_ = true;
    int width_ = 80;
    int height_ = 24;
    std::map<std::string, Details> details_;
    std::string pending_play_;
    size_t pending_part_ = SIZE_MAX;
    bool pending_queue_ = false;
    std::optional<TimePoint> preview_due_;
    std::optional<TimePoint> cover_due_;
    size_t series_selected_ = 0;
    size_t series_offset_ = 0;
    std::string cover_requested_;
    std::optional<std::pair<std::string, Image>> cover_;
    std::optional<Rect> cover_rect_;
    std::optional<std::pair<int, int>> cursor_;
    Rect list_rect_;
    Rect preview_rect_;
    uint64_t next_list_id_ = 1;
    PlayerStatus player_status_;
    std::vector<DownloadRow> downloads_;
    std::vector<PlayItem> demo_played_;
    Terminal* terminal_ = nullptr;
    bool login_polling_ = false;
    CancelFlag list_task_;
    CancelFlag details_task_;
    CancelFlag cover_task_;
    CancelFlag login_task_;
    CancelFlag misc_task_;
    // Destroyed first, so workers stop before the state they report into.
    std::unique_ptr<Pool> pool_;
    std::unique_ptr<Player> player_;
    std::unique_ptr<Downloader> downloader_;
};
}  // namespace bili
