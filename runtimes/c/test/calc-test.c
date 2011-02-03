#include <stdlib.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#define DEBUG
#include "nile-debug.h"
#include "nile-print.h"

#define MEM_SIZE 1000000
#define NITERS         2
#define NREALS       700
#define NROUNDS        1
#define NPIPES    500000

nile_Buffer_t *
Calculate_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    int i;
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        float result = nile_Real_tof (nile_Buffer_pop_head (in));
        for (i = 0; i < NITERS; i++)
            result = 1 / result;
        if (nile_Buffer_tailroom (out) < 1)
            out = nile_Process_append_output (p, out);
        nile_Buffer_push_tail (out, nile_Real (result));
    }
    return out;
}

nile_Process_t * Calculate (nile_Process_t *p)
    { return nile_Process (p, 1, 0, 0, Calculate_body, 0); }

void
go (nile_Process_t *init, float *data)
{
    int i;
    nile_Process_t *p = nile_Process_pipe (
        nile_Funnel (init, 1),
        Calculate (init),
        Calculate (init),
        Calculate (init),
        Calculate (init),
        Calculate (init),
//      nile_PrintToFile (init, stdout),
        NILE_NULL);
    for (i = 0; i < NROUNDS; i++)
        nile_Funnel_pour (p, data, NREALS, i + 1 == NROUNDS);
}

int
main (int argc, char **argv)
{
    int i;
    nile_Process_t *init;
    int nthreads;
    char *mem = malloc (MEM_SIZE);
    float *data = malloc (NREALS * sizeof (float));

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

    srand (17837643);
    for (i = 0; i < NREALS; i++)
        data[i] = rand () / (float) RAND_MAX * 1000;

    /*
    printf ("\nBEGIN INPUT:\n");
    for (i = 0; i < NREALS; i++)
        printf ("%.2f ", data[i]);
    printf ("\nEND INPUT:\n");
    */

    //printf ("BEGIN OUTPUT\n");
    for (i = 0; i < NPIPES; i++)
        go (init, data);
    if (nile_sync (init))
        log ("Sync gave error");
    //printf ("\nEND OUTPUT\n");

    if (nile_shutdown (init) != mem) {
        log ("Didn't get memory back");
        exit (0);
    }

    free (mem);
    free (data);
    log ("Success");
    exit (0);
}
