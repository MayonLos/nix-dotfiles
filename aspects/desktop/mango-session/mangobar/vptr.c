/* Read "move <x> <y>" / "button <evdev-code> <pressed>" lines on stdin and
 * inject them through zwlr_virtual_pointer_v1. Used only by the isolated
 * mangobar tray test: the headless compositor has no physical pointer, so the
 * bar needs a pointer device before it can receive context-menu clicks. */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static int width = 2560;
static int height = 1600;

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
  (void)data;
  (void)version;
  if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
    manager = wl_registry_bind(registry, name,
                               &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                   uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

int main(int argc, char **argv) {
  if (argc == 3) {
    width = atoi(argv[1]);
    height = atoi(argv[2]);
  }
  if (width <= 0 || height <= 0) {
    fprintf(stderr, "vptr: bad extents\n");
    return 1;
  }
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) {
    fprintf(stderr, "vptr: cannot connect to compositor\n");
    return 1;
  }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (!manager) {
    fprintf(stderr, "vptr: compositor has no zwlr_virtual_pointer_manager_v1\n");
    return 2;
  }
  struct zwlr_virtual_pointer_v1 *pointer =
      zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
  if (!pointer) {
    fprintf(stderr, "vptr: cannot create virtual pointer\n");
    return 3;
  }
  if (wl_display_roundtrip(display) < 0) {
    fprintf(stderr, "vptr: display roundtrip failed\n");
    return 4;
  }
  printf("READY\n");
  fflush(stdout);

  char line[256];
  while (fgets(line, sizeof(line), stdin)) {
    int x, y, button, pressed;
    if (sscanf(line, "move %d %d", &x, &y) == 2) {
      zwlr_virtual_pointer_v1_motion_absolute(pointer, 0, (uint32_t)x,
                                              (uint32_t)y, (uint32_t)width,
                                              (uint32_t)height);
      zwlr_virtual_pointer_v1_frame(pointer);
    } else if (sscanf(line, "button %d %d", &button, &pressed) == 2) {
      zwlr_virtual_pointer_v1_button(pointer, 0, (uint32_t)button,
                                     pressed ? 1 : 0);
      zwlr_virtual_pointer_v1_frame(pointer);
    } else if (strncmp(line, "quit", 4) == 0) {
      break;
    }
    if (wl_display_flush(display) < 0) {
      fprintf(stderr, "vptr: flush failed\n");
      break;
    }
  }
  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_disconnect(display);
  return 0;
}
