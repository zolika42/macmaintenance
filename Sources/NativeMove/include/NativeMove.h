#ifndef MM_NATIVE_MOVE_H
#define MM_NATIVE_MOVE_H
#include <stdint.h>
// Returns zero on success or a POSIX error. ESTALE after rename means inspect both paths.
int mm_exclusive_move(const char *source, const char *destination, uint64_t device, uint64_t inode);
#endif
