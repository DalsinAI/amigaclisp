/* AmigaCLISP: the few POSIX calls CLISP needs that libnix doesn't have.
   Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP. */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <proto/dos.h>

/* AmigaOS delivers no asynchronous Unix signals, so there is no mask to keep. */
int sigprocmask (int how, const sigset_t *set, sigset_t *oset)
{
  (void)how; (void)set;
  if (oset != NULL)
    sigemptyset(oset);
  return 0;
}

/* No fork/exec on AmigaOS: CLISP's pipe streams report the error. */
int execl (const char *path, const char *arg, ...)
{
  (void)path; (void)arg;
  errno = ENOSYS;
  return -1;
}

/* SYS::TERMINAL-RAW: switch the console to raw (1) or cooked (0) mode, as
   SetMode() does for a CON: window. Returns 0, or -1 when input is no console. */
int amiga_console_mode (int raw)
{
  BPTR in = Input();
  if (in == 0 || !IsInteractive(in))
    return -1;
  return SetMode(in, raw ? 1 : 0) ? 0 : -1;
}

/* abort() says only "Program aborted": say where from first. The address
   minus main's, plus main's address in lisp.map (the build's nm), is the caller. */
extern int main ();
void __real_abort (void) __attribute__((noreturn));
void __wrap_abort (void)
{
  fprintf(stderr, "[amiga abort] called from %p, main at %p\n",
          __builtin_return_address(0), (void *)main);
  fflush(stderr);
  __real_abort();
}

/* fcntl(F_GETFL) fails in libnix for the standard handles, and CLISP takes
   that as "no stdin/stdout" (nohup): every standard stream comes out empty
   and nothing is printed. When it fails there, give the direction the handle
   has: 0 reads, 1 and 2 write. */
int __real_fcntl (int fd, int cmd, ...);
int __wrap_fcntl (int fd, int cmd, ...)
{
  va_list ap;
  va_start(ap, cmd);
  long arg = va_arg(ap, long);
  va_end(ap);
  int r = __real_fcntl(fd, cmd, arg);
  if (r < 0 && cmd == F_GETFL && fd >= 0 && fd <= 2) {
    BPTR h = fd == 0 ? Input() : fd == 1 ? Output() : (BPTR)0;
    if (fd == 2 || h != 0) {
      errno = 0;
      return fd == 0 ? O_RDONLY : O_WRONLY;
    }
  }
  return r;
}

/* LISTEN on a standard handle (patch 0011): 1 when a key is waiting at the
   console, 0 when none is, -1 when it is no console (CLISP's own test runs). */
int amiga_listen (int fd)
{
  BPTR h = fd == 0 ? Input() : 0;
  if (h == 0 || !IsInteractive(h))
    return -1;
  return WaitForChar(h, 0) ? 1 : 0;
}
