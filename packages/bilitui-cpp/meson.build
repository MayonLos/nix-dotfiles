project('bilitui-next', 'cpp', version: '0.1.0', default_options: ['cpp_std=c++23', 'warning_level=2', 'werror=true', 'b_lto=false'])
deps = [
  dependency('libcurl'),
  dependency('nlohmann_json'),
  dependency('ftxui'),
  dependency('libqrencode'),
  dependency('libturbojpeg'),
  dependency('threads'),
]
add_project_arguments('-Wno-missing-field-initializers', language: 'cpp')
inc = include_directories('src')
core = static_library('core', [
    'src/core/text.cpp', 'src/core/model.cpp', 'src/core/search.cpp', 'src/core/wbi.cpp',
    'src/net/http.cpp', 'src/net/api.cpp', 'src/store.cpp',
    'src/media/process.cpp', 'src/media/stream.cpp', 'src/media/player.cpp', 'src/media/download.cpp',
    'src/ui/keys.cpp', 'src/ui/input.cpp', 'src/ui/terminal.cpp',
    'src/app.cpp', 'src/view.cpp',
  ], include_directories: inc, dependencies: deps)
executable('bilitui-next', 'src/main.cpp', include_directories: inc, link_with: core, dependencies: deps, install: true)
doctest = dependency('doctest')
test('unit', executable('tests', 'tests/tests.cpp', include_directories: inc, link_with: core, dependencies: deps + [doctest],
  cpp_args: ['-DFIXTURES="' + meson.current_source_dir() / 'tests/fixtures' + '"']))
