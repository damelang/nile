#include <stdlib.h>
#include <stdio.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#define DEBUG
#include "nile-debug.h"
#include "nile-print.h"

#define MEM_SIZE 1000000
#define NREALS 10000

void
go (nile_Process_t *init, float *data)
{
    nile_Process_t *p = nile_Process_pipe (
        nile_Funnel (init, 2),
        nile_SortBy (init, 2, 1),
        nile_PrintToFile (init, stdout), 
        NILE_NULL);
    nile_Funnel_pour (p, data, NREALS, 1);
}

int
main (int argc, char **argv)
{
    nile_Process_t *init;
    char *mem = malloc (MEM_SIZE);
    float *data = malloc (NREALS * sizeof (float));
    int i, nthreads;

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

    srand (83897234);
    for (i = 0; i < NREALS; i++)
        data[i] = rand () / (float) RAND_MAX * 1000;
    printf ("\n");
    go (init, data);
    
    if (nile_sync (init)) {
        log ("sync gave error");
        exit (0);
    }
    printf ("\n");

    if (nile_shutdown (init) != mem) {
        log ("Didn't get memory back");
        exit (0);
    }

    free (mem);
    log ("Success");
    exit (0);
}
