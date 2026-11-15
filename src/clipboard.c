#define _GNU_SOURCE

#include "clipboard.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "script.h"
#include "shell.h"
#include "wlr-data-control-unstable-v1-client-protocol.h"

#define TEXT_LIMIT (1024 * 1024)
#define IMAGE_LIMIT (16 * 1024 * 1024)
/* Offered with everything the shell copies, so its own selection is known
 * when the compositor hands it back. */
#define OWN_MIME "application/x-shady-shell"
#define SECRET_MIME "x-kde-passwordManagerHint"

static const char *const TEXT_MIMES[] = {
    "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING", NULL,
};

/* An offer and what it says it has. */
struct offer {
    struct zwlr_data_control_offer_v1 *offer;
    int text_rank; /* index in TEXT_MIMES of the best text, -1 for none */
    bool png, own, secret;
};

/* A selection being read from another client. */
struct reading {
    int fd;
    struct shell_watch *watch;
    bool image;
    char *data;
    size_t len, cap;
};

/* What the shell serves, and the writes to clients that asked for it. */
struct source {
    struct zwlr_data_control_source_v1 *source;
    char *mime;
    char *data;
    size_t len;
};

struct sending {
    struct wl_list link;
    int fd;
    struct shell_watch *watch;
    char *data;
    size_t len, off;
};

static struct {
    struct shell *shell;
    struct zwlr_data_control_manager_v1 *manager;
    struct zwlr_data_control_device_v1 *device;
    struct offer *selection;
    struct reading reading;
    struct source *source;
    struct wl_list sendings;
    char *current;
    const char *current_kind;
    unsigned image_serial;
    bool ready;
} cb = { .reading = { .fd = -1 } };

/* ---- what is on the clipboard -------------------------------------------- */

static void set_current(const char *kind, const char *value) {
    free(cb.current);
    cb.current = value ? strdup(value) : NULL;
    cb.current_kind = cb.current ? kind : NULL;
}

const char *shell_clipboard_current(const char **kind) {
    if (kind) *kind = cb.current_kind;
    return cb.current;
}

bool shell_clipboard_available(void) {
    return cb.device != NULL;
}

/* ---- reading another client's selection --------------------------------- */

static void reading_stop(void) {
    if (cb.reading.watch) shell_watch_remove(cb.reading.watch);
    if (cb.reading.fd >= 0) close(cb.reading.fd);
    free(cb.reading.data);
    cb.reading = (struct reading){ .fd = -1 };
}

static int mkdirs(const char *path) {
    char buf[4096];
    if (snprintf(buf, sizeof(buf), "%s", path) >= (int)sizeof(buf)) return -1;
    for (char *p = buf + 1; *p; p++) {
        if (*p != '/') continue;
        *p = '\0';
        if (mkdir(buf, 0700) < 0 && errno != EEXIST) return -1;
        *p = '/';
    }
    return mkdir(buf, 0700) < 0 && errno != EEXIST ? -1 : 0;
}

/* Pictures go to $XDG_CACHE_HOME/shady/clipboard/, named by time. */
static char *save_image(const char *data, size_t len) {
    const char *cache = getenv("XDG_CACHE_HOME");
    const char *home = getenv("HOME");
    char dir[4096];
    if (cache && *cache) snprintf(dir, sizeof(dir), "%s/shady/clipboard", cache);
    else if (home && *home) snprintf(dir, sizeof(dir), "%s/.cache/shady/clipboard", home);
    else return NULL;
    if (mkdirs(dir) < 0) return NULL;
    char path[4200];
    snprintf(path, sizeof(path), "%s/%lld-%u.png", dir, (long long)time(NULL), ++cb.image_serial);
    FILE *f = fopen(path, "wb");
    if (!f) return NULL;
    bool ok = fwrite(data, 1, len, f) == len;
    ok = fclose(f) == 0 && ok;
    if (!ok) {
        unlink(path);
        return NULL;
    }
    return strdup(path);
}

static void reading_done(void) {
    struct reading r = cb.reading;
    cb.reading.data = NULL;
    reading_stop();
    if (!r.data || r.len == 0) {
        free(r.data);
        return;
    }
    if (r.image) {
        char *path = save_image(r.data, r.len);
        free(r.data);
        if (!path) return;
        set_current("image", path);
        shell_lua_emit_strings(cb.shell, "clipboard", "image", path);
        free(path);
    } else {
        /* Text ends at its first NUL, as text does. */
        r.data[r.len] = '\0';
        set_current("text", r.data);
        shell_lua_emit_strings(cb.shell, "clipboard", "text", r.data);
        free(r.data);
    }
}

