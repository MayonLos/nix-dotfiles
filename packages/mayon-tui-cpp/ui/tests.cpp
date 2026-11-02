#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <ftxui/screen/screen.hpp>

#include "ui/draw.hpp"

using namespace tui;
TEST_CASE("clip keeps wide characters whole and marks the cut") {
    CHECK(clip("信号与系统", 20) == "信号与系统");
    CHECK(clip("信号与系统", 6) == "信号…");
    CHECK(width_of(clip("信号与系统", 6)) <= 6);
    CHECK(clip("abc", 0).empty());
}
TEST_CASE("put never leaves half of a wide character at its limit") {
    ftxui::Screen screen(10, 1);
    CHECK(put(screen, 0, 0, "信号", Style{}, 3) == 2);
    CHECK(screen.PixelAt(0, 0).character == "信");
    CHECK(screen.PixelAt(2, 0).character != "号");
    ftxui::Screen edge(3, 1);
    CHECK(put(edge, 0, 0, "信号", Style{}) == 2);
}
TEST_CASE("wrap respects cell width and the line limit") {
    const auto lines = wrap("信号与系统", 4, 2);
    REQUIRE(lines.size() == 2);
    CHECK(lines[0] == "信号");
    CHECK(lines[1] == "与系");
}
TEST_CASE("hints collapse to what fits and always point to help") {
    const std::vector<Hint> hints{{"Enter", "播放"}, {"a", "排队"}, {"/", "过滤"}, {"?", "帮助"}};
    CHECK(fit_hints(hints, 200).size() == 4);
    const auto narrow = fit_hints(hints, 22);
    REQUIRE(!narrow.empty());
    CHECK(narrow.front().key == "Enter");
    CHECK(narrow.back().action == "更多");
}
TEST_CASE("centered stays inside the outer area") {
    const Rect area = centered(20, 10, 40, 4);
    CHECK(area.x == 0);
    CHECK(area.width == 20);
    CHECK(area.y == 3);
}
