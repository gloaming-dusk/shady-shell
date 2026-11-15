#ifndef SHADY_SHELL_CLIPBOARD_H
#define SHADY_SHELL_CLIPBOARD_H

/*
 * The clipboard, through wlr-data-control: the shell serves what it copies
 * itself (no wl-copy process), and reads what every other client copies,
 * so a config can keep a history. Text and PNG pictures; a copy a password
 * manager marks as secret (x-kde-passwordManagerHint) is never read.
 *
 * Every selection that is read becomes the Lua event "clipboard" with
 * ("text", text) or ("image", path): pictures are written to
 * $XDG_CACHE_HOME/shady/clipboard/.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct shell;
struct wl_registry;

/* From the registry: take zwlr_data_control_manager_v1. True if it was. */
bool shell_clipboard_global(struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version);
/* After the first roundtrips, with the seat known. */
void shell_clipboard_init(struct shell *shell);
void shell_clipboard_finish(void);

bool shell_clipboard_available(void);
/* Serve `data` as the selection under `mime` ("text/plain;charset=utf-8"
 * offers the usual text names too). The data is copied. */
bool shell_clipboard_set(const char *mime, const void *data, size_t len);
/* What is on the clipboard as last seen: kind "text" or "image" (the
 * picture's path), or NULL for nothing or something else. */
const char *shell_clipboard_current(const char **kind);
/* After serving a picture the shell copied from `path`: that is now what
 * is on the clipboard. */
void shell_clipboard_note_image(const char *path);

#endif
