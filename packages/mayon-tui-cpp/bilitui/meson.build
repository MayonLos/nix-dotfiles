bili_deps = ui_deps + [
  dependency('libcurl'),
  dependency('nlohmann_json'),
  dependency('libqrencode'),
  dependency('libturbojpeg'),
]
bili_inc = include_directories('.', '..')
bili = static_library('bilitui', [
    'core/model.cpp', 'core/wbi.cpp',
    'net/http.cpp', 'net/api.cpp', 'store.cpp',
    'media/process.cpp', 'media/stream.cpp', 'media/player.cpp', 'media/download.cpp',
    'app.cpp', 'view.cpp',
  ], include_directories: bili_inc, link_with: ui, dependencies: bili_deps)
executable('bilitui-next', 'main.cpp', include_directories: bili_inc, link_with: [bili, ui], dependencies: bili_deps, install: true)
test('bilitui', executable('bilitui-tests', 'tests/tests.cpp', include_directories: bili_inc, link_with: [bili, ui], dependencies: bili_deps + [doctest],
  cpp_args: ['-DFIXTURES="' + meson.current_source_dir() / 'tests/fixtures' + '"']))
