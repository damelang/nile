#include <stdlib.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#define DEBUG
#include "nile-debug.h"
#include "nile-print.h"

#define NBYTES_PER_THREAD    1000000
#define NITERS_PER_ELEMENT         2
#define NREALS_PER_POUR         1000
#define NPOURS_PER_PIPELINE        1
#define NSTAGES_PER_PIPELINE       7
#define NPIPELINES           1000000

static nile_Buffer_t *
Reciprocal_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    int i;
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        float result = nile_Real_tof (nile_Buffer_pop_head (in));
        for (i = 0; i < NITERS_PER_ELEMENT; i++)
            result = 1 / result;
        if (nile_Buffer_tailroom (out) < 1)
            out = nile_Process_append_output (p, out);
        nile_Buffer_push_tail (out, nile_Real (result));
    }
    return out;
}

static nile_Process_t * Reciprocal (nile_Process_t *p)
    { return nile_Process (p, 1, 0, 0, Reciprocal_body, 0); }

static void
create_and_run_pipeline (nile_Process_t *init, float *data)
{
    int i;
    //nile_Process_t *pipeline = nile_PrintToFile (init, stdout);
    nile_Process_t *pipeline = NILE_NULL;
    for (i = 0; i < NSTAGES_PER_PIPELINE; i++)
        pipeline = nile_Process_pipe (Reciprocal (init), pipeline, NILE_NULL);
    pipeline = nile_Process_pipe (nile_Funnel (init), pipeline, NILE_NULL);
    for (i = 0; i < NPOURS_PER_PIPELINE; i++)
        nile_Funnel_pour (pipeline, data, NREALS_PER_POUR, (i + 1 == NPOURS_PER_PIPELINE));
}

int
main (int argc, char **argv)
{
    int i;
    nile_Process_t *init;
    int nthreads;
    int mem_size;
    float *data = malloc (NREALS_PER_POUR * sizeof (float));

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

    mem_size = NBYTES_PER_THREAD * nthreads;
    init = nile_startup (malloc (mem_size), mem_size, nthreads);
    if (!init)
        die ("Failed to start up");

    srand (17837643);
    for (i = 0; i < NREALS_PER_POUR; i++)
        data[i] = rand () / (float) RAND_MAX * 1000;

    for (i = 0; i < NPIPELINES; i++) {
        create_and_run_pipeline (init, data);
        if (nile_error (init)) {
            log ("nile_error!");
            break;
        }
    }

    nile_sync (init);
    if (nile_error (init))
        log ("nile_error!");

    free (nile_shutdown (init));
    free (data);
    log ("Success");
    exit (0);
}
