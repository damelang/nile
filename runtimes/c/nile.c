#include <stdarg.h>
#include "nile.h"

#define real nile_Real_t
#define MAX_THREADS 50
#define READY_Q_TOO_LONG_LENGTH 25

/* CPU pause */

#if defined(__SSE2__) || defined(_M_IX86)
#include <xmmintrin.h>
static inline void nile_pause () { _mm_pause (); }
#else
static inline void nile_pause () { }
#endif

/* Atomic functions */

#if (defined(__GNUC__) || defined(__INTEL_COMPILER)) && defined(__linux)
static inline int nile_atomic_test_and_set (int * volatile l)
    { return __sync_lock_test_and_set (l, 1); }
static inline void nile_atomic_clear (int * volatile l)
    { __sync_lock_release (l); }
#elif defined(__MACH__) && defined(__APPLE__)
#include <libkern/OSAtomic.h>
static inline int nile_atomic_test_and_set (int * volatile l)
    { return OSAtomicTestAndSetBarrier (0, l); }
static inline void nile_atomic_clear (int * volatile l)
    { OSAtomicTestAndClearBarrier (0, l); }
#elif defined(_MSC_VER)
static inline int nile_atomic_test_and_set (int * volatile l)
    { return InterlockedExchangeAcquire (l, 1); }
static inline void nile_atomic_clear (int * volatile l)
    { InterlockedDecrementRelease (l); }
#else
#   error Unsupported platform!
#endif

/* Spin locks */

static void
nile_lock (int * volatile lock)
{
    while (*lock || nile_atomic_test_and_set (lock))
        nile_pause ();
}

static void
nile_unlock (int * volatile lock)
{
    nile_atomic_clear (lock);
}

/* Semaphores */

#if defined(__MACH__)

#include <mach/mach.h>
#include <mach/semaphore.h>
typedef semaphore_t nile_Sem_t;

static void
nile_Sem_new (nile_Sem_t *s, int value)
{
    semaphore_create (mach_task_self (), s, SYNC_POLICY_FIFO, value);
}

static void
nile_Sem_free (nile_Sem_t *s)
{
    semaphore_destroy (mach_task_self (), *s);
}

static void
nile_Sem_signal (nile_Sem_t *s)
{
    semaphore_signal (*s);
}

static void
nile_Sem_wait (nile_Sem_t *s)
{
    semaphore_wait (*s);
}

#elif defined(__linux)
#   error Need to implement nile_Sem_t for Linux!
#elif defined(_WIN32)
#   error Need to implement nile_Sem_t for Windows!
#else
#   error Unsupported platform!
#endif

/* Threads */

#if defined(__unix__) || defined(__DARWIN_UNIX03)

#include <pthread.h>
typedef pthread_t nile_Thread_t;

static void
nile_Thread_new (nile_t *nl, nile_Thread_t *t, void * (*f) (nile_t *))
{
    pthread_create (t, NULL, (void * (*) (void *) ) f, nl);
}

static void
nile_Thread_join (nile_Thread_t *t)
{
    pthread_join (*t, NULL);
}

#elif defined(_WIN32)

typedef HANDLE nile_Thread_t;

static void
nile_Thread_new (nile_t *nl, nile_Thread_t *t, void * (*f) (nile_t *))
{
    *t = CreateThread (NULL, 0, (LPTHREAD_START_ROUTINE) f, nl, 0, NULL);
}

static void
nile_Thread_join (nile_Thread_t *t)
{
    WaitForSingleObject (*t, INFINITE);
    CloseHandle (*t);
}

#else
#   error Unsupported platform!
#endif

/* Execution context */

struct nile_ {
    int nthreads;
    int nthreads_active;
    nile_Kernel_t *ready_q;
    int ready_q_length;
    int shutdown;
    nile_Buffer_t *freelist;
    int freelist_lock;
    int ready_q_lock;
    nile_Sem_t ready_q_has_kernel;
    nile_Sem_t ready_q_no_longer_too_long_sem;
    nile_Sem_t idle_sem;
    nile_Thread_t threads[MAX_THREADS];
};

/* Main thread loop */

static int
nile_Kernel_exec (nile_t *nl, nile_Kernel_t *k);

