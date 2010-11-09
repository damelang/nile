#ifndef NILE_H
#define NILE_H

/* EXTERNAL API */

typedef struct nile_Process_ nile_Process_t;
typedef struct nile_Buffer_ nile_Buffer_t;
typedef struct nile_ nile_t;

nile_t *
nile_new (int nthreads, char *mem, int memsize);

char *
nile_free (nile_t *nl);

void
nile_feed (nile_Process_t *p, float *data, int quantum, int n, int eos);

void
nile_sync (nile_t *nl);

nile_Process_t *
nile_Pipeline (nile_t *nl, ...);

nile_Process_t *
nile_Capture (nile_t *nl, float *sink, int size, int *n);

/* INTERNAL API */

#if defined( _MSC_VER)
typedef unsigned __int32 uint32_t;
#else
#include <stdint.h>
#endif

/* Real numbers */

#include <math.h>
typedef struct { float f; } nile_Real_t;
#define real nile_Real_t

static inline real  nile_Real     (float f)        { real r = {f}; return r;        }
static inline int   nile_Real_nz  (real a)         { return  a.f != 0;              }
static inline int   nile_Real_toi (real a)         { return (int) a.f;              }
static inline float nile_Real_tof (real a)         { return       a.f;              }
static inline real  nile_Real_neg (real a)         { return nile_Real (-a.f);       }
static inline real  nile_Real_sqr (real a)         { return nile_Real (sqrtf(a.f)); }
static inline real  nile_Real_add (real a, real b) { return nile_Real (a.f +  b.f); }
static inline real  nile_Real_sub (real a, real b) { return nile_Real (a.f -  b.f); }
static inline real  nile_Real_mul (real a, real b) { return nile_Real (a.f *  b.f); }
static inline real  nile_Real_div (real a, real b) { return nile_Real (a.f /  b.f); }
static inline real  nile_Real_eq  (real a, real b) { return nile_Real (a.f == b.f); }
static inline real  nile_Real_neq (real a, real b) { return nile_Real (a.f != b.f); }
static inline real  nile_Real_lt  (real a, real b) { return nile_Real (a.f <  b.f); }
static inline real  nile_Real_gt  (real a, real b) { return nile_Real (a.f >  b.f); }
static inline real  nile_Real_leq (real a, real b) { return nile_Real (a.f <= b.f); }
static inline real  nile_Real_geq (real a, real b) { return nile_Real (a.f >= b.f); }
static inline real  nile_Real_or  (real a, real b) { return nile_Real (a.f || b.f); }
static inline real  nile_Real_and (real a, real b) { return nile_Real (a.f && b.f); }
static inline real  nile_Real_flr (real a)         { real b = nile_Real ((int)a.f);
                                                     return nile_Real
                                                       (b.f > a.f ? b.f - 1 : b.f); }
static inline real  nile_Real_clg (real a)         { real b = nile_Real ((int)a.f);
                                                     return nile_Real
                                                       (b.f < a.f ? b.f + 1 : b.f); }

/* Process */

#define NILE_INPUT_CONSUMED 0
#define NILE_INPUT_FORWARD  1
#define NILE_INPUT_SUSPEND  2
#define NILE_INPUT_EOS      3

#define NILE_INBOX_LIMIT   10

typedef int (*nile_Process_work_t)
    (nile_Process_t *p, nile_Buffer_t **in, nile_Buffer_t **out);

struct nile_Process_ {
    nile_t *nl;
    nile_Process_t *next;
    nile_Process_work_t work;
    nile_Process_t *downstream;
    uint32_t lock;
    nile_Buffer_t *inbox;
    int inbox_n;
    int initialized;
    int active;
};

nile_Process_t *
nile_Process_new (nile_t *nl, nile_Process_work_t work);

void
nile_Process_free (nile_Process_t *p);

void
nile_Process_inbox_append (nile_Process_t *p, nile_Buffer_t *b);

void
nile_Process_inbox_prepend (nile_Process_t *p, nile_Buffer_t *b);

/* Stream buffers */

#define NILE_BUFFER_SIZE 128

struct nile_Buffer_ {
    nile_t *nl;
    nile_Buffer_t *next;
    int i;
    int n;
    int eos;
    real data[NILE_BUFFER_SIZE];
};

nile_Buffer_t *
nile_Buffer_new (nile_t *nl);

void
nile_Buffer_free (nile_Buffer_t *b);

nile_Buffer_t *
nile_Buffer_clone (nile_Buffer_t *b);

static inline nile_Buffer_t *
nile_Buffer_prepare_to_append (nile_Buffer_t *b, int quantum, nile_Process_t *p)
{
    if (b->n > NILE_BUFFER_SIZE - quantum) {
        nile_Process_inbox_append (p->downstream, b);
        b = nile_Buffer_new (p->nl);
    }
    return b;
}

static inline void
nile_Buffer_append (nile_Buffer_t *b, real v)
{ b->data[b->n++] = v; }

static inline nile_Buffer_t *
nile_Buffer_prepare_to_prepend (nile_Buffer_t *b, int quantum, nile_Process_t *p)
{
    b->i -= quantum;
    if (b->i < 0) {
        b->i += quantum;
        nile_Process_inbox_prepend (p, b);
        b = nile_Buffer_new (p->nl);
        b->n = NILE_BUFFER_SIZE;
        b->i = NILE_BUFFER_SIZE - quantum;
    }
    return b;
}

static inline void
nile_Buffer_prepend (nile_Buffer_t *b, real v)
{ b->data[b->i++] = v; }

static inline real
nile_Buffer_shift (nile_Buffer_t *b)
{ return b->data[b->i++]; }

/* Primitive Processs */

nile_Process_t *
nile_Mix (nile_t *nl, nile_Process_t *p1, nile_Process_t *p2);

nile_Process_t *
nile_Interleave (nile_t *nl, nile_Process_t *p1, int quantum1,
                             nile_Process_t *p2, int quantum2);

nile_Process_t *
nile_SortBy (nile_t *nl, int index, int quantum);

#undef real

#endif
