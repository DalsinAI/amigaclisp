/* AmigaCLISP: with CLISP_TRACE set, exit() says where from and with what code.
   Linked into lisp only (-Wl,--wrap=exit is added to the Makefile after
   configure, whose test programs must not see it).
   Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP. */
#include <stdio.h>
#include <stdlib.h>

extern int main ();
void __real_exit (int code) __attribute__((noreturn));
void __wrap_exit (int code)
{
  if (getenv("CLISP_TRACE") != NULL) {
    fprintf(stderr, "[amiga exit] exit(%d) called from %p, main at %p\n",
            code, __builtin_return_address(0), (void *)main);
    fflush(stderr);
  }
  __real_exit(code);
}
