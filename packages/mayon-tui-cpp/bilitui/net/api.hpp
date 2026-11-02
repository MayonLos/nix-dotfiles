// Bilibili API client: fixed hosts, an explicit write allow-list and a shared risk-control cooldown.
#pragma once
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "core/model.hpp"
#include "core/wbi.hpp"
#include "net/http.hpp"

namespace bili {
class Api {
public:
    explicit Api(const std::string& cookie);
    bool logged_in() const;
    std::string cookie() const;
    std::optional<std::string> user_id() const;
    void initialize(const CancelFlag& cancel = {});
    Json get(const std::string& path, const Params& params, const CancelFlag& cancel = {});
    Json signed_get(const std::string& path, const Params& params, const CancelFlag& cancel = {});
    Json post(const std::string& path, const Params& params, const CancelFlag& cancel = {});
    std::vector<std::string> suggest(const std::string& query, const CancelFlag& cancel = {});
    std::pair<std::string, std::string> qr_generate(const CancelFlag& cancel = {});
    // Returns the state code, plus the complete session cookie once login succeeds.
    std::pair<int64_t, std::optional<std::string>> qr_poll(const std::string& key, const CancelFlag& cancel = {});

private:
    Json request(bool post, const std::string& host, const std::string& path, const Params& params, const std::string& csrf, bool use_cookie,
                 const CancelFlag& cancel, std::vector<std::string>* set_cookies = nullptr);
    mutable std::mutex mutex_;
    std::string cookie_;
    std::optional<std::pair<std::string, std::string>> wbi_;
};
// Parsing and validation boundaries, public for tests.
std::string clean_cookie(const std::string& cookie);
std::optional<std::string> cookie_value(const std::string& cookie, const std::string& name);
void set_cookie(std::string& cookie, const std::string& name, const std::string& value);
Json unwrap_api(const Json& value);
bool write_path_allowed(const std::string& path);
bool qr_url_allowed(const std::string& url);
std::string safe_api_message(const std::string& text);
std::pair<int64_t, std::optional<std::string>> parse_qr_poll(const std::string& previous, const Json& value,
                                                             const std::vector<std::string>& set_cookies);
}  // namespace bili
