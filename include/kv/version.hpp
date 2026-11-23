#ifndef KV_VERSION_HPP
#define KV_VERSION_HPP

#include <string_view>

namespace kv {

// Returns the server's version string, for example "0.1.0".
[[nodiscard]] std::string_view version() noexcept;

}  // namespace kv

#endif  // KV_VERSION_HPP
