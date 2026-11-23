#include "kv/version.hpp"

#include <string_view>

namespace kv {

namespace {
constexpr std::string_view kVersion = "0.1.0";
}  // namespace

std::string_view version() noexcept { return kVersion; }

}  // namespace kv
