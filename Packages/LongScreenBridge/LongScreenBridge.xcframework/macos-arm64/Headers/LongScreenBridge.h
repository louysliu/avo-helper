#ifndef LONG_SCREEN_BRIDGE_H
#define LONG_SCREEN_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
typedef struct { double time; double duration; size_t width; size_t height; } LSFrame;
typedef int32_t (*LSProgress)(void *, double, const char *);
typedef int32_t (*LSReset)(void *);
typedef int32_t (*LSNext)(void *, LSFrame *, const uint8_t **, size_t *);
char *ls_run(size_t width, size_t height, double duration, LSReset reset, LSNext next, const char *output_dir, size_t max_pixels, size_t working_bytes, LSProgress progress, void *context);
void ls_string_free(char *value);
#endif