static void * 
nile_main (nile_t *nl)
{
    nile_Kernel_t *k;
    int shutdown;
    int signal_idle;
    int signal_q_no_longer_too_long;
    int active;
    int response;

    for (;;) {
        nile_lock (&nl->ready_q_lock);
            nl->nthreads_active--;
            shutdown = nl->shutdown;
            signal_idle = !nl->nthreads_active && !nl->ready_q;
        nile_unlock (&nl->ready_q_lock);

        if (shutdown)
            break;

        if (signal_idle)
           nile_Sem_signal (&nl->idle_sem);

        nile_Sem_wait (&nl->ready_q_has_kernel);

        nile_lock (&nl->ready_q_lock);
            nl->nthreads_active++;
            k = nl->ready_q;
            if (k) {
                nl->ready_q = k->next;
                nl->ready_q_length--;
            }
            signal_q_no_longer_too_long =
                nl->ready_q_length == READY_Q_TOO_LONG_LENGTH - 1;
        nile_unlock (&nl->ready_q_lock);
        
        if (k)
            k->next = NULL;
        else
            continue;

        if (signal_q_no_longer_too_long)
           nile_Sem_signal (&nl->ready_q_no_longer_too_long_sem);

        for (;;) {
            nile_lock (&k->lock);
                active = k->active = (k->inbox != NULL);
            nile_unlock (&k->lock);
            if (!active)
                break;
            response = nile_Kernel_exec (nl, k);
            if (response == NILE_INPUT_SUSPEND || response == NILE_INPUT_EOS)
                break;
        }
    }
            
    return NULL;
}

/* Context new/free */

nile_t *
nile_new (int nthreads, char *mem, int memsize)
{
    int i;
    nile_t *nl = (nile_t *) mem;
    nl->nthreads = nthreads < MAX_THREADS ? nthreads : MAX_THREADS;
    nl->nthreads_active = nl->nthreads;
    nl->ready_q = NULL;
    nl->ready_q_length = 0;
    nl->shutdown = 0;

    nl->freelist = (nile_Buffer_t *) (mem + sizeof (nile_t));
    int n = (memsize - sizeof (nile_t)) / sizeof (nile_Buffer_t);
    for (i = 0; i < n - 1; i++)
        nl->freelist[i].next = &(nl->freelist[i + 1]);
    nl->freelist[n - 1].next = NULL;

    nl->freelist_lock = 0;
    nl->ready_q_lock = 0;
    nile_Sem_new (&nl->ready_q_has_kernel, 0);
    nile_Sem_new (&nl->ready_q_no_longer_too_long_sem, 0);
    nile_Sem_new (&nl->idle_sem, 0);

    for (i = 0; i < nl->nthreads; i++)
        nile_Thread_new (nl, &(nl->threads[i]), nile_main);

    return nl;
}

char *
nile_free (nile_t *nl)
{
    int i;

    nile_lock (&nl->ready_q_lock);
        nl->shutdown = 1;
    nile_unlock (&nl->ready_q_lock);

    for (i = 0; i < nl->nthreads; i++)
        nile_Sem_signal (&nl->ready_q_has_kernel);

    for (i = 0; i < nl->nthreads; i++)
        nile_Thread_join (&(nl->threads[i]));

    nile_Sem_free (&nl->idle_sem);
    nile_Sem_free (&nl->ready_q_no_longer_too_long_sem);
    nile_Sem_free (&nl->ready_q_has_kernel);

    return (char *) nl;
}

/* External stream data */

void
nile_feed (nile_t *nl, nile_Kernel_t *k, nile_Real_t *data, int n, int eos)
{
    nile_Buffer_t *in;
    int i = 0;
    int ready_q_length;

    nile_lock (&nl->ready_q_lock);
        ready_q_length = nl->ready_q_length;
    nile_unlock (&nl->ready_q_lock);

    while (!(ready_q_length < READY_Q_TOO_LONG_LENGTH)) {
        nile_Sem_wait (&nl->ready_q_no_longer_too_long_sem);
        nile_lock (&nl->ready_q_lock);
            ready_q_length = nl->ready_q_length;
        nile_unlock (&nl->ready_q_lock);
    }

    while (n) {
        in = nile_Buffer_new (nl);
        while (i < n && in->n < NILE_BUFFER_SIZE)
            in->data[in->n++] = data[i++];
        n -= in->n;
        if (n == 0)
            in->eos = eos;
        nile_Kernel_inbox_append (nl, k, in);
    }
}

/* External synchronization (waiting until all kernels are done) */

