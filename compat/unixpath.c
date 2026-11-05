/* AmigaCLISP: a Unix view of AmigaDOS paths for CLISP.
   Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP.

   CLISP's pathname code is written for Unix: absolute paths start with '/'.
   The linker wraps the libnix file calls (-Wl,--wrap=open, ...) so that CLISP
   sees "/Volume/dir/file" while AmigaDOS gets "Volume:dir/file":

     /Vol/a/b    -> Vol:a/b        /Vol      -> Vol:
     a/../b      -> a//b           ../x      -> /x       ./x -> x
     Vol:a/b     -> Vol:a/b        (already AmigaDOS: left as it is)

   Paths coming back (getcwd, realpath) go the other way: "Vol:a/b" -> "/Vol/a/b".
   "/" itself is the list of volumes: it stats as a directory and nothing else. */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>
#include <dos/dosextens.h>
#include <proto/exec.h>
#include <proto/dos.h>

#define AMIGA_PATH_MAX 1024

static int trace = -1;                          /* CLISP_TRACE set: log each path */

/* A Unix path can name a volume that isn't there ("/lisp" is the volume
   lisp:): fail with ENOENT instead of putting up "Please insert volume". */
__attribute__((constructor)) static void unixpath_init (void)
{
  struct Process *me = (struct Process *)FindTask(NULL);
  me->pr_WindowPtr = (APTR)-1;
}

/* Unix-view path -> AmigaDOS path in out. Returns 0, or -1 (ENAMETOOLONG). */
static int to_amiga (const char *in, char *out, size_t size)
{
  size_t n = 0;
  int need_sep = 0;
  const char *p = in;
  if (strchr(in, ':') != NULL) {               /* already AmigaDOS */
    if (strlen(in) >= size) goto toolong;
    strcpy(out, in);
    return 0;
  }
  if (*p == '/') {                              /* absolute: first component is the volume */
    while (*p == '/') p++;
    const char *e = strchr(p, '/');
    size_t len = e ? (size_t)(e - p) : strlen(p);
    if (len + 2 > size) goto toolong;
    memcpy(out, p, len); n = len;
    out[n++] = ':';                             /* the rest is relative to its root */
    p += len;
  }
  while (*p) {
    const char *e = strchr(p, '/');
    size_t len = e ? (size_t)(e - p) : strlen(p);
    if (len == 0) { p++; continue; }            /* "//" in a Unix path is "/" */
    if (len == 1 && p[0] == '.') {              /* "." : drop */
    } else if (len == 2 && p[0] == '.' && p[1] == '.') {
      /* "..": in AmigaDOS a '/' with nothing before it is the parent */
      if (n + 2 >= size) goto toolong;
      if (need_sep) out[n++] = '/';
      out[n++] = '/';
      need_sep = 0;
    } else {
      if (n + len + 1 >= size) goto toolong;
      if (need_sep) out[n++] = '/';
      memcpy(out + n, p, len); n += len;
      need_sep = 1;
    }
    p += len;
  }
  out[n] = 0;
  if (trace < 0) trace = getenv("CLISP_TRACE") != NULL;
  if (trace) fprintf(stderr, "[amiga path] %s -> %s\n", in, out);
  return 0;
toolong:
  errno = ENAMETOOLONG;
  return -1;
}

/* AmigaDOS absolute path "Vol:a/b" -> "/Vol/a/b" in place (buf has size bytes). */
static int to_unix (char *buf, size_t size)
{
  char *colon = strchr(buf, ':');
  size_t len = strlen(buf);
  if (colon == NULL) return 0;                  /* relative: nothing to do */
  if (len + 2 > size) { errno = ENAMETOOLONG; return -1; }
  memmove(buf + 1, buf, len + 1);
  buf[0] = '/';
  colon++;                                      /* moved by one */
  if (colon[1] == 0) { *colon = 0; return 0; }  /* "Vol:" -> "/Vol" */
  *colon = '/';
  return 0;
}

static int is_root (const char *path)
{
  if (*path != '/') return 0;
  while (*path == '/' || (*path == '.' && (path[1] == 0 || path[1] == '/'))) path++;
  return *path == 0;
}

static void root_stat (struct stat *st)
{
  memset(st, 0, sizeof *st);
  st->st_mode = S_IFDIR | 0555;
  st->st_nlink = 1;
}

