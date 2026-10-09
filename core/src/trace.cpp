#include "trace.h"

#include "ink.h"

namespace {
InkLogHandler gLogHandler = nullptr;
}  // namespace

void ink_engine::Trace(const std::string &message) {
  if (gLogHandler) gLogHandler(message.c_str());
}

InkStatus ink_set_log_handler(InkLogHandler handler) {
  gLogHandler = handler;
  return INK_OK;
}
