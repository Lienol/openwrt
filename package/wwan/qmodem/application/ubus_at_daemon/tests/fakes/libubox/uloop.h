#ifndef TEST_FAKE_ULOOP_H
#define TEST_FAKE_ULOOP_H

#include <stddef.h>

#define ULOOP_READ 1U
#define container_of(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))

struct uloop_fd {
    int fd;
    void (*cb)(struct uloop_fd *fd, unsigned int events);
    int registered;
};

static inline int uloop_fd_add(struct uloop_fd *fd, unsigned int flags)
{
    (void)flags;
    fd->registered = 1;
    return 0;
}

static inline int uloop_fd_delete(struct uloop_fd *fd)
{
    fd->registered = 0;
    return 0;
}

#endif