void
nile_sync (nile_t *nl)
{
    int idle = 0;
    while (!idle) {
        nile_Sem_wait (&nl->idle_sem);
        nile_lock (&nl->ready_q_lock);
            idle = !nl->nthreads_active && !nl->ready_q;
        nile_unlock (&nl->ready_q_lock);
    }
}

/* Buffers */

nile_Buffer_t *
nile_Buffer_new (nile_t *nl)
{
    nile_Buffer_t *b;

    nile_lock (&nl->freelist_lock);
        b = nl->freelist;
        if (!b)
            abort ();
        nl->freelist = b->next;
    nile_unlock (&nl->freelist_lock);

    b->next = NULL;
    b->i = 0;
    b->n = 0;
    b->eos = 0;
    return b;
}

void
nile_Buffer_free (nile_t *nl, nile_Buffer_t *b)
{
    nile_lock (&nl->freelist_lock);
        b->next = nl->freelist;
        nl->freelist = b;
    nile_unlock (&nl->freelist_lock);
}

nile_Buffer_t *
nile_Buffer_clone (nile_t *nl, nile_Buffer_t *b)
{
    int i;
    nile_Buffer_t *clone = nile_Buffer_new (nl);
    clone->i = b->i;
    clone->n = b->n;
    clone->eos = b->eos;
    for (i = b->i; i < b->n; i++)
        clone->data[i] = b->data[i];
    return clone;
}

/* Kernels */

nile_Kernel_t *
nile_Kernel_new (nile_t *nl, nile_Kernel_process_t process,
                             nile_Kernel_clone_t clone)
{
    nile_Kernel_t *k = (nile_Kernel_t *) nile_Buffer_new (nl);
    k->next = NULL;
    k->process = process;
    k->clone = clone;
    k->downstream = NULL;
    k->lock = 0;
    k->inbox = NULL;
    k->initialized = 0;
    k->active = 0;
    return k;
}

void
nile_Kernel_free (nile_t *nl, nile_Kernel_t *k)
{
    nile_Buffer_free (nl, (nile_Buffer_t *) k);
}

nile_Kernel_t *
nile_Kernel_clone (nile_t *nl, nile_Kernel_t *k)
{
    nile_Kernel_t *clone = nile_Kernel_new (nl, k->process, k->clone);
    return clone;
}

static void
nile_Kernel_ready (nile_t *nl, nile_Kernel_t *k)
{
    nile_lock (&nl->ready_q_lock);
        if (nl->ready_q) {
            nile_Kernel_t *ready_q = nl->ready_q;
            while (ready_q->next)
                ready_q = ready_q->next;
            ready_q->next = k;
        }
        else
            nl->ready_q = k;
        nl->ready_q_length++;
    nile_unlock (&nl->ready_q_lock);

    nile_Sem_signal (&nl->ready_q_has_kernel);
}

/* Kernel inbox management */

void
nile_Kernel_inbox_append (nile_t *nl, nile_Kernel_t *k, nile_Buffer_t *b)
{
    int must_activate;

    nile_lock (&k->lock); 
        if (k->inbox) {
            nile_Buffer_t *inbox = k->inbox;
            while (inbox->next)
                inbox = inbox->next;
            inbox->next = b;
            must_activate = 0;
        }
        else {
            k->inbox = b;
            must_activate = !k->active;
        }
    nile_unlock (&k->lock); 

    if (must_activate)
        nile_Kernel_ready (nl, k);
}

void
nile_Kernel_inbox_prepend (nile_t *nl, nile_Kernel_t *k, nile_Buffer_t *b)
{
    nile_lock (&k->lock);
        b->next = k->inbox;
        k->inbox = b;
    nile_unlock (&k->lock);
}

/* Kernel execution */

