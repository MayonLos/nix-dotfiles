/*
 * Send Ctrl+V or Ctrl+Shift+V through the virtual-keyboard protocol.
 *
 * wtype 0.4's `-k v` assigns that key evdev code 1. On this Mango that is
 * Escape, and Ctrl+Shift+Escape opens the btop scratchpad. wlroots 0.20 also
 * rejects modifiers until the client has defined a keymap. Upload a normal
 * evdev keymap, then send KEY_V (47): that position is V, not Escape.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "virtual-keyboard-unstable-v1-client-protocol.h"

#define KEY_V 47
#define MOD_SHIFT 1u
#define MOD_CTRL 4u
#define KEYMAP_FORMAT_XKB_V1 1u

static const char keymap_text[] =
	"xkb_keymap {\n"
	"xkb_keycodes { include \"evdev+aliases(qwerty)\" };\n"
	"xkb_types { include \"complete\" };\n"
	"xkb_compat { include \"complete\" };\n"
	"xkb_symbols { include \"pc+us+inet(evdev)\" };\n"
	"};\n";

static int send_keymap(struct zwp_virtual_keyboard_v1 *keyboard) {
	size_t len = strlen(keymap_text);
	int fd = memfd_create("paste-key-keymap", MFD_CLOEXEC);
	ssize_t written;

	if (fd < 0)
		return -1;
	written = write(fd, keymap_text, len);
	if (written != (ssize_t)len || lseek(fd, 0, SEEK_SET) < 0) {
		close(fd);
		return -1;
	}
	zwp_virtual_keyboard_v1_keymap(keyboard, KEYMAP_FORMAT_XKB_V1, fd,
								   (uint32_t)len);
	return fd;
}

struct paste_state {
	struct wl_seat *seat;
	struct zwp_virtual_keyboard_manager_v1 *manager;
};

static void registry_global(void *data, struct wl_registry *registry,
							uint32_t name, const char *interface,
							uint32_t version) {
	struct paste_state *state = data;

	(void)version;
	if (strcmp(interface, wl_seat_interface.name) == 0) {
		state->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
	} else if (strcmp(interface,
					  zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
		state->manager = wl_registry_bind(
			registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
	}
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

static int fail(const char *message) {
	fprintf(stderr, "paste-key: %s\n", message);
	return 1;
}

int main(int argc, char **argv) {
	struct wl_display *display;
	struct wl_registry *registry;
	struct paste_state state = {0};
	struct zwp_virtual_keyboard_v1 *keyboard;
	int keymap_fd = -1;
	uint32_t mods = 0;
	int saw_v = 0;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "ctrl") == 0) {
			mods |= MOD_CTRL;
		} else if (strcmp(argv[i], "shift") == 0) {
			mods |= MOD_SHIFT;
		} else if (strcmp(argv[i], "v") == 0) {
			saw_v = 1;
		} else {
			fprintf(stderr, "paste-key: unknown argument %s\n", argv[i]);
			return 1;
		}
	}
	if (!saw_v)
		return fail("usage: paste-key [ctrl] [shift] v");

	display = wl_display_connect(NULL);
	if (!display)
		return fail("no wayland display");

	registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, &state);
	if (wl_display_roundtrip(display) < 0)
		return fail("wayland roundtrip failed");
	if (!state.seat || !state.manager)
		return fail("compositor has no seat or virtual keyboard");

	keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(
		state.manager, state.seat);
	if (wl_display_roundtrip(display) < 0)
		return fail("wayland roundtrip failed");

	keymap_fd = send_keymap(keyboard);
	if (keymap_fd < 0)
		return fail("could not send keymap");
	if (wl_display_roundtrip(display) < 0) {
		close(keymap_fd);
		return fail("keymap was rejected");
	}
	close(keymap_fd);

	zwp_virtual_keyboard_v1_modifiers(keyboard, mods, 0, 0, 0);
	if (wl_display_roundtrip(display) < 0)
		return fail("wayland roundtrip failed");
	zwp_virtual_keyboard_v1_key(keyboard, 0, KEY_V, 1);
	if (wl_display_roundtrip(display) < 0)
		return fail("wayland roundtrip failed");
	/* Let the client finish a shortcut such as Kitty's clipboard paste
	   before the release. An immediate release cancels that read. */
	usleep(100000);
	zwp_virtual_keyboard_v1_key(keyboard, 0, KEY_V, 0);
	if (wl_display_roundtrip(display) < 0)
		return fail("wayland roundtrip failed");
	zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
	if (wl_display_roundtrip(display) < 0)
		return fail("wayland roundtrip failed");

	zwp_virtual_keyboard_v1_destroy(keyboard);
	wl_registry_destroy(registry);
	wl_display_roundtrip(display);
	wl_display_disconnect(display);
	return 0;
}
