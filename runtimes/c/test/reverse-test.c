#include <stdlib.h>
#include <stdio.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#define DEBUG
#include "nile-debug.h"
#include "nile-print.h"

#define MEM_SIZE  1000000
#define NELEMENTS    5000
#define QUANTUM         2
#define NREALS    (NELEMENTS * QUANTUM)

int
main (int argc, char **argv)
{
    int i;
    float *data = malloc (NREALS * sizeof (float));
    nile_Process_t *pipeline;
    nile_Process_t *init = nile_startup (malloc (MEM_SIZE), MEM_SIZE, 1);

    if (!init)
        die ("Failed to start up");

    for (i = 0; i < NREALS; i++)
        data[i] = i;

    pipeline = nile_Process_pipe (
        nile_Reverse (init, QUANTUM),
        nile_PrintToFile (init, QUANTUM, stdout), 
        NILE_NULL);
    nile_Process_feed (pipeline, data, NREALS);
    nile_sync (init);

    if (nile_error (init))
        die ("nile_error");

    free (nile_shutdown (init));
    log ("Success");
    exit (0);
}