static int
nile_Kernel_exec (nile_t *nl, nile_Kernel_t *k)
{
    int response = NILE_INPUT_FORWARD;
    int eos = 0;
    nile_Buffer_t *out = nile_Buffer_new (nl);
    nile_Buffer_t *in;

    for (;;) { 
        nile_lock (&k->lock);
            in = k->inbox;
            k->inbox = in ? in->next : in;
        nile_unlock (&k->lock);
        if (!in)
            break;
        in->next = NULL;
        eos = in->eos;

        response = k->process (nl, k, &in, &out);
        switch (response) {
            case NILE_INPUT_CONSUMED:
                nile_Buffer_free (nl, in);
                break;
            case NILE_INPUT_FORWARD:
                if (out && out->n) {
                    nile_Kernel_inbox_append (nl, k->downstream, out);
                    out = nile_Buffer_new (nl);
                }
                nile_Kernel_inbox_append (nl, k->downstream, in);
                break;
            case NILE_INPUT_SUSPEND:
                if (in)
                    nile_Kernel_inbox_prepend (nl, k, in);
                eos = 0;
                break;
        }
        if (response == NILE_INPUT_SUSPEND)
            break;
    }

    if (out) {
        out->eos = eos;
        if (response != NILE_INPUT_FORWARD && out->n)
            nile_Kernel_inbox_append (nl, k->downstream, out);
        else
            nile_Buffer_free (nl, out);
    }

    if (eos) {
        nile_Kernel_free (nl, k);
        response = NILE_INPUT_EOS;
    }

    return response;
}

/* Pipeline kernel */

typedef struct {
    nile_Kernel_t base;
    int n;
    nile_Kernel_t *ks[20];
} nile_Pipeline_t;

static nile_Kernel_t *
nile_Pipeline_clone (nile_t *nl, nile_Kernel_t *k_)
{
    nile_Pipeline_t *k = (nile_Pipeline_t *) k_;
    nile_Pipeline_t *clone =
        (nile_Pipeline_t *) nile_Kernel_clone (nl, k_);
    int i;

    clone->n = k->n;
    for (i = 0; i < k->n; i++)
        clone->ks[i] = k->ks[i]->clone (nl, k->ks[i]);

    return (nile_Kernel_t *) clone;
}

static int
nile_Pipeline_process (nile_t *nl, nile_Kernel_t *k_,
                       nile_Buffer_t **in, nile_Buffer_t **out)
{
    nile_Pipeline_t *k = (nile_Pipeline_t *) k_;

    if (!k_->initialized) {
        k_->initialized = 1;
        int i;
        for (i = k->n - 1; i >= 0; i--) {
            k->ks[i]->downstream = k_->downstream;
            k_->downstream = k->ks[i];
        }
    }
    return NILE_INPUT_FORWARD;
}

nile_Kernel_t *
nile_Pipeline (nile_t *nl, ...)
{
    va_list args;
    nile_Kernel_t *ki;
    nile_Pipeline_t *k = NILE_KERNEL_NEW (nl, nile_Pipeline);

    va_start (args, nl); 
    ki = va_arg (args, nile_Kernel_t *);
    for (k->n = 0; ki != NULL; k->n++) {
        k->ks[k->n] = ki;
        ki = va_arg (args, nile_Kernel_t *);
    }
    va_end (args);

    return (nile_Kernel_t *) k;
}

/* Interleave kernel */

typedef struct {
    nile_Kernel_t base;
    nile_Kernel_t *v_k1;
    int quantum1;
    nile_Kernel_t *v_k2;
    int quantum2;
} nile_Interleave_t;

static nile_Kernel_t *
nile_Interleave_clone (nile_t *nl, nile_Kernel_t *k_)
{
    nile_Interleave_t *k = (nile_Interleave_t *) k_;
    nile_Interleave_t *clone =
        (nile_Interleave_t *) nile_Kernel_clone (nl, k_);
    clone->v_k1 = k->v_k1->clone (nl, k->v_k1);
    clone->quantum1 = k->quantum1; 
    clone->v_k2 = k->v_k2->clone (nl, k->v_k2); 
    clone->quantum2 = k->quantum2; 
    return (nile_Kernel_t *) clone;
}

typedef struct {
    nile_Kernel_t base;
    int lock;
    nile_Buffer_t *out;
} nile_Interleave__shared_t;

typedef struct nile_Interleave__ nile_Interleave__t;

struct nile_Interleave__ {
    nile_Kernel_t base;
    nile_Interleave__shared_t *shared;
    int quantum;
    int j0;
    nile_Interleave__t *sibling;
    int j;
    int n;
};

static nile_Kernel_t *
nile_Interleave__clone (nile_t *nl, nile_Kernel_t *k_)
{
    /* You can't clone this type of kernel, it is created just-in-time
       during initialization of Interleave.
     */
    return NULL;
}

