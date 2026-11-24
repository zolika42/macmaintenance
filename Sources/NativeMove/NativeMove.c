#include "NativeMove.h"
#include <errno.h>
#ifdef __APPLE__
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Open each path component without following symlinks. Retain the final parent
// descriptor so the rename does not resolve mutable ancestor strings again.
static int parent_fd(const char *path, char **storage, char **leaf) {
    if (!path || path[0] != '/' || !path[1]) { errno = EINVAL; return -1; }
    *storage = strdup(path + 1);
    if (!*storage) return -1;
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return -1;
    char *cursor = *storage, *component;
    while ((component = strsep(&cursor, "/")) != NULL) {
        if (!*component || !strcmp(component, ".") || !strcmp(component, "..")) {
            close(fd); errno = EINVAL; return -1;
        }
        if (!cursor) { *leaf = component; return fd; }
        int next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int error = errno;
        close(fd);
        if (next < 0) { errno = error; return -1; }
        fd = next;
    }
    close(fd); errno = EINVAL; return -1;
}

int mm_exclusive_move(const char *source, const char *destination, uint64_t device, uint64_t inode) {
    char *src_storage = NULL, *dst_storage = NULL, *src = NULL, *dst = NULL;
    int sfd = -1, dfd = -1, result = 0;
    struct stat st, parent, moved;
    sfd = parent_fd(source, &src_storage, &src);
    if (sfd < 0) { result = errno; goto done; }
    dfd = parent_fd(destination, &dst_storage, &dst);
    if (dfd < 0) { result = errno; goto done; }
    if (fstatat(sfd, src, &st, AT_SYMLINK_NOFOLLOW) != 0) { result = errno; goto done; }
    if ((!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode)) ||
        (uint64_t)st.st_dev != device || (uint64_t)st.st_ino != inode) {
        result = ESTALE; goto done;
    }
    if (fstat(dfd, &parent) != 0) { result = errno; goto done; }
    if (st.st_dev != parent.st_dev) { result = EXDEV; goto done; }
    // Exclusive at the kernel boundary, including directory and dangling-link collisions.
    // This is NOT a conditional inode-compare-and-rename syscall. A writable source
    // parent still requires a separate trust policy before this can be used as root.
    if (renameatx_np(sfd, src, dfd, dst, RENAME_EXCL) != 0) { result = errno; goto done; }
    if (fstatat(dfd, dst, &moved, AT_SYMLINK_NOFOLLOW) != 0 ||
        moved.st_dev != st.st_dev || moved.st_ino != st.st_ino) {
        result = ESTALE; goto done;
    }
done:
    if (sfd >= 0) close(sfd);
    if (dfd >= 0) close(dfd);
    free(src_storage); free(dst_storage);
    return result;
}
#else
int mm_exclusive_move(const char *source, const char *destination, uint64_t device, uint64_t inode) {
    (void)source; (void)destination; (void)device; (void)inode; return ENOTSUP;
}
#endif