static void reading_ready(int fd, short revents, void *data) {
    (void)data;
    size_t limit = cb.reading.image ? IMAGE_LIMIT : TEXT_LIMIT;
    if (revents & POLLIN) {
        for (;;) {
            if (cb.reading.cap - cb.reading.len < 65536 + 1) {
                size_t cap = cb.reading.cap ? cb.reading.cap * 2 : 65536 * 2;
                char *grown = realloc(cb.reading.data, cap);
                if (!grown) {
                    reading_stop();
                    return;
                }
                cb.reading.data = grown;
                cb.reading.cap = cap;
            }
            ssize_t n = read(fd, cb.reading.data + cb.reading.len, 65536);
            if (n > 0) {
                cb.reading.len += (size_t)n;
                if (cb.reading.len > limit) {
                    fprintf(stderr, "shady-shell: clipboard: selection over %zu bytes, not kept\n", limit);
                    reading_stop();
                    return;
                }
                continue;
            }
            if (n == 0) {
                reading_done();
                return;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) return;
            if (errno == EINTR) continue;
            reading_stop();
            return;
        }
    }
    if (revents & (POLLHUP | POLLERR | POLLNVAL)) reading_done();
}

static void read_selection(struct offer *o) {
    reading_stop();
    const char *mime;
    bool image = false;
    if (o->text_rank >= 0) mime = TEXT_MIMES[o->text_rank];
    else if (o->png) { mime = "image/png"; image = true; }
    else return;
    int fds[2];
    if (pipe2(fds, O_CLOEXEC | O_NONBLOCK) < 0) return;
    zwlr_data_control_offer_v1_receive(o->offer, mime, fds[1]);
    wl_display_flush(cb.shell->core.display);
    close(fds[1]);
    cb.reading.fd = fds[0];
    cb.reading.image = image;
    cb.reading.watch = shell_watch_add(&cb.shell->core, fds[0], POLLIN, reading_ready, NULL);
    if (!cb.reading.watch) reading_stop();
}

/* ---- offers -------------------------------------------------------------- */

static void offer_mime(void *data, struct zwlr_data_control_offer_v1 *offer, const char *mime) {
    (void)offer;
    struct offer *o = data;
    if (!strcmp(mime, OWN_MIME)) o->own = true;
    else if (!strcmp(mime, SECRET_MIME)) o->secret = true;
    else if (!strcmp(mime, "image/png")) o->png = true;
    for (int i = 0; TEXT_MIMES[i]; i++) {
        if (!strcmp(mime, TEXT_MIMES[i]) && (o->text_rank < 0 || i < o->text_rank)) o->text_rank = i;
    }
}

static const struct zwlr_data_control_offer_v1_listener offer_listener = {
    .offer = offer_mime,
};

static void offer_free(struct offer *o) {
    if (!o) return;
    zwlr_data_control_offer_v1_destroy(o->offer);
    free(o);
}

static void device_data_offer(void *data, struct zwlr_data_control_device_v1 *device,
        struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)device;
    struct offer *o = calloc(1, sizeof(*o));
    if (!o) {
        zwlr_data_control_offer_v1_destroy(offer);
        return;
    }
    o->offer = offer;
    o->text_rank = -1;
    zwlr_data_control_offer_v1_add_listener(offer, &offer_listener, o);
}

static void device_selection(void *data, struct zwlr_data_control_device_v1 *device,
        struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)device;
    struct offer *o = offer ? zwlr_data_control_offer_v1_get_user_data(offer) : NULL;
    if (cb.selection && cb.selection != o) offer_free(cb.selection);
    cb.selection = o;
    if (!o) {
        reading_stop();
        set_current(NULL, NULL);
        return;
    }
    /* The shell's own copy is known already; a secret is not read. */
    if (o->own || o->secret) {
        reading_stop();
        if (o->secret) set_current(NULL, NULL);
        return;
    }
    read_selection(o);
}

static void device_finished(void *data, struct zwlr_data_control_device_v1 *device) {
    (void)data;
    zwlr_data_control_device_v1_destroy(device);
    if (cb.device == device) cb.device = NULL;
}

static void device_primary_selection(void *data, struct zwlr_data_control_device_v1 *device,
        struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)device;
    /* The primary selection is not followed; its offer is not needed. */
    if (offer) offer_free(zwlr_data_control_offer_v1_get_user_data(offer));
}

static const struct zwlr_data_control_device_v1_listener device_listener = {
    .data_offer = device_data_offer,
    .selection = device_selection,
    .finished = device_finished,
    .primary_selection = device_primary_selection,
};

/* ---- serving what the shell copies --------------------------------------- */

static void sending_free(struct sending *s) {
    wl_list_remove(&s->link);
    if (s->watch) shell_watch_remove(s->watch);
    close(s->fd);
    free(s->data);
    free(s);
}

