// Kept apart: <asm/termbits.h> declares its own struct termios and cannot meet <termios.h>.
#include <asm/termbits.h>
#include <sys/ioctl.h>

#include <cstdint>

namespace serial {
// termios2 is the kernel's interface for any integer rate, so custom bauds need no special case.
bool set_baud(int fd, uint32_t baud) {
    struct termios2 options {};
    if (::ioctl(fd, TCGETS2, &options) != 0) return false;
    options.c_cflag &= ~static_cast<tcflag_t>(CBAUD);
    options.c_cflag |= BOTHER;
    options.c_ispeed = baud;
    options.c_ospeed = baud;
    return ::ioctl(fd, TCSETS2, &options) == 0;
}
}  // namespace serial
