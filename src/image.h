#ifndef SHADY_SHELL_IMAGE_H
#define SHADY_SHELL_IMAGE_H

#include <cairo.h>
#include <stddef.h>

/*
 * Picture files for shell.image: PNG always, JPEG and WebP when the shell
 * was built with libjpeg and libwebp. The format is told from the file's
 * first bytes, not its name.
 */

/* Decode `path` into a premultiplied ARGB32 image surface, or NULL with
 * the reason in `error`. Pictures larger than SHELL_IMAGE_MAX_SIDE on a
 * side are reduced on the way (JPEG while decoding, so a camera photo never
 * occupies its full size in memory). */
cairo_surface_t *shell_image_load(const char *path, char *error, size_t error_size);

/* NULL-terminated names of the formats this build reads: "png", "jpeg", "webp". */
const char *const *shell_image_formats(void);

#define SHELL_IMAGE_MAX_SIDE 8192

#endif
