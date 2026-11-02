keys_inc = include_directories('.', '..')
keys_deps = ui_deps + [dependency('nlohmann_json')]
keys_lib = static_library('keys', ['model.cpp', 'fuzzy.cpp', 'page.cpp'], include_directories: keys_inc, link_with: ui, dependencies: keys_deps)
keys_demo = executable('keys-demo', 'demo.cpp', include_directories: keys_inc, link_with: [keys_lib, ui], dependencies: keys_deps, install: false)
keys_fixtures = meson.current_source_dir() / 'tests/fixtures'
test('keys', executable('keys-tests', 'tests.cpp', include_directories: keys_inc, link_with: [keys_lib, ui], dependencies: keys_deps + [doctest],
  cpp_args: ['-DFIXTURES="' + keys_fixtures + '"']))
# The crate's own export check. Outside the package source in a Nix build, so it is optional.
keys_check = '../../mayon-tui/crates/keys/check_bindings.py'
keys_python = find_program('python3', required: false)
if keys_python.found() and import('fs').exists(keys_check)
  keys_listed = custom_target('keys-listed', output: 'keys-listed.json', capture: true,
    command: [keys_demo, '--data', keys_fixtures / 'bindings.json', 'list', '--json'])
  test('keys-check-bindings', keys_python, args: [meson.current_source_dir() / keys_check, keys_fixtures / 'bindings.json', keys_fixtures / 'mango.conf', keys_listed])
endif
