ports_inc = include_directories('.', '..')
ports_deps = ui_deps + [dependency('nlohmann_json')]
ports_lib = static_library('ports', ['page.cpp'], include_directories: ports_inc, link_with: ui, dependencies: ports_deps)
ports_demo = executable('ports-demo', 'demo.cpp', include_directories: ports_inc, link_with: [ports_lib, ui], dependencies: ports_deps, install: false)
test('ports', executable('ports-tests', 'tests.cpp', include_directories: ports_inc, link_with: [ports_lib, ui], dependencies: ports_deps + [doctest]))