static void sending_ready(int fd, short revents, void *data) {
    struct sending *s = data;
    if (revents & (POLLERR | POLLHUP | POLLNVAL)) {
        sending_free(s);
        return;
    }
    while (s->off < s->len) {
        ssize_t n = write(fd, s->data + s->off, s->len - s->off);
        if (n > 0) {
            s->off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
        break;
    }
    sending_free(s);
}

static void source_send(void *data, struct zwlr_data_control_source_v1 *zsource,
        const char *mime, int32_t fd) {
    (void)zsource; (void)mime;
    struct source *src = data;
    struct sending *s = calloc(1, sizeof(*s));
    if (!s || !(s->data = malloc(src->len ? src->len : 1))) {
        free(s);
        close(fd);
        return;
    }
    memcpy(s->data, src->data, src->len);
    s->len = src->len;
    s->fd = fd;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    wl_list_insert(&cb.sendings, &s->link);
    s->watch = shell_watch_add(&cb.shell->core, fd, POLLOUT, sending_ready, s);
    if (!s->watch) sending_free(s);
}

static void source_free(struct source *src) {
    if (!src) return;
    zwlr_data_control_source_v1_destroy(src->source);
    free(src->mime);
    free(src->data);
    free(src);
}

static void source_cancelled(void *data, struct zwlr_data_control_source_v1 *zsource) {
    (void)zsource;
    struct source *src = data;
    if (cb.source == src) cb.source = NULL;
    source_free(src);
}

static const struct zwlr_data_control_source_v1_listener source_listener = {
    .send = source_send,
    .cancelled = source_cancelled,
};

bool shell_clipboard_set(const char *mime, const void *data, size_t len) {
    if (!cb.device || !cb.manager || !mime || (!data && len)) return false;
    struct source *src = calloc(1, sizeof(*src));
    if (!src) return false;
    src->mime = strdup(mime);
    src->data = malloc(len ? len : 1);
    if (!src->mime || !src->data) {
        free(src->mime);
        free(src->data);
        free(src);
        return false;
    }
    if (len) memcpy(src->data, data, len);
    src->len = len;
    src->source = zwlr_data_control_manager_v1_create_data_source(cb.manager);
    zwlr_data_control_source_v1_add_listener(src->source, &source_listener, src);
    bool text = !strncmp(mime, "text/plain", 10);
    if (text) {
        for (int i = 0; TEXT_MIMES[i]; i++) zwlr_data_control_source_v1_offer(src->source, TEXT_MIMES[i]);
    } else {
        zwlr_data_control_source_v1_offer(src->source, mime);
    }
    zwlr_data_control_source_v1_offer(src->source, OWN_MIME);
    zwlr_data_control_device_v1_set_selection(cb.device, src->source);
    wl_display_flush(cb.shell->core.display);
    /* The old source is cancelled by the compositor, and freed then. */
    cb.source = src;
    if (text) {
        char *copy = malloc(len + 1);
        if (copy) {
            memcpy(copy, data, len);
            copy[len] = '\0';
            set_current("text", copy);
            free(copy);
        }
    }
    return true;
}

/* ---- setup --------------------------------------------------------------- */

bool shell_clipboard_global(struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    if (strcmp(interface, zwlr_data_control_manager_v1_interface.name) != 0 || cb.manager) return false;
    cb.manager = wl_registry_bind(registry, name, &zwlr_data_control_manager_v1_interface,
        version < 2 ? version : 2);
    return true;
}

void shell_clipboard_init(struct shell *shell) {
    cb.shell = shell;
    wl_list_init(&cb.sendings);
    cb.ready = true;
    const char *off = getenv("SHADY_SHELL_NO_CLIPBOARD");
    if (off && *off && strcmp(off, "0") != 0) return;
    if (!cb.manager || !shell->core.seat) return;
    cb.device = zwlr_data_control_manager_v1_get_data_device(cb.manager, shell->core.seat);
    zwlr_data_control_device_v1_add_listener(cb.device, &device_listener, NULL);
}

void shell_clipboard_note_image(const char *path) {
    set_current("image", path);
}

void shell_clipboard_finish(void) {
    if (!cb.ready) return;
    reading_stop();
    struct sending *s, *tmp;
    wl_list_for_each_safe(s, tmp, &cb.sendings, link) sending_free(s);
    source_free(cb.source);
    cb.source = NULL;
    offer_free(cb.selection);
    cb.selection = NULL;
    if (cb.device) zwlr_data_control_device_v1_destroy(cb.device);
    cb.device = NULL;
    if (cb.manager) zwlr_data_control_manager_v1_destroy(cb.manager);
    cb.manager = NULL;
    set_current(NULL, NULL);
    cb.ready = false;
}
