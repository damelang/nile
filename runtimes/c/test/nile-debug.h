#ifndef NILE_DEBUG_H
#define NILE_DEBUG_H

#ifdef DEBUG

#include <stdlib.h>
#include <stdio.h>

#ifdef _MSC_VER
#define __func__ __FUNCTION__
#endif

#define log(s, ...) \
do { \
    fprintf (stderr, "(%20s:%40s:%4d) -- " s "\n", \
             __FILE__, __func__, __LINE__, ##__VA_ARGS__); \
    fflush (stderr); \
} while (0)

#define die(s, ...) \
do { \
    log (s " [EXITING]", ##__VA_ARGS__); exit (0); \
} while (0)

#define plog(p, s, ...) \
    log ("(process: %p) -- " s, p, ##__VA_ARGS__)

#define tlog(t, s, ...) \
    log ("(t->id: %2d) -- " s, t->id, ##__VA_ARGS__)

#else
#define log(...)
#define die(...) exit (0)
#define plog(...)
#define tlog(...)
#endif

#endif
