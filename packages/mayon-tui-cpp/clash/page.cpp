#include "page.hpp"

#include <iostream>

#include "app.hpp"
#include "ui/draw.hpp"

namespace {
// Shown when the arguments or the preferences file are invalid. main prints the
// same message before choosing to run the page, so this is mainly a safe fallback.
class ErrorPage : public tui::Page {
public:
    explicit ErrorPage(std::string message) : message_(std::move(message)) {}
    void draw(ftxui::Screen& screen, tui::Rect area) override {
        tui::put(screen, area.x + 1, area.y, "Clash TUI", tui::Style{tui::kBrightFg, {}, false, true});
        tui::put(screen, area.x + 1, area.y + 2, tui::clip(message_, std::max(area.width - 2, 1)), tui::Style{tui::kRed});
        tui::put_hints(screen, area.x + 1, area.y + area.height - 1, area.width - 2, {{"q", "退出"}});
    }
    bool handle(const tui::InputEvent& event) override {
        return event.type == tui::InputEvent::Type::Key && (event.key.is(U'q') || event.key.code == tui::KeyCode::Escape);
    }

private:
    std::string message_;
};
std::unique_ptr<tui::Page> page_for(const std::vector<std::string>& args) {
    clash::Options options;
    std::string error;
    const auto parsed = clash::parse_options(args, options, error);
    if (parsed == clash::ParseResult::Run) {
        try {
            return std::make_unique<clash::App>(std::move(options));
        } catch (const std::exception& failure) {
            return std::make_unique<ErrorPage>(failure.what());
        }
    }
    return std::make_unique<ErrorPage>(parsed == clash::ParseResult::Exit ? std::string("帮助已输出") : error);
}
}  // namespace

void clash::App::draw(ftxui::Screen& screen, tui::Rect area) { ui_draw(*this, screen, area); }

std::unique_ptr<tui::Page> make_clash_page() { return page_for({}); }
std::unique_ptr<tui::Page> make_clash_page(const std::vector<std::string>& args) { return page_for(args); }
int clash_cli(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return clash::run_cli(args, std::cin, std::cout, std::cerr);
}
