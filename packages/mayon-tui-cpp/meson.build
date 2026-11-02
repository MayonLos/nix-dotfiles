project('mayon-tui-cpp', 'cpp', version: '0.1.0', default_options: ['cpp_std=c++23', 'warning_level=2', 'werror=true', 'b_lto=false'])
add_project_arguments('-Wno-missing-field-initializers', language: 'cpp')
ftxui = dependency('ftxui')
threads = dependency('threads')
doctest = dependency('doctest')
ui_deps = [ftxui, threads]
ui_inc = include_directories('.')
ui = static_library('mayon-ui', [
    'ui/text.cpp', 'ui/search.cpp', 'ui/keys.cpp', 'ui/input.cpp', 'ui/terminal.cpp', 'ui/draw.cpp',
  ], include_directories: ui_inc, dependencies: ui_deps)
test('ui', executable('ui-tests', 'ui/tests.cpp', include_directories: ui_inc, link_with: ui, dependencies: ui_deps + [doctest]))
subdir('bilitui')