/* the real libnix calls */
int __real_open (const char *path, int flags, ...);
int __real_stat (const char *path, struct stat *st);
int __real_lstat (const char *path, struct stat *st);
int __real_access (const char *path, int mode);
DIR *__real_opendir (const char *path);
int __real_chdir (const char *path);
char *__real_getcwd (char *buf, size_t size);
int __real_mkdir (const char *path, mode_t mode);
int __real_rmdir (const char *path);
int __real_unlink (const char *path);
int __real_rename (const char *from, const char *to);

#define CONVERT(var, path)                                  \
  char var[AMIGA_PATH_MAX];                                 \
  if (to_amiga((path), var, sizeof var) < 0) return -1

int __wrap_open (const char *path, int flags, ...)
{
  int mode = 0;
  if (flags & O_CREAT) {
    va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap);
  }
  CONVERT(a, path);
  return __real_open(a, flags, mode);
}

int __wrap_stat (const char *path, struct stat *st)
{
  if (is_root(path)) { root_stat(st); return 0; }
  CONVERT(a, path);
  return __real_stat(a, st);
}

/* AmigaDOS soft links are rare and libnix resolves them in stat: lstat is stat. */
int __wrap_lstat (const char *path, struct stat *st)
{
  if (is_root(path)) { root_stat(st); return 0; }
  CONVERT(a, path);
  return __real_stat(a, st);
}

int __wrap_access (const char *path, int mode)
{
  if (is_root(path)) return (mode & W_OK) ? (errno = EACCES, -1) : 0;
  CONVERT(a, path);
  return __real_access(a, mode);
}

DIR *__wrap_opendir (const char *path)
{
  char a[AMIGA_PATH_MAX];
  if (is_root(path)) { errno = ENOENT; return NULL; }  /* volume listing: not yet */
  if (to_amiga(path, a, sizeof a) < 0) return NULL;
  return __real_opendir(a);
}

int __wrap_chdir (const char *path)
{
  CONVERT(a, path);
  return __real_chdir(a);
}

char *__wrap_getcwd (char *buf, size_t size)
{
  char *r = __real_getcwd(buf, size);
  if (r != NULL && to_unix(r, size) < 0) return NULL;
  return r;
}

int __wrap_mkdir (const char *path, mode_t mode)
{
  CONVERT(a, path);
  return __real_mkdir(a, mode);
}

int __wrap_rmdir (const char *path)
{
  CONVERT(a, path);
  return __real_rmdir(a);
}

int __wrap_unlink (const char *path)
{
  CONVERT(a, path);
  return __real_unlink(a);
}

int __wrap_rename (const char *from, const char *to)
{
  CONVERT(a, from);
  CONVERT(b, to);
  return __real_rename(a, b);
}

/* No symbolic links to read: every path is a plain file or directory. */
ssize_t __wrap_readlink (const char *path, char *buf, size_t size)
{
  struct stat st;
  (void)buf; (void)size;
  if (__wrap_lstat(path, &st) < 0) return -1;
  errno = EINVAL;
  return -1;
}

/* realpath: the canonical name AmigaDOS gives the object (assigns and links
   resolved), in the Unix view. resolved must hold PATH_MAX bytes. */
char *__wrap_realpath (const char *path, char *resolved)
{
  char a[AMIGA_PATH_MAX];
  char *out = resolved;
  if (is_root(path)) {
    if (out == NULL && (out = malloc(2)) == NULL) { errno = ENOMEM; return NULL; }
    strcpy(out, "/");
    return out;
  }
  if (to_amiga(path, a, sizeof a) < 0) return NULL;
  BPTR lock = Lock((STRPTR)a, SHARED_LOCK);
  if (lock == 0) {
    errno = (IoErr() == ERROR_OBJECT_NOT_FOUND || IoErr() == ERROR_DIR_NOT_FOUND
             || IoErr() == ERROR_DEVICE_NOT_MOUNTED) ? ENOENT : EACCES;
    if (resolved != NULL) {                     /* POSIX: leave the part that failed */
      strncpy(resolved, path, AMIGA_PATH_MAX - 1); resolved[AMIGA_PATH_MAX - 1] = 0;
    }
    return NULL;
  }
  if (out == NULL && (out = malloc(AMIGA_PATH_MAX)) == NULL) {
    UnLock(lock); errno = ENOMEM; return NULL;
  }
  LONG ok = NameFromLock(lock, (STRPTR)out, AMIGA_PATH_MAX - 2);
  UnLock(lock);
  if (!ok) { if (out != resolved) free(out); errno = ENAMETOOLONG; return NULL; }
  to_unix(out, AMIGA_PATH_MAX);
  return out;
}
