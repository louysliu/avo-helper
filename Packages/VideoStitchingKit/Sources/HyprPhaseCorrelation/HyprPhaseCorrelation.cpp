#include "HyprPhaseCorrelation.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <cmath>

int hypr_phase_correlate(const uint8_t *previous, const uint8_t *current,
                         int width, int height, double *dx, double *dy, double *response) {
    if (!previous || !current || !dx || !dy || !response || width < 2 || height < 2) return -1;
    try {
        cv::Mat a8(height, width, CV_8UC1, const_cast<uint8_t *>(previous));
        cv::Mat b8(height, width, CV_8UC1, const_cast<uint8_t *>(current));
        cv::Mat a, b, window;
        a8.convertTo(a, CV_32F);
        b8.convertTo(b, CV_32F);
        cv::createHanningWindow(window, cv::Size(width, height), CV_32F);
        double confidence = 0;
        const cv::Point2d shift = cv::phaseCorrelate(a, b, window, &confidence);
        if (!std::isfinite(shift.x) || !std::isfinite(shift.y) || !std::isfinite(confidence)) return -2;
        *dx = shift.x;
        *dy = -shift.y; // Positive means upward content motion / downward scrolling.
        *response = confidence;
        return 0;
    } catch (...) {
        return -3;
    }
}
