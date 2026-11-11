#include "image.h"

#include <errno.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if HAVE_JPEG
#include <jpeglib.h>
#endif
#if HAVE_WEBP
#include <webp/decode.h>
#endif

/* Larger files are refused before they are read. */
#define MAX_FILE_BYTES (256u << 20)

static const char *const formats[] = {
    "png",
#if HAVE_JPEG
    "jpeg",
#endif
#if HAVE_WEBP
    "webp",
#endif
    NULL,
};

const char *const *shell_image_formats(void) {
    return formats;
}

static cairo_surface_t *fail(char *error, size_t size, const char *fmt, const char *detail) {
    snprintf(error, size, fmt, detail);
    return NULL;
}

static cairo_surface_t *new_surface(int width, int height, char *error, size_t size) {
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surface);
        return fail(error, size, "%s", "out of memory");
    }
    return surface;
}

/* A picture over the size limit, drawn smaller. */
static cairo_surface_t *limit_size(cairo_surface_t *surface, char *error, size_t size) {
    int w = cairo_image_surface_get_width(surface), h = cairo_image_surface_get_height(surface);
    int side = w > h ? w : h;
    if (side <= SHELL_IMAGE_MAX_SIDE) return surface;
    double s = (double)SHELL_IMAGE_MAX_SIDE / side;
    int nw = (int)(w * s + 0.5), nh = (int)(h * s + 0.5);
    cairo_surface_t *small = new_surface(nw > 0 ? nw : 1, nh > 0 ? nh : 1, error, size);
    if (small) {
        cairo_t *cr = cairo_create(small);
        cairo_scale(cr, (double)nw / w, (double)nh / h);
        cairo_set_source_surface(cr, surface, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
        cairo_paint(cr);
        cairo_destroy(cr);
    }
    cairo_surface_destroy(surface);
    return small;
}

static cairo_surface_t *load_png(const char *path, char *error, size_t size) {
    cairo_surface_t *surface = cairo_image_surface_create_from_png(path);
    cairo_status_t status = cairo_surface_status(surface);
    if (status != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surface);
        return fail(error, size, "not a readable PNG (%s)", cairo_status_to_string(status));
    }
    /* cairo hands back RGB24 for opaque PNGs; everything else draws ARGB32. */
    if (cairo_image_surface_get_format(surface) != CAIRO_FORMAT_ARGB32) {
        int w = cairo_image_surface_get_width(surface), h = cairo_image_surface_get_height(surface);
        cairo_surface_t *argb = new_surface(w, h, error, size);
        if (argb) {
            cairo_t *cr = cairo_create(argb);
            cairo_set_source_surface(cr, surface, 0, 0);
            cairo_paint(cr);
            cairo_destroy(cr);
        }
        cairo_surface_destroy(surface);
        surface = argb;
    }
    return surface ? limit_size(surface, error, size) : NULL;
}

/* ---- JPEG --------------------------------------------------------------- */

#if HAVE_JPEG
struct jpeg_failure {
    struct jpeg_error_mgr mgr;
    jmp_buf jump;
    char message[JMSG_LENGTH_MAX];
};

static void jpeg_fail(j_common_ptr info) {
    struct jpeg_failure *failure = (struct jpeg_failure *)info->err;
    info->err->format_message(info, failure->message);
    longjmp(failure->jump, 1);
}

static void jpeg_quiet(j_common_ptr info, int level) {
    (void)info;
    (void)level; /* warnings (a truncated file still decodes) are not news */
}

static cairo_surface_t *load_jpeg(FILE *file, char *error, size_t size) {
    struct jpeg_decompress_struct info;
    struct jpeg_failure failure;
    /* volatile: assigned between setjmp and a longjmp back to it. */
    cairo_surface_t *volatile surface = NULL;
    unsigned char *volatile row = NULL;
    info.err = jpeg_std_error(&failure.mgr);
    failure.mgr.error_exit = jpeg_fail;
    failure.mgr.emit_message = jpeg_quiet;
    if (setjmp(failure.jump)) {
        jpeg_destroy_decompress(&info);
        if (surface) cairo_surface_destroy(surface);
        free(row);
        return fail(error, size, "not a readable JPEG (%s)", failure.message);
    }
    jpeg_create_decompress(&info);
    jpeg_stdio_src(&info, file);
    jpeg_read_header(&info, TRUE);
    /* Decode big photos at 1/2, 1/4 or 1/8: the cheapest way to make them small. */
    unsigned side = info.image_width > info.image_height ? info.image_width : info.image_height;
    info.scale_num = 1;
    info.scale_denom = 1;
    while (info.scale_denom < 8 && side / (info.scale_denom * 2) >= SHELL_IMAGE_MAX_SIDE)
        info.scale_denom *= 2;
#ifdef JCS_EXTENSIONS
    /* libjpeg-turbo writes cairo's byte order (B G R A on little endian) itself. */
    bool direct = true;
    info.out_color_space = (*(const uint16_t *)"\1\0" == 1) ? JCS_EXT_BGRA : JCS_EXT_ARGB;
#else
    bool direct = false;
    info.out_color_space = JCS_RGB;
#endif
    if (info.jpeg_color_space == JCS_CMYK || info.jpeg_color_space == JCS_YCCK) {
        direct = false;
        info.out_color_space = JCS_CMYK;
    }
    jpeg_start_decompress(&info);
    int w = (int)info.output_width, h = (int)info.output_height;
    surface = new_surface(w, h, error, size);
    if (!surface) {
        jpeg_destroy_decompress(&info);
        return NULL;
    }
    cairo_surface_flush(surface);
    unsigned char *data = cairo_image_surface_get_data(surface);
    int stride = cairo_image_surface_get_stride(surface);
    if (!direct) {
        row = malloc((size_t)w * (size_t)info.output_components);
        if (!row) {
            jpeg_destroy_decompress(&info);
            cairo_surface_destroy(surface);
            return fail(error, size, "%s", "out of memory");
        }
    }
    while (info.output_scanline < info.output_height) {
        uint32_t *out = (uint32_t *)(data + (size_t)info.output_scanline * (size_t)stride);
        if (direct) {
            JSAMPROW rows[1] = { (JSAMPROW)out };
            jpeg_read_scanlines(&info, rows, 1);
            continue;
        }
        JSAMPROW rows[1] = { row };
        jpeg_read_scanlines(&info, rows, 1);
        for (int x = 0; x < w; x++) {
            const unsigned char *p = row + (size_t)x * (size_t)info.output_components;
            unsigned r, g, b;
            if (info.out_color_space == JCS_CMYK) {
                /* Adobe writes inverted CMYK; that is what turns up in practice. */
                unsigned k = p[3];
                r = p[0] * k / 255;
                g = p[1] * k / 255;
                b = p[2] * k / 255;
            } else if (info.output_components == 1) {
                r = g = b = p[0];
            } else {
                r = p[0];
                g = p[1];
                b = p[2];
            }
            out[x] = 0xff000000u | (r << 16) | (g << 8) | b;
        }
    }
    jpeg_finish_decompress(&info);
    jpeg_destroy_decompress(&info);
    free(row);
    cairo_surface_mark_dirty(surface);
    return limit_size(surface, error, size);
}
#endif

