/* Isolated librime checks; arguments are public input/expected-candidate pairs. */
#include <rime_api.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc < 5 || argc % 2 != 1) return 2;
  RimeApi *api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.app_name = "rime.dotfiles-check";
  traits.log_dir = "";
  traits.min_log_level = 0;
  api->setup(&traits);
  api->initialize(&traits);
  if (!api->find_module("lua") || !api->find_module("octagram")) {
    fprintf(stderr, "Missing Lua or Octagram module\n");
    api->finalize();
    return 1;
  }
  if (api->start_maintenance(True)) api->join_maintenance_thread();
  RimeSessionId session = api->create_session();
  int failed = !session || !api->select_schema(session, "rime_ice");
  for (int i = 3; !failed && i + 1 < argc; i += 2) {
    api->clear_composition(session);
    api->set_option(session, "ascii_mode", False);
    api->simulate_key_sequence(session, argv[i]);
    int found = 0;
    for (int page = 0; page < 4 && !found; ++page) {
      RIME_STRUCT(RimeContext, context);
      if (!api->get_context(session, &context)) break;
      for (int j = 0; j < context.menu.num_candidates; ++j) {
        if (strcmp(context.menu.candidates[j].text, argv[i + 1]) == 0)
          found = 1;
      }
      int last = context.menu.is_last_page;
      api->free_context(&context);
      if (last) break;
      api->process_key(session, 0xff56, 0); /* Page_Down */
    }
    printf("%s -> %s: %s\n", argv[i], argv[i + 1], found ? "PASS" : "FAIL");
    if (!found) failed = 1;
  }
  if (session) api->destroy_session(session);
  api->finalize();
  return failed;
}
