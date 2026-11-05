/* intparam.h for m68k-amigaos (OpenAmigaGCC 16, 68040). Written for AmigaCLISP:
   CLISP's cross configure can't work out the unsigned type sizes with this compiler.
   Values checked with the compiler (sizeof and _Alignof of each type). */
/* Integers of type char have 8 bits. */
#define char_bitsize 8

/* Integers of type short have 16 bits. */
#define short_bitsize 16

/* Integers of type int have 32 bits. */
#define int_bitsize 32

/* Integers of type long have 32 bits. */
#define long_bitsize 32

/* Integers of type long long have 64 bits. */
#define long_long_bitsize 64

/* Pointers of type char * have 32 bits. */
#define pointer_bitsize 32

/* Type char has sizeof = 1 and alignment = 1. */
#define sizeof_char 1
#define alignment_char 1

/* Type short has sizeof = 2 and alignment = 2. */
#define sizeof_short 2
#define alignment_short 2

/* Type int has sizeof = 4 and alignment = 2. */
#define sizeof_int 4
#define alignment_int 2

/* Type long has sizeof = 4 and alignment = 2. */
#define sizeof_long 4
#define alignment_long 2

/* Type long long has sizeof = 8 and alignment = 2. */
#define sizeof_long_long 8
#define alignment_long_long 2

/* Type float has sizeof = 4 and alignment = 2. */
#define sizeof_float 4
#define alignment_float 2

/* Type double has sizeof = 8 and alignment = 2. */
#define sizeof_double 8
#define alignment_double 2

/* Type long double has sizeof = 12 and alignment = 2. */
#define sizeof_long_double 12
#define alignment_long_double 2

/* Types unsigned short, int, long, long long are stored BIG-ENDIAN in memory. */
#define short_big_endian
#define int_big_endian
#define long_big_endian
#define long_long_big_endian

/* Stack grows down. */
#define stack_grows_down
