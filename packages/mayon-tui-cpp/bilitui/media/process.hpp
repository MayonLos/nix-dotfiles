// Child processes without shell parsing: stdio to /dev/null and default signal state.
#pragma once
#include <sys/types.h>

#include <string>
#include <vector>

namespace bili {
pid_t spawn_process(const std::vector<std::string>& argv);
// Returns true once the child has been reaped; `success` reports a zero exit status.
bool try_reap(pid_t pid, bool* success);
void stop_process(pid_t pid);
}  // namespace bili
