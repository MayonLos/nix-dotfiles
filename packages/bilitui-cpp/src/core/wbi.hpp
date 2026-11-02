// WBI request signing for Bilibili's signed read endpoints.
#pragma once
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace bili {
using Params = std::vector<std::pair<std::string, std::string>>;
std::string md5_hex(std::string_view data);
// Throws when a key is malformed. Returns the sorted parameters plus wts and w_rid.
Params wbi_sign(const Params& params, const std::string& img, const std::string& sub, uint64_t timestamp);
}  // namespace bili
