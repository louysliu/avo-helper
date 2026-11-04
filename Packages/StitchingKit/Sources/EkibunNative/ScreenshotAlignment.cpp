// Avo Helper's validation policy around the upstream Ekibun phase correlator.
// Separate from stitch.cpp so upstream behavior can be tested independently.
#include "EkibunNative.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>
#include <exception>
#include <cstdio>

namespace {
double overlapError(const uint8_t *a, const uint8_t *b, int w, int h, int dx, int dy) {
    const int left = std::max(0, -dx), right = std::min(w, w - dx);
    const int top = std::max(0, -dy), bottom = std::min(h, h - dy);
    if (right - left < std::max(8, w / 4) || bottom - top < std::max(8, h / 20))
        return std::numeric_limits<double>::infinity();
    const int sx = std::max(1, (right - left) / 96), sy = std::max(1, (bottom - top) / 192);
    double error = 0;
    int count = 0;
    for (int y = top; y < bottom; y += sy) {
        for (int x = left; x < right; x += sx) {
            const size_t ia = (static_cast<size_t>(y + dy) * w + x + dx) * 4;
            const size_t ib = (static_cast<size_t>(y) * w + x) * 4;
            for (int c = 0; c < 3; ++c) error += std::abs(int(a[ia + c]) - int(b[ib + c]));
            count += 3;
        }
    }
    return error / std::max(1, count);
}
}

extern "C" int32_t ekibun_align_screenshots(
    const uint8_t *previous, const uint8_t *next, int32_t w, int32_t h,
    int32_t maximumAnalysisSide,
    EkibunAlignment *result, char *error, size_t error_capacity) {
    if (error && error_capacity) error[0] = '\0';
    if (!result) return 0;
    *result = {};
    if (!previous || !next || w <= 0 || h <= 0 || static_cast<int64_t>(w) * h > 60000000) return 0;
    if (maximumAnalysisSide != 0 && maximumAnalysisSide < 64) return 0;
    try {
        if (std::memcmp(previous, next, static_cast<size_t>(w) * h * 4) == 0) {
            result->status = 2; result->confidence = 1;
            return 1;
        }
        // Input preparation is host policy, not a rewrite of the upstream core.
        // 0 selects full resolution. Otherwise retain the old app's integer-grid
        // analysis budget, then verify/refine using the untouched source pixels.
        const int scale = maximumAnalysisSide == 0 ? 1 : std::max(1, 1 + (std::max(w, h) - 1) / maximumAnalysisSide);
        const int aw = (w + scale - 1) / scale, ah = (h + scale - 1) / scale;
        std::vector<uint8_t> sampledA, sampledB;
        const uint8_t *analysisA = previous, *analysisB = next;
        if (scale > 1) {
            sampledA.resize(static_cast<size_t>(aw) * ah * 4);
            sampledB.resize(sampledA.size());
            for (int y = 0; y < ah; ++y) for (int x = 0; x < aw; ++x) {
                const size_t src = (static_cast<size_t>(y * scale) * w + x * scale) * 4;
                const size_t dst = (static_cast<size_t>(y) * aw + x) * 4;
                std::memcpy(sampledA.data() + dst, previous + src, 4);
                std::memcpy(sampledB.data() + dst, next + src, 4);
            }
            analysisA = sampledA.data(); analysisB = sampledB.data();
        }
        result->analysis_scale = scale;
        if (!ekibun_phase_correlate(analysisA, analysisB, aw, ah, 1, &result->phase, error, error_capacity)) return 0;
        const auto phase = result->phase;
        if (phase.response < 0.025 || std::abs(phase.x) > phase.period_x || std::abs(phase.y) > phase.period_y) return 1;
        const int rawX = static_cast<int>(std::lround(phase.x * scale)), rawY = static_cast<int>(std::lround(phase.y * scale));
        double bestError = std::numeric_limits<double>::infinity();
        int bestX = 0, bestY = 0;
        for (int wrapY = -1; wrapY <= 1; ++wrapY) {
            for (int wrapX = -1; wrapX <= 1; ++wrapX) {
                const int centerY = rawY + wrapY * phase.period_y * scale;
                const int centerX = rawX + wrapX * phase.period_x * scale;
                if (std::abs(centerY) >= h || std::abs(centerX) >= w) continue;
                for (int dy = centerY - scale; dy <= centerY + scale; ++dy) {
                    for (int dx = centerX - scale; dx <= centerX + scale; ++dx) {
                        const double e = overlapError(previous, next, w, h, dx, dy);
                        if (e < bestError) { bestError = e; bestX = dx; bestY = dy; }
                    }
                }
            }
        }
        result->rgb_error = bestError;
        if (!std::isfinite(bestError) || bestError >= 32 || (bestX == 0 && bestY == 0)) return 1;
        result->status = 1; result->x = bestX; result->y = bestY;
        result->confidence = std::clamp(phase.response, 0.0, 1.0) * std::max(0.0, 1 - bestError / 64);
        return 1;
    } catch (const std::exception &e) {
        *result = {};
        if (error && error_capacity) std::snprintf(error, error_capacity, "%s", e.what());
    } catch (...) {
        *result = {};
        if (error && error_capacity) std::snprintf(error, error_capacity, "Unknown native validation failure");
    }
    return 0;
}
