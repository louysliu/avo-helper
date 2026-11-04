#ifndef HYPR_PHASE_CORRELATION_H
#define HYPR_PHASE_CORRELATION_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Returns 0 on success; catches OpenCV exceptions before crossing the C ABI.
int hypr_phase_correlate(const uint8_t *previous, const uint8_t *current,
                         int width, int height, double *dx, double *dy, double *response);
#ifdef __cplusplus
}
#endif
#endif