static int
nile_Interleave__process (nile_t *nl, nile_Kernel_t *k_,
                          nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Interleave__t *k = (nile_Interleave__t *) k_;
    int *lock = &k->shared->lock;
    nile_Buffer_t *in = *in_;
    nile_Buffer_t *out;
    int done = 0;
    int j; 

    if (!k_->initialized) {
        k_->initialized = 1;
        k->j = k->j0;
        k->n = NILE_BUFFER_SIZE - (k->quantum + k->sibling->quantum) + k->j0 + 1;
    }

    if (*out_) {
        nile_Buffer_free (nl, *out_);
        *out_ = NULL;
    }

    nile_lock (lock);
        out = k->shared->out;
        j = k->j;
    nile_unlock (lock);

    while (in->i < in->n && j != -1) {
        int i0 = in->i;
        while (in->i < in->n && j < k->n) {
            int q = k->quantum;
            while (q--)
                out->data[j++] = in->data[in->i++];
            j += k->sibling->quantum;
        }
        int flush_needed = (in->eos && !(in->i < in->n)) || !(j < k->n);

        nile_lock (lock);
            out->n += in->i - i0;
            if (flush_needed) {
                j = -1;
                if (k->sibling->j == -1) {
                    done = in->eos && !(in->i < in->n);
                    if (done)
                        out->eos = 1;
                    nile_Kernel_inbox_append (nl, k_->downstream, out);
                    if (!done) {
                        out = nile_Buffer_new (nl);
                        j = k->j0;
                        k->sibling->j = k->sibling->j0;
                        nile_Kernel_ready (nl, &k->sibling->base);
                    }
                }
            }
            k->shared->out = out;
            k->j = j;
        nile_unlock (lock);
    }

    if (done)
        nile_Kernel_free (nl, &k->shared->base);

    return (j == -1 && !done ? NILE_INPUT_SUSPEND : NILE_INPUT_CONSUMED);
}

static nile_Interleave__t *
nile_Interleave_ (nile_t *nl, nile_Interleave__shared_t *shared, int quantum, int j0)
{
    nile_Interleave__t *k = NILE_KERNEL_NEW (nl, nile_Interleave_);
    k->shared = shared;
    k->quantum = quantum;
    k->j0 = j0;
    return k;
}

static int
nile_Interleave_process (nile_t *nl, nile_Kernel_t *k_,
                         nile_Buffer_t **in, nile_Buffer_t **out)
{
    nile_Interleave_t *k = (nile_Interleave_t *) k_;

    if (!k_->initialized) {
        k_->initialized = 1;
        nile_Interleave__shared_t *shared =
            (nile_Interleave__shared_t *) nile_Kernel_new (nl, NULL, NULL);
        shared->lock = 0;
        shared->out = nile_Buffer_new (nl);
        nile_Interleave__t *child1 =
            nile_Interleave_ (nl, shared, k->quantum1, 0);
        nile_Interleave__t *child2 =
            nile_Interleave_ (nl, shared, k->quantum2, k->quantum1);
        child1->sibling = child2;
        child2->sibling = child1;
        child1->base.downstream = k_->downstream;
        child2->base.downstream = k_->downstream;
        k->v_k1->downstream = &child1->base;
        k->v_k2->downstream = &child2->base;
        k_->downstream = k->v_k2;
    }

    nile_Kernel_inbox_append (nl, k->v_k1, nile_Buffer_clone (nl, *in));
    return NILE_INPUT_FORWARD;
}

nile_Kernel_t *
nile_Interleave (nile_t *nl, nile_Kernel_t *v_k1, int quantum1,
                             nile_Kernel_t *v_k2, int quantum2)
{
    nile_Interleave_t *k = NILE_KERNEL_NEW (nl, nile_Interleave);
    k->v_k1 = v_k1;
    k->quantum1 = quantum1;
    k->v_k2 = v_k2;
    k->quantum2 = quantum2;
    return (nile_Kernel_t *) k;
}

/* GroupBy kernel */

typedef struct {
    nile_Kernel_t base;
    int index;
    int quantum;
    real key;
} nile_GroupBy_t;

static nile_Kernel_t *
nile_GroupBy_clone (nile_t *nl, nile_Kernel_t *k_)
{
    nile_GroupBy_t *k = (nile_GroupBy_t *) k_;
    nile_GroupBy_t *clone =
        (nile_GroupBy_t *) nile_Kernel_clone (nl, k_);
    clone->index = k->index;
    clone->quantum = k->quantum;
    return (nile_Kernel_t *) clone;
}

