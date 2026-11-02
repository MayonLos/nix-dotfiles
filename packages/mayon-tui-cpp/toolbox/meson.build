toolbox_inc = include_directories('.', '..')
toolbox_deps = ui_deps + [dependency('nlohmann_json')]
toolbox_lib = static_library('toolbox', ['shell.cpp', 'voice.cpp'], include_directories: toolbox_inc,
  link_with: ui, dependencies: toolbox_deps)
voice_demo = executable('voice-demo', 'voice_demo.cpp', include_directories: toolbox_inc,
  link_with: [toolbox_lib, ui], dependencies: toolbox_deps, install: false)
toolbox_fixtures = meson.current_source_dir() / 'tests/fixtures'
test('toolbox', executable('toolbox-tests', 'tests.cpp', include_directories: toolbox_inc,
  link_with: [toolbox_lib, ui], dependencies: toolbox_deps + [doctest],
  cpp_args: ['-DFIXTURES="' + toolbox_fixtures + '"']))
executable('mayon-tools-next', 'main.cpp', include_directories: toolbox_inc,
  link_with: [toolbox_lib, ports_lib, keys_lib, docker_lib, serial_lib, ui],
  dependencies: toolbox_deps, install: true)
