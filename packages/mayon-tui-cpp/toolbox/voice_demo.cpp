// Runs the voice dashboard on its own terminal for parity checks and screenshots;
// the toolbox is the real entry.
#include <exception>
#include <iostream>

#include "ui/page.hpp"
#include "voice.hpp"

int main() {
    try {
        const auto page = make_voice_page();
        return tui::run_page(*page);
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << "\n";
        return 1;
    }
}
