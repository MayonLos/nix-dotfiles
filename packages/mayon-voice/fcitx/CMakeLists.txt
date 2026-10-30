cmake_minimum_required(VERSION 3.16)
project(mayon_voice_fcitx VERSION 0.1.0 LANGUAGES CXX)

find_package(Fcitx5Core REQUIRED)
find_package(Fcitx5Module REQUIRED COMPONENTS DBus)

add_fcitx5_addon(mayonvoice mayonvoice.cpp)
target_link_libraries(mayonvoice PRIVATE Fcitx5::Core Fcitx5::Module::DBus)
target_compile_features(mayonvoice PRIVATE cxx_std_20)
install(TARGETS mayonvoice DESTINATION "${FCITX_INSTALL_ADDONDIR}")

configure_file(mayonvoice.conf.in.in mayonvoice.conf @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/mayonvoice.conf"
  DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon")
