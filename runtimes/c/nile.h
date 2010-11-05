#ifndef NILE_H
#define NILE_H

/* EXTERNAL API */

typedef float nile_Real_t;
typedef struct nile_Kernel_ nile_Kernel_t;
typedef struct nile_Buffer_ nile_Buffer_t;
typedef struct nile_ nile_t;

nile_t *
nile_new (int nthreads, char *mem, int memsize);

char *
nile_free (nile_t *nl);

void
nile_feed (nile_t *nl, nile_Kernel_t *k, nile_Real_t *data,
           int quantum, int n, int eos);

void
nile_sync (nile_t *nl);

nile_Kernel_t *
nile_Pipeline (nile_t *nl, ...);

nile_Kernel_t *
nile_Pipeline_v (nile_t *nl, nile_Kernel_t **ks, int n);

nile_Kernel_t *
nile_Capture (nile_t *nl, nile_Real_t *sink, int size, int *n);

/* INTERNAL API */

#if defined( _MSC_VER)
typedef unsigned __int32 uint32_t;
#else
#include <stdint.h>
#endif

/* Real numbers */

#include <math.h>

#define real nile_Real_t

static inline real nile_Real        (float a) { return       a; }
static inline int  nile_Real_to_int (real  a) { return (int) a; }
static inline real nile_Real_flr (real a)
    { real b = (int) a; return b > a ? b - 1 : b; }
static inline real nile_Real_clg (real a)
    { real b = (int) a; return b < a ? b + 1 : b; }
static inline real nile_Real_sqr (real a) { return sqrtf (a); }
static inline real nile_Real_neg (real a) { return        -a; }
static inline real nile_Real_add (real a, real b) { return a + b; }
static inline real nile_Real_sub (real a, real b) { return a - b; }
static inline real nile_Real_mul (real a, real b) { return a * b; }
static inline real nile_Real_div (real a, real b) { return a / b; }
static inline real nile_Real_eq  (real a, real b) { return a == b; }
static inline real nile_Real_neq (real a, real b) { return a != b; }
static inline real nile_Real_lt  (real a, real b) { return a < b; }
static inline real nile_Real_gt  (real a, real b) { return a > b; }
static inline real nile_Real_leq (real a, real b) { return a <= b; }
static inline real nile_Real_geq (real a, real b) { return a >= b; }
static inline real nile_Real_or  (real a, real b) { return a || b; }
static inline real nile_Real_and (real a, real b) { return a && b; }

/* Kernels */

#define NILE_INPUT_CONSUMED 0
#define NILE_INPUT_FORWARD  1
#define NILE_INPUT_SUSPEND  2
#define NILE_INPUT_EOS      3

#define NILE_INBOX_LIMIT   10

typedef int
(*nile_Kernel_process_t) (nile_t *nl, nile_Kernel_t *k,
                          nile_Buffer_t **in, nile_Buffer_t **out);

typedef nile_Kernel_t *
(*nile_Kernel_clone_t) (nile_t *nl, nile_Kernel_t *k);

struct nile_Kernel_ {
    nile_Kernel_t *next;
    nile_Kernel_process_t process;
    nile_Kernel_clone_t clone;
    nile_Kernel_t *downstream;
    uint32_t lock;
    nile_Buffer_t *inbox;
    int inbox_n;
    int initialized;
    int active;
};

nile_Kernel_t *
nile_Kernel_new (nile_t *nl, nile_Kernel_process_t process,
                             nile_Kernel_clone_t clone);

#define NILE_KERNEL_NEW(nl, name) \
    ((name##_t *) nile_Kernel_new ((nl), name##_process, name##_clone))

void
nile_Kernel_free (nile_t *nl, nile_Kernel_t *k);

nile_Kernel_t *
nile_Kernel_clone (nile_t *nl, nile_Kernel_t *k);

void
nile_Kernel_inbox_append (nile_t *nl, nile_Kernel_t *k, nile_Buffer_t *b);

void
nile_Kernel_inbox_prepend (nile_t *nl, nile_Kernel_t *k, nile_Buffer_t *b);

/* Stream buffers */

#define NILE_BUFFER_SIZE 128

struct nile_Buffer_ {
    nile_Buffer_t *next;
    int i;
    int n;
    int eos;
    real data[NILE_BUFFER_SIZE];
};

nile_Buffer_t *
nile_Buffer_new (nile_t *nl);

void
nile_Buffer_free (nile_t *nl, nile_Buffer_t *b);

nile_Buffer_t *
nile_Buffer_clone (nile_t *nl, nile_Buffer_t *b);

static inline nile_Buffer_t *
nile_Buffer_prepare_to_append (nile_t *nl, nile_Buffer_t *b, int quantum,
                               nile_Kernel_t *k)
{
    if (b->n > NILE_BUFFER_SIZE - quantum) {
        nile_Kernel_inbox_append (nl, k->downstream, b);
        b = nile_Buffer_new (nl);
    }
    return b;
}

static inline void
nile_Buffer_append (nile_Buffer_t *b, real v)
{ b->data[b->n++] = v; }

static inline nile_Buffer_t *
nile_Buffer_append_repeat (nile_t *nl, nile_Buffer_t *b, real v,
                           int times, nile_Kernel_t *k)
{
    int room, n;
    while (times) {
        b = nile_Buffer_prepare_to_append (nl, b, 1, k);
        room = NILE_BUFFER_SIZE - b->n;
        n = times < room ? times : room;
        times -= n;
        while (n--)
            nile_Buffer_append (b, v);
    }
    return b;
}

static inline nile_Buffer_t *
nile_Buffer_prepare_to_prepend (nile_t *nl, nile_Buffer_t *b, int quantum,
                                nile_Kernel_t *k)
{
    b->i -= quantum;
    if (b->i < 0) {
        b->i += quantum;
        nile_Kernel_inbox_prepend (nl, k, b);
        b = nile_Buffer_new (nl);
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

/* Primitive kernels */

nile_Kernel_t *
nile_Mix (nile_t *nl, nile_Kernel_t *k1, nile_Kernel_t *k2);

nile_Kernel_t *
nile_Interleave (nile_t *nl, nile_Kernel_t *k1, int quantum1,
                             nile_Kernel_t *k2, int quantum2);

nile_Kernel_t *
nile_GroupBy (nile_t *nl, int index, int quantum);

nile_Kernel_t *
nile_SortBy (nile_t *nl, int index, int quantum);

#undef real

#endif
