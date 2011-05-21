#include <stdlib.h>
#include <stdio.h>
#include "nile.h"
#define DEBUG
#include "nile-debug.h"

#define NBYTES_PER_THREAD 1000

int
main (int argc, char **argv)
{
    nile_Process_t *init;
    char *mem;
    int nthreads;

    if (argc > 1) {
        nthreads = atoi (argv[1]);
        if (nthreads < 1)
            nthreads = 1;
        if (nthreads > 100)
            nthreads = 100;
    }
    else
        nthreads = 1;
    log ("nthreads: %d", nthreads);

    mem = malloc (NBYTES_PER_THREAD * nthreads);
    init = nile_startup (mem, NBYTES_PER_THREAD * nthreads, nthreads);
    if (!init) {
        log ("Failed to start up");
        exit (0);
    }
    
    nile_sync (init);

    if (nile_error (init)) {
        log ("nile_error gave error");
        exit (0);
    }

    nile_print_leaks (init);

    if (nile_shutdown (init) != mem) {
        log ("Didn't get memory back");
        exit (0);
    }

    free (mem);
    log ("Success");
    exit (0);
}
