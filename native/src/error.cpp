#include "error.hpp"

namespace sogen::dart {
namespace {
thread_local std::string error_message{};
}

sogen_dart_status fail(const sogen_dart_status status, std::string message) {
  error_message = std::move(message);
  return status;
}

void clear_error() { error_message.clear(); }

const std::string &last_error() { return error_message; }
} // namespace sogen::dart
