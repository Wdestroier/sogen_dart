#pragma once

#include <string>

#include <sogen_dart.h>

namespace sogen::dart {
sogen_dart_status fail(sogen_dart_status status, std::string message);
void clear_error();
const std::string &last_error();
} // namespace sogen::dart
