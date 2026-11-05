/* AmigaCLISP: the few POSIX calls CLISP needs that libnix doesn't have.
   Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP. */
#include <errno.h>
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
