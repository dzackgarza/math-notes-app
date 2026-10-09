#pragma once

#include <string>

namespace ink_engine {

// Reports an engine decision about input to the host's log handler
// (ink_set_log_handler); without a handler it does nothing.
void Trace(const std::string &message);

}  // namespace ink_engine
