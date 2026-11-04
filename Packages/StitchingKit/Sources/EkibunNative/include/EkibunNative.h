#ifndef AVO_EKIBUN_NATIVE_H
#define AVO_EKIBUN_NATIVE_H
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double x;
    double y;
    double response;
    int32_t period_x;
    int32_t period_y;
} EkibunPhaseResult;

/// RGBA8, top-down, tightly packed. Each buffer must contain at least
/// width * height * 4 readable bytes, borrowed for this call only.
/// Returns 1 on success, 0 on invalid input/OpenCV failure. No exception crosses C ABI.
int32_t ekibun_phase_correlate(const uint8_t *previous, const uint8_t *next,
                              int32_t width, int32_t height, int32_t use_diff,
                              EkibunPhaseResult *result,
                              char *error, size_t error_capacity);
const char *ekibun_opencv_version(void);

typedef struct {
    int32_t status; // 0 unmatched, 1 matched, 2 exact duplicate
    int32_t x;
    int32_t y;
    double confidence;
    double rgb_error;
    int32_t analysis_scale;
    EkibunPhaseResult phase;
} EkibunAlignment;

/// Host policy: duplicates, periodic-shift disambiguation, local verification.
int32_t ekibun_align_screenshots(const uint8_t *previous, const uint8_t *next,
                               int32_t width, int32_t height,
                               int32_t maximum_analysis_side,
                               EkibunAlignment *result,
                               char *error, size_t error_capacity);

#ifdef __cplusplus
}
#endif
#endif
