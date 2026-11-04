// Adapted from ekibun/Stitch app/src/main/jni/stitch.cpp, commit
// 07c61d250824cddcaa84af38042334efe2ad0070. LGPL-2.1; see Ports/Ekibun/LICENSE.
// Replaces JNI/AndroidBitmap with borrowed RGBA buffers and a checked C ABI.
// The phase-correlation operations below retain the upstream algorithm.
#include "EkibunNative.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <cmath>
#include <cstdio>
#include <exception>

static void setError(char *output, size_t capacity, const char *message) {
    if (output && capacity) std::snprintf(output, capacity, "%s", message);
}

extern "C" const char *ekibun_opencv_version(void) { return CV_VERSION; }

extern "C" int32_t ekibun_phase_correlate(
    const uint8_t *previous, const uint8_t *next, int32_t width, int32_t height,
    int32_t use_diff, EkibunPhaseResult *result, char *error, size_t error_capacity) {
    if (result) *result = {};
    setError(error, error_capacity, "");
    if (!previous || !next || !result || width <= 0 || height <= 0 ||
        static_cast<int64_t>(width) * height > 60000000) {
        setError(error, error_capacity, "Invalid RGBA buffers or dimensions");
        return 0;
    }
    try {
        // Unlike AndroidBitmap's copyTo, these views borrow the caller's pixels.
        // All OpenCV outputs go into separate matrices; input bytes are immutable.
        const cv::Mat mat0(height, width, CV_8UC4, const_cast<uint8_t *>(previous));
        const cv::Mat mat1(height, width, CV_8UC4, const_cast<uint8_t *>(next));
        cv::Mat kernel = (cv::Mat_<char>(3, 3) << 1, 1, 1, 1, -8, 1, 1, 1, 1);
        cv::Mat grayL64F, grayR64F;
        if (use_diff) {
            cv::Mat grad0, grad1, diff;
            cv::filter2D(mat0, grad0, CV_8U, kernel);
            cv::filter2D(mat1, grad1, CV_8U, kernel);
            cv::absdiff(grad0, grad1, diff);
            cv::bitwise_and(grad0, diff, grad0);
            cv::bitwise_and(grad1, diff, grad1);
            cv::cvtColor(grad0, grad0, cv::COLOR_RGBA2GRAY);
            cv::cvtColor(grad1, grad1, cv::COLOR_RGBA2GRAY);
            grad0.convertTo(grayL64F, CV_64F);
            grad1.convertTo(grayR64F, CV_64F);
        } else {
            cv::Mat gray0, gray1;
            cv::cvtColor(mat0, gray0, cv::COLOR_RGBA2GRAY);
            cv::cvtColor(mat1, gray1, cv::COLOR_RGBA2GRAY);
            gray0.convertTo(grayL64F, CV_64F);
            gray1.convertTo(grayR64F, CV_64F);
        }
        // response is additional diagnostic output; it does not change the shift.
        double response = 0;
        auto p = cv::phaseCorrelate(grayR64F, grayL64F, cv::noArray(), &response);
        if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(response)) {
            setError(error, error_capacity, "Non-finite phase correlation");
            return 0;
        }
        *result = {p.x, p.y, response, cv::getOptimalDFTSize(width), cv::getOptimalDFTSize(height)};
        return 1;
    } catch (const cv::Exception &e) {
        setError(error, error_capacity, e.what());
    } catch (const std::exception &e) {
        setError(error, error_capacity, e.what());
    } catch (...) {
        setError(error, error_capacity, "Unknown native failure");
    }
    return 0;
}
