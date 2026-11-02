#include "page.hpp"

namespace {
class Placeholder : public tui::Page {
    void draw(ftxui::Screen& screen, tui::Rect area) override { tui::put(screen, area.x + 2, area.y + 1, "serial", tui::Style{tui::kMuted}); }
    bool handle(const tui::InputEvent& event) override { return event.key.is(U'q'); }
};
}  // namespace
std::unique_ptr<tui::Page> make_serial_page() { return std::make_unique<Placeholder>(); }
