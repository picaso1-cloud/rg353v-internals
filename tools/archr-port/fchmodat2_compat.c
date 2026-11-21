/* fchmodat2_compat — LD_PRELOAD shim for kernels without the fchmodat2
 * syscall (added in Linux 6.6).
 *
 * Two layers are broken on the 5.10 BSP kernel:
 *   - coreutils >= 9.5 issues the fchmodat2 syscall inline (no PLT);
 *   - glibc >= 2.39 routes fchmodat() through fchmodat2 WITHOUT a usable
 *     ENOSYS fallback on this build, so even old binaries fail with
 *     "Function not implemented".
 *
 * This shim therefore replaces both symbols:
 *   fchmodat2()  -> real syscall, on ENOSYS fall back to the fchmodat(2)
 *                   syscall (or an /proc/fd emulation for exotic flags)
 *   fchmodat()   -> raw fchmodat syscall (bypasses glibc's broken wrapper)
 * Install via /etc/ld.so.preload.
 *
 * Build: aarch64-linux-gnu-gcc -shared -fPIC -O2 -o fchmodat2_compat.so fchmodat2_compat.c
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x100
#endif
#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

/* aarch64 syscall numbers (x86_64 shares them for these) */
#define NR_FCHMODAT  53
#define NR_FCHMODAT2 452

static int fchmodat_fallback(int dirfd, const char *pathname, mode_t mode,
                             int flags)
{
    if (flags & AT_EMPTY_PATH) {
        char buf[64];
        snprintf(buf, sizeof(buf), "/proc/self/fd/%d", dirfd);
        int fd = open(buf, O_RDONLY);
        if (fd < 0) {
            errno = EBADF;
            return -1;
        }
        int rc = fchmod(fd, mode);
        int saved = errno;
        close(fd);
        errno = saved;
        return rc;
    }

    if (flags & AT_SYMLINK_NOFOLLOW) {
        /* kernel fchmodat cannot not-follow symlinks; go via O_PATH fd */
        int fd = open(pathname, O_PATH | O_NOFOLLOW);
        if (fd < 0)
            return -1;
        char buf[64];
        snprintf(buf, sizeof(buf), "/proc/self/fd/%d", fd);
        int rc = chmod(buf, mode);
        int saved = errno;
        close(fd);
        errno = saved;
        return rc;
    }

    return (int)syscall(NR_FCHMODAT, dirfd, pathname, mode);
}

/* glibc's fchmodat() is broken here: replace it outright with the raw
 * syscall. flags are forwarded for callers that pass them. */
int fchmodat(int dirfd, const char *pathname, mode_t mode, int flags)
{
    if (flags == 0)
        return (int)syscall(NR_FCHMODAT, dirfd, pathname, mode);
    return fchmodat_fallback(dirfd, pathname, mode, flags);
}

int fchmodat2(int dirfd, const char *pathname, mode_t mode, int flags)
{
    long r = syscall(NR_FCHMODAT2, dirfd, pathname, mode, flags);
    if (r == 0)
        return 0;
    if (errno != ENOSYS)
        return (int)r;
    return fchmodat_fallback(dirfd, pathname, mode, flags);
}
