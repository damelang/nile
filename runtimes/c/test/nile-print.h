#ifndef NILE_PRINT_H
#define NILE_PRINT_H
#include <stdio.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"

typedef struct {
    int   quantum;
    FILE *f;
} nile_PrintToFile_vars_t;

static nile_Buffer_t *
nile_PrintToFile_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    nile_PrintToFile_vars_t v = *(nile_PrintToFile_vars_t *) nile_Process_vars (p);
    while (!nile_Buffer_is_empty (in)) {
        int q = v.quantum;
        while (q-- && !nile_Buffer_is_empty (in))
            fprintf (v.f, "%.4f ", nile_Real_tof (nile_Buffer_pop_head (in)));
        fprintf (v.f, "\n");
    }
    return out;
}

static nile_Buffer_t *
nile_PrintToFile_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_PrintToFile_vars_t v = *(nile_PrintToFile_vars_t *) nile_Process_vars (p);
    fflush (v.f);
    return out;
}

static nile_Process_t *
nile_PrintToFile (nile_Process_t *p, int quantum, FILE *f)
{
    p = nile_Process (p, quantum, 0, 0, nile_PrintToFile_body, nile_PrintToFile_epilogue);
    if (p) {
        nile_PrintToFile_vars_t *vars = nile_Process_vars (p);
        vars->quantum = quantum;
        vars->f = f;
    }
    return p;
}

#endif
