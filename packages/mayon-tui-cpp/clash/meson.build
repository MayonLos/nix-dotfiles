clash_inc = include_directories('.', '..')
clash_deps = ui_deps + [dependency('nlohmann_json')]
clash_lib = static_library('clash',
  ['api.cpp', 'model.cpp', 'native.cpp', 'matcher.cpp', 'yaml.cpp', 'app.cpp', 'ui.cpp', 'cli.cpp', 'page.cpp'],
  include_directories: clash_inc, link_with: ui, dependencies: clash_deps)
clash_demo = executable('clash-demo', 'demo.cpp', include_directories: clash_inc, link_with: [clash_lib, ui], dependencies: clash_deps, install: false)
clash_main = executable('clashtui-next', 'main.cpp', include_directories: clash_inc, link_with: [clash_lib, ui], dependencies: clash_deps, install: true)
clash_fixtures = meson.current_source_dir() / 'tests/fixtures'
test('clash', executable('clash-tests', 'tests.cpp', include_directories: clash_inc, link_with: [clash_lib, ui], dependencies: clash_deps + [doctest],
  cpp_args: ['-DFIXTURES="' + clash_fixtures + '"']))
