// Make QEMU's io_uring setup report "unavailable" so it falls back to ppoll/epoll.
#include <errno.h>
struct io_uring;
int io_uring_queue_init(unsigned entries, struct io_uring *ring, unsigned flags) { return -ENOSYS; }
