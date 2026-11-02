serial_inc = include_directories('.', '..')
serial_deps = ui_deps + [dependency('nlohmann_json')]
serial_lib = static_library('serial', ['baud.cpp', 'codec.cpp', 'store.cpp', 'transport.cpp', 'flash.cpp', 'app.cpp', 'page.cpp'],
  include_directories: serial_inc, link_with: ui, dependencies: serial_deps)
serial_demo = executable('serial-demo', 'demo.cpp', include_directories: serial_inc, link_with: [serial_lib, ui], dependencies: serial_deps, install: false)
serial_fixtures = meson.current_source_dir() / 'tests/fixtures'
test('serial', executable('serial-tests', 'tests.cpp', include_directories: serial_inc, link_with: [serial_lib, ui], dependencies: serial_deps + [doctest],
  cpp_args: ['-DFIXTURES="' + serial_fixtures + '"']))
