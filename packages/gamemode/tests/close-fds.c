#define _GNU_SOURCE
#include <unistd.h>

/* Like steam-runtime lsof, close inherited library sockets before exit. The
 * libgamemodeauto destructor must report a disconnected bus, never abort. */
int main(void)
{
    return close_range(3, ~0U, 0) == 0 ? 0 : 1;
}