/* ---- WebP --------------------------------------------------------------- */

#if HAVE_WEBP
static cairo_surface_t *load_webp(FILE *file, char *error, size_t size) {
    if (fseek(file, 0, SEEK_END) != 0) return fail(error, size, "%s", strerror(errno));
    long length = ftell(file);
    if (length <= 0 || (unsigned long)length > MAX_FILE_BYTES)
        return fail(error, size, "%s", "WebP file too large or empty");
    rewind(file);
    uint8_t *bytes = malloc((size_t)length);
    if (!bytes) return fail(error, size, "%s", "out of memory");
    if (fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        free(bytes);
        return fail(error, size, "%s", "short read");
    }
    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config) ||
            WebPGetFeatures(bytes, (size_t)length, &config.input) != VP8_STATUS_OK) {
        free(bytes);
        return fail(error, size, "%s", "not a readable WebP");
    }
    if (config.input.has_animation) {
        free(bytes);
        return fail(error, size, "%s", "animated WebP is not supported");
    }
    int w = config.input.width, h = config.input.height;
    int side = w > h ? w : h;
    if (side > SHELL_IMAGE_MAX_SIDE) {
        double s = (double)SHELL_IMAGE_MAX_SIDE / side;
        config.options.use_scaling = 1;
        config.options.scaled_width = w = (int)(w * s + 0.5) > 0 ? (int)(w * s + 0.5) : 1;
        config.options.scaled_height = h = (int)(h * s + 0.5) > 0 ? (int)(h * s + 0.5) : 1;
    }
    cairo_surface_t *surface = new_surface(w, h, error, size);
    if (!surface) {
        free(bytes);
        return NULL;
    }
    cairo_surface_flush(surface);
    /* Premultiplied, in cairo's byte order. */
    config.output.colorspace = (*(const uint16_t *)"\1\0" == 1) ? MODE_bgrA : MODE_Argb;
    config.output.is_external_memory = 1;
    config.output.u.RGBA.rgba = cairo_image_surface_get_data(surface);
    config.output.u.RGBA.stride = cairo_image_surface_get_stride(surface);
    config.output.u.RGBA.size = (size_t)config.output.u.RGBA.stride * (size_t)h;
    VP8StatusCode status = WebPDecode(bytes, (size_t)length, &config);
    WebPFreeDecBuffer(&config.output);
    free(bytes);
    if (status != VP8_STATUS_OK) {
        cairo_surface_destroy(surface);
        return fail(error, size, "%s", "not a readable WebP");
    }
    cairo_surface_mark_dirty(surface);
    return surface;
}
#endif

cairo_surface_t *shell_image_load(const char *path, char *error, size_t error_size) {
    FILE *file = fopen(path, "rb");
    if (!file) return fail(error, error_size, "%s", strerror(errno));
    unsigned char magic[12] = { 0 };
    size_t got = fread(magic, 1, sizeof(magic), file);
    rewind(file);
    cairo_surface_t *surface = NULL;
    if (got >= 8 && !memcmp(magic, "\x89PNG\r\n\x1a\n", 8)) {
        fclose(file);
        return load_png(path, error, error_size);
    } else if (got >= 3 && magic[0] == 0xff && magic[1] == 0xd8 && magic[2] == 0xff) {
#if HAVE_JPEG
        surface = load_jpeg(file, error, error_size);
#else
        fail(error, error_size, "%s", "this shell was built without JPEG support");
#endif
    } else if (got >= 12 && !memcmp(magic, "RIFF", 4) && !memcmp(magic + 8, "WEBP", 4)) {
#if HAVE_WEBP
        surface = load_webp(file, error, error_size);
#else
        fail(error, error_size, "%s", "this shell was built without WebP support");
#endif
    } else {
        fail(error, error_size, "%s", "not a picture this shell can read");
    }
    fclose(file);
    return surface;
}
