#ifndef NILE_PRINT_H
#define NILE_PRINT_H
#include <stdio.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"

nile_Buffer_t *
nile_PrintToFile_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    FILE *f = *(FILE **) nile_Process_vars (p);
    while (!nile_Buffer_is_empty (in))
        fprintf (f, "%.4f\n", nile_Real_tof (nile_Buffer_pop_head (in)));
    return out;
}

nile_Buffer_t *
nile_PrintToFile_epilogue (nile_Process_t *p, nile_Buffer_t *out)
    { fflush (*(FILE **) nile_Process_vars (p)); return out; }

nile_Process_t *
nile_PrintToFile (nile_Process_t *p, FILE *f)
{
    p = nile_Process (p, 1, 0, 0, nile_PrintToFile_body, nile_PrintToFile_epilogue);
    if (p) {
        FILE **var = nile_Process_vars (p);
        *var = f;
    }
    return p;
}

#endif
