/*
 * maxima: starts Maxima on AmigaCLISP, from the drawer it is in.
 *
 *   maxima [Maxima's options]        e.g.  maxima   or   maxima -s 4010
 *
 * The drawer holds lisp (AmigaCLISP), clisp/ (CLISP's compiled system),
 * binary-clisp/ (Maxima's compiled files), share/ (Maxima's packages) and,
 * once made, maxima.mem (Maxima's memory image). A memory image belongs to
 * the machine it was made on, so the first start makes it (makeimage.lisp)
 * and every start after that loads it.
 *
 * Maxima finds its packages through MAXIMA_PREFIX, which is set here (a
 * local variable, which the CLI that runs CLISP takes with it) to this
 * drawer in the Unix view AmigaCLISP uses: Work:wxMaxima/Maxima is
 * /Work/wxMaxima/Maxima.
 *
 * Copyright (c) 2026 AmiCradle Team. GPL-2.0-or-later, as Maxima.
 */
#include <exec/types.h>
#include <dos/dos.h>
#include <dos/dostags.h>
#include <dos/var.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static const char version[] = "$VER: maxima 0.1 (6.11.2026) AmiCradle Team";

#define LISP_STACK 2000000

static char dir[512];      /* this drawer, Amiga path (Work:wxMaxima/Maxima) */
static char udir[520];     /* the same, Unix view (/Work/wxMaxima/Maxima) */
static char line[4096];

/* Work:a/b -> /Work/a/b; RAM: -> /RAM */
static void unix_view(const char *a, char *u, size_t n)
{
    const char *colon = strchr(a, ':');
    if (!colon) { snprintf(u, n, "%s", a); return; }
    snprintf(u, n, "/%.*s%s%s", (int)(colon - a), a, colon[1] ? "/" : "", colon + 1);
}

static int exists(const char *name)
{
    BPTR l = Lock((CONST_STRPTR)name, ACCESS_READ);
    if (!l) return 0;
    UnLock(l);
    return 1;
}

/* append s to line, in quotes when it has a space or is empty */
static int add(const char *s, int quote)
{
    size_t len = strlen(line);
    int q = quote || !*s || strchr(s, ' ') != NULL;
    if (len + strlen(s) + 4 >= sizeof line) return 0;
    if (len) line[len++] = ' ';
    if (q) line[len++] = '"';
    strcpy(line + len, s);
    len += strlen(s);
    if (q) line[len++] = '"';
    line[len] = 0;
    return 1;
}

static LONG run(void)
{
    return SystemTags((CONST_STRPTR)line, NP_StackSize, LISP_STACK, TAG_DONE);
}

/* the image is made with no console: on one the boot image stops
   (AmigaCLISP's MakeImage does the same), its output goes to a log */
#define MAKEIMAGE_LOG "T:maxima-makeimage.log"
static LONG run_logged(void)
{
    BPTR in = Open((CONST_STRPTR)"NIL:", MODE_OLDFILE);
    BPTR out = Open((CONST_STRPTR)MAKEIMAGE_LOG, MODE_NEWFILE);
    LONG rc;
    if (!in || !out) {
        if (in) Close(in);
        if (out) Close(out);
        return -1;
    }
    rc = SystemTags((CONST_STRPTR)line, SYS_Input, in, SYS_Output, out,
                    NP_StackSize, LISP_STACK, TAG_DONE);
    Close(in);
    Close(out);
    return rc;
}

int main(int argc, char **argv)
{
    BPTR home = GetProgramDir();
    char path[600];
    int i;
    LONG rc;
    (void)version;

    if (!home || !NameFromLock(home, (STRPTR)dir, sizeof dir)) {
        fprintf(stderr, "maxima: cannot find its own drawer\n");
        return RETURN_FAIL;
    }
    unix_view(dir, udir, sizeof udir);
    SetVar((CONST_STRPTR)"MAXIMA_PREFIX", (CONST_STRPTR)udir, -1, GVF_LOCAL_ONLY);

    snprintf(path, sizeof path, "%s/maxima.mem", dir);
    if (!exists(path)) {
        /* first start: load CLISP and Maxima, save maxima.mem */
        fprintf(stderr, "maxima: making Maxima's memory image (first start only), please wait...\n");
        /* as AmigaCLISP's MakeImage: in CLISP's folder, its system from there */
        BPTR cl, old;
        line[0] = 0;
        snprintf(path, sizeof path, "%s/lisp", dir); add(path, 1);
        add("-B", 0); add("", 1); add("-norc", 0);
        snprintf(path, sizeof path, "%s/makeimage.lisp", dir); add(path, 1);
        snprintf(path, sizeof path, "%s/clisp", dir);
        if (!(cl = Lock((CONST_STRPTR)path, ACCESS_READ))) {
            fprintf(stderr, "maxima: no %s\n", path);
            return RETURN_FAIL;
        }
        old = CurrentDir(cl);
        rc = run_logged();
        UnLock(CurrentDir(old));
        snprintf(path, sizeof path, "%s/maxima.mem", dir);
        if (!exists(path)) {
            fprintf(stderr, "maxima: no memory image was made (return code %ld); see %s\n",
                    (long)rc, MAKEIMAGE_LOG);
            return RETURN_FAIL;
        }
        fprintf(stderr, "maxima: %s saved\n", path);
    }

    line[0] = 0;
    snprintf(path, sizeof path, "%s/lisp", dir); add(path, 1);
    add("-B", 0); snprintf(path, sizeof path, "%s/clisp", dir); add(path, 1);
    add("-M", 0); snprintf(path, sizeof path, "%s/maxima.mem", dir); add(path, 1);
    add("-E", 0); add("UTF-8", 0); add("-q", 0); add("-norc", 0);
    add("", 1); add("--", 0);
    for (i = 1; i < argc; i++)
        if (!add(argv[i], 0)) {
            fprintf(stderr, "maxima: command line too long\n");
            return RETURN_FAIL;
        }
    rc = run();
    return rc < 0 ? RETURN_FAIL : (int)rc;
}
