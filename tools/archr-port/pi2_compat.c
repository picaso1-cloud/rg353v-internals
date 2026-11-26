/* pi2_compat.c - keep glibc off the PI2 futex protocol.
 *
 * The problem
 * -----------
 * glibc >= 2.34 answers pthread_mutexattr_setprotocol(PTHREAD_PRIO_INHERIT)
 * with the *PI2* futex protocol (FUTEX_LOCK_PI2, op 0x8d | FUTEX_PRIVATE_FLAG
 * | FUTEX_CLOCK_REALTIME). That syscall only exists from Linux 5.14; the
 * 5.10 BSP kernel of the RG353V answers ENOSYS, and glibc's futex wrapper
 * treats any unexpected errno as fatal:
 *
 *   "The futex facility returned an unexpected error code."
 *   -> abort() -> "Aborted (core dumped)"
 *
 * libpulse's threaded mainloop (pa_threaded_mainloop) creates its lock with
 * PTHREAD_PRIO_INHERIT, so *every* pulse client dies on this kernel:
 * the launcher (SDL2 pulse backend), archr-levels (the volume daemon) and
 * anything else that talks to PipeWire's pulse server.
 *
 * The fix
 * -------
 * Answer the request with "no priority inheritance" instead. The mutex is
 * then an ordinary one and glibc uses the plain FUTEX_WAIT, which every
 * kernel has. Priority inheritance is not needed for the pulse mainloop
 * lock: it is a short critical section, never held across a blocking
 * operation.
 *
 * Nothing here is forwarded to the real function on purpose: the attribute
 * is left at the default (PTHREAD_PRIO_NONE) that pthread_mutexattr_init
 * set, which is exactly what we want. That also keeps this shim free of
 * any libc dependency, so it can be built without a sysroot.
 *
 * Build:
 *   clang --target=aarch64-linux-gnu -fPIC -shared -nostdlib -O2 \
 *         -o pi2_compat.so pi2_compat.c
 * Install: /usr/lib/pi2_compat.so + a line in /etc/ld.so.preload
 * SPDX-License-Identifier: MIT
 */

#define PTHREAD_PRIO_NONE	0
#define PTHREAD_PRIO_INHERIT	1
#define PTHREAD_PRIO_PROTECT	2

/* The attribute type is opaque here: the pointer is only passed through
 * (not at all, in fact). pthread_mutexattr_t is small and aligned, but the
 * caller owns it, so its size never matters to us. */
typedef struct { long __opaque[8]; } pa_mutexattr_t;

int
pthread_mutexattr_setprotocol (pa_mutexattr_t *attr, int protocol)
{
  (void) attr;
  (void) protocol;
  /* Leave the attribute as pthread_mutexattr_init() made it:
   * PTHREAD_PRIO_NONE. Return 0 (success) so the caller carries on. */
  return 0;
}
