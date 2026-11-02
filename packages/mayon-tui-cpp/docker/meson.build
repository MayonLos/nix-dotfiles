docker_inc = include_directories('.', '..')
docker_deps = ui_deps + [dependency('nlohmann_json')]
docker_lib = static_library('docker', ['api.cpp', 'cleanup.cpp', 'vm.cpp', 'vm_xml.cpp', 'app.cpp', 'cli.cpp', 'page.cpp'],
  include_directories: docker_inc, link_with: ui, dependencies: docker_deps)
docker_demo = executable('docker-demo', 'demo.cpp', include_directories: docker_inc,
  link_with: [docker_lib, ui], dependencies: docker_deps, install: false)
docker_fixtures = meson.current_source_dir() / 'tests/fixtures'
# End-to-end cases reuse the crate's Python mock Engine and mock virsh through the doctest
# binary, so the single `docker` test covers both unit and offline integration checks.
docker_python = find_program('python3', required: false)
docker_test_args = ['-DFIXTURES="' + docker_fixtures + '"', '-DDEMO="' + docker_demo.full_path() + '"']
if docker_python.found()
  docker_test_args += ['-DPYTHON="' + docker_python.full_path() + '"']
endif
docker_tests = executable('docker-tests', 'tests.cpp', include_directories: docker_inc,
  link_with: [docker_lib, ui], dependencies: docker_deps + [doctest], cpp_args: docker_test_args)
test('docker', docker_tests, timeout: 180)
