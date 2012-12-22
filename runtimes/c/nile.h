#ifndef NILE_H
#define NILE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nile_Process_ nile_Process_t;

/* Runtime management */

nile_Process_t *
nile_startup (char *memory, int nbytes, int nthreads);

char *
nile_shutdown (nile_Process_t *init);

void
nile_sync (nile_Process_t *init);

typedef enum {
    NILE_STATUS_OK,
    NILE_STATUS_OUT_OF_MEMORY,
    NILE_STATUS_BAD_ARG,
    NILE_STATUS_SHUTTING_DOWN
} nile_Status_t;

nile_Status_t
nile_status (nile_Process_t *init);

void
nile_print_leaks (nile_Process_t *init);

/* Connecting and launching process pipelines */

nile_Process_t *
nile_Process_pipe (nile_Process_t *p1, nile_Process_t *p2);

void
nile_Process_gate (nile_Process_t *gater, nile_Process_t *gatee);

nile_Process_t *
nile_Process_pipeline (nile_Process_t **ps, int n);

void
nile_Process_launch (nile_Process_t **ps, int nps, float *data, int ndata);

/* Built-in processes */

nile_Process_t *
nile_PassThrough (nile_Process_t *parent, int quantum);

nile_Process_t *
nile_Capture (nile_Process_t *parent, float *data, int *n, int size);

nile_Process_t *
nile_Reverse (nile_Process_t *parent, int in_quantum);

nile_Process_t *
nile_SortBy (nile_Process_t *parent, int in_quantum, float index);

nile_Process_t *
nile_DupZip (nile_Process_t *parent, int in_quantum,
             nile_Process_t *p1, nile_Process_t *p2);

nile_Process_t *
nile_DupCat (nile_Process_t *parent, int in_quantum,
             nile_Process_t *p1, nile_Process_t *p2);

nile_Process_t *
nile_Funnel (nile_Process_t *parent);

void
nile_Funnel_pour (nile_Process_t *p, float *data, int n, int EOS);

#ifdef NILE_INCLUDE_PROCESS_API

/* Process definition API */

typedef int (*nile_Process_work_function_t)
    (nile_Process_t *p, float *in, int i, int m, float *out, int j, int n);

nile_Process_t *
nile_Process (nile_Process_t *parent, int in_quantum, int out_quantum,
              nile_Process_work_function_t prologue,
              nile_Process_work_function_t body,
              nile_Process_work_function_t epilogue);

void *
nile_Process_memory (nile_Process_t *p);

void
nile_Process_advance_output (nile_Process_t *p, float **out, int *j, int *n);

int
nile_Process_advance_input (nile_Process_t *p, float **in, int *i, int *m);

void
nile_Process_prefix_input (nile_Process_t *p, float **in, int *i, int *m);

int
nile_Process_return (nile_Process_t *p, int i, int j, int status);

int
nile_Process_reroute (nile_Process_t *p, int i, int j, nile_Process_t *sub);

#endif
#ifdef __cplusplus
}
#endif
#endif
