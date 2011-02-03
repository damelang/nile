#include <stdlib.h>
#include <stdio.h>
#include "nile.h"
#define DEBUG
#include "nile-debug.h"

#define MEM_SIZE 100000

int
main (int argc, char **argv)
{
    nile_Process_t *init;
    char *mem = malloc (MEM_SIZE);
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

    init = nile_startup (mem, MEM_SIZE, nthreads);
    if (!init) {
        log ("Failed to start up");
        exit (0);
    }
    
    if (nile_sync (init)) {
        log ("sync gave error");
        exit (0);
    }

    if (nile_shutdown (init) != mem) {
        log ("Didn't get memory back");
        exit (0);
    }

    free (mem);
    log ("Success");
    exit (0);
}