static int
nile_GroupBy_process (nile_t *nl, nile_Kernel_t *k_,
                      nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_GroupBy_t *k = (nile_GroupBy_t *) k_;
    nile_Kernel_t *clone;
    nile_Buffer_t *in = *in_;
    nile_Buffer_t *out = *out_;

    if (!k_->initialized) {
        k_->initialized = 1;
        k->key = in->data[k->index];
    }
    
    while (in->i < in->n) {
        real key = in->data[in->i + k->index];
        if (key != k->key) {
            k->key = key;
            clone = k_->downstream->clone (nl, k_->downstream);
            out->eos = 1;
            nile_Kernel_inbox_append (nl, k_->downstream, out);
            nile_Kernel_inbox_prepend (nl, k_, in);
            k_->downstream = clone;
            *out_ = NULL;
            *in_ = NULL;
            nile_Kernel_ready (nl, k_);
            return NILE_INPUT_SUSPEND;
        }
        out = nile_Buffer_prepare_to_append (nl, out, k->quantum, k_);
        int q = k->quantum;
        while (q--)
            out->data[out->n++] = in->data[in->i++];
    }

    *out_ = out;
    return NILE_INPUT_CONSUMED;
}

nile_Kernel_t *
nile_GroupBy (nile_t *nl, int index, int quantum)
{
    nile_GroupBy_t *k = NILE_KERNEL_NEW (nl, nile_GroupBy);
    k->index = index;
    k->quantum = quantum;
    return nile_Pipeline (nl, nile_SortBy (nl, index, quantum), &k->base, NULL);
}

/* SortBy kernel */

typedef struct {
    nile_Kernel_t base;
    int index;
    int quantum;
    nile_Buffer_t *out;
} nile_SortBy_t;

static nile_Kernel_t *
nile_SortBy_clone (nile_t *nl, nile_Kernel_t *k_)
{
    nile_SortBy_t *k = (nile_SortBy_t *) k_;
    nile_SortBy_t *clone =
        (nile_SortBy_t *) nile_Kernel_clone (nl, k_);
    clone->index = k->index;
    clone->quantum = k->quantum;
    return (nile_Kernel_t *) clone;
}

static int
nile_SortBy_process (nile_t *nl, nile_Kernel_t *k_,
                     nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_SortBy_t *k = (nile_SortBy_t *) k_;
    nile_Buffer_t *in = *in_;

    if (!k_->initialized) {
        k_->initialized = 1;
        k->out = *out_;
        k->out->eos = 1;
        *out_ = NULL;
    }

    if (*out_) {
        nile_Buffer_free (nl, *out_);
        *out_ = NULL;
    }

    while (in->i < in->n) {
        nile_Buffer_t *out = k->out;
        real key = in->data[in->i + k->index];

        /* find the right buffer */
        while (out->next != NULL && key > out->next->data[k->index])
            out = out->next;

        /* split the buffer if it's full */
        if (out->n > NILE_BUFFER_SIZE - k->quantum) {
            nile_Buffer_t *next = nile_Buffer_new (nl);
            next->eos = out->eos;
            next->next = out->next;
            out->eos = 0;
            out->next = next;

            int j = out->n / k->quantum / 2 * k->quantum;
            while (j < out->n)
                out->next->data[out->next->n++] = out->data[j++];
            out->n -= out->next->n;

            if (key > out->next->data[k->index])
                out = out->next;
        }

        /* insert new element */
        int j = out->n - k->quantum;
        while (j >= 0) {
            if (key >= out->data[j + k->index])
                break;
            int jj = j + k->quantum;
            int q = k->quantum;
            while (q--)
                out->data[jj++] = out->data[j++];
            j -= (k->quantum + k->quantum);
        }
        j += k->quantum;
        int q = k->quantum;
        while (q--)
            out->data[j++] = in->data[in->i++];
        out->n += k->quantum;
    }

    if (in->eos)
        nile_Kernel_inbox_append (nl, k_->downstream, k->out);

    return NILE_INPUT_CONSUMED;
}

nile_Kernel_t *
nile_SortBy (nile_t *nl, int index, int quantum)
{
    nile_SortBy_t *k = NILE_KERNEL_NEW (nl, nile_SortBy);
    k->index = index;
    k->quantum = quantum;
    return (nile_Kernel_t *) k;
}
