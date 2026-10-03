#pragma once

#include <optional>
#include <vector>

#include "ink.h"

namespace ink_engine {

// A held pen stroke is replaced by geometry only when its full path fits a
// bounded primitive. The caller keeps the original samples beside the result.
std::optional<std::vector<InkPenSample>> RecognizeHeldStroke(
    const std::vector<InkPenSample> &samples, double view_scale);

// A compact back-and-forth stroke is an erase gesture when it crosses ink.
bool IsEraseScribble(const std::vector<InkPenSample> &samples, double view_scale);

}  // namespace ink_engine
