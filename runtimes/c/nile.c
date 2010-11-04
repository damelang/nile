#include <stdlib.h>
#include <stdarg.h>
#ifdef _WIN32
#include <windows.h>
#endif
#include "nile.h"

#define real nile_Real_t
#define MAX_THREADS 50
#define READY_Q_TOO_LONG_LENGTH 25

#ifndef NILE_MULTI_THREADED

#define nile_lock(l)
#define nile_unlock(l)

#else

/* CPU pause */

#if defined(__SSE2__) || defined(_M_IX86)
#include <xmmintrin.h>
static inline void nile_pause () { _mm_pause (); }
#else
static inline void nile_pause () { }
#endif

/* Atomic exchange */

#if defined(_WIN32)
#define nile_xchg InterlockedExchange
#elif defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__))
static inline uint32_t
nile_xchg (volatile uint32_t *l, uint32_t v)
{
    __asm__ __volatile__("xchgl %1,%0"
                         : "=r" (v) : "m" (*l), "0" (v) : "memory");
    return v;
}
#else
#error Unsupported platform!
#endif

/* Spin locks */

static inline void
nile_lock (volatile uint32_t *lock)
{
    while (*lock || nile_xchg (lock, 1))
        nile_pause ();
}

static inline void
nile_unlock (volatile uint32_t *lock)
{
    nile_xchg (lock, 0);
}

#endif

/* Semaphores */

#ifndef NILE_MULTI_THREADED

typedef int nile_Sem_t;
#define nile_Sem_new(s, value)
#define nile_Sem_free(s)
#define nile_Sem_signal(s)
#define nile_Sem_wait(s)

#else

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

typedef HANDLE nile_Sem_t;

static void
nile_Sem_new (nile_Sem_t *s, int value)
{
    *s = CreateSemaphore (NULL, value, MAX_THREADS, NULL);
}

static void
nile_Sem_free (nile_Sem_t *s)
{
    CloseHandle (*s);
}

static void
nile_Sem_signal (nile_Sem_t *s)
{
    ReleaseSemaphore (*s, 1, NULL);
}

static void
nile_Sem_wait (nile_Sem_t *s)
{
    WaitForSingleObject (*s, INFINITE);
}

#else
#   error Unsupported platform!
#endif

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
    uint32_t freelist_lock;
    uint32_t ready_q_lock;
    nile_Sem_t ready_q_has_kernel;
    nile_Sem_t ready_q_no_longer_too_long_sem;
    nile_Sem_t idle_sem;
    nile_Thread_t threads[MAX_THREADS];
};

/* Main thread loop */

static nile_Kernel_t * nile_NULL_KERNEL_clone (nile_t *nl, nile_Kernel_t *k_) { return k_; }
static nile_Kernel_t NULL_KERNEL = {0, 0, nile_NULL_KERNEL_clone, 0};

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
            signal_idle = !nl->nthreads_active && !nl->ready_q;
        nile_unlock (&nl->ready_q_lock);

        if (signal_idle) {
            nile_Sem_signal (&nl->idle_sem);
#ifndef NILE_MULTI_THREADED
            break;
#endif
        }

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
            shutdown = nl->shutdown;
        nile_unlock (&nl->ready_q_lock);

        if (shutdown)
            break;
        if (!k)
            continue;
        k->next = NULL;

        if (signal_q_no_longer_too_long)
           nile_Sem_signal (&nl->ready_q_no_longer_too_long_sem);

        for (;;) {
            nile_lock (&k->lock);
                active = k->active = k->inbox_n > 0;
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
#ifndef NILE_MULTI_THREADED
    nl->nthreads = 0;
#else
    nl->nthreads = nthreads < MAX_THREADS ? nthreads : MAX_THREADS;
#endif
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
nile_feed (nile_t *nl, nile_Kernel_t *k, nile_Real_t *data,
           int quantum, int n, int eos)
{
    nile_Buffer_t *in;
    int i = 0;
    int ready_q_length;
    int m = (NILE_BUFFER_SIZE / quantum) * quantum;

    nile_lock (&nl->ready_q_lock);
        ready_q_length = nl->ready_q_length;
    nile_unlock (&nl->ready_q_lock);

    while (ready_q_length >= READY_Q_TOO_LONG_LENGTH) {
        nile_Sem_wait (&nl->ready_q_no_longer_too_long_sem);
        nile_lock (&nl->ready_q_lock);
            ready_q_length = nl->ready_q_length;
        nile_unlock (&nl->ready_q_lock);
    }

    in = nile_Buffer_new (nl);
    while (i < n) {
        while (i < n && in->n < m)
            in->data[in->n++] = data[i++];
        if (i < n) {
            nile_Kernel_inbox_append (nl, k, in);
            in = nile_Buffer_new (nl);
        }
    }
    in->eos = eos;
    nile_Kernel_inbox_append (nl, k, in);

#ifndef NILE_MULTI_THREADED
    nl->nthreads_active++;
    nile_main (nl);
#endif
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
    if (b) {
        nile_Buffer_t *next = b->next;
        nile_lock (&nl->freelist_lock);
            b->next = nl->freelist;
            nl->freelist = b;
        nile_unlock (&nl->freelist_lock);
        nile_Buffer_free (nl, next);
    }
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
    k->inbox_n = 0;
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
nile_Kernel_ready_now (nile_t *nl, nile_Kernel_t *k)
{
    nile_lock (&nl->ready_q_lock);
        k->next = nl->ready_q;
        nl->ready_q = k;
        nl->ready_q_length++;
    nile_unlock (&nl->ready_q_lock);

    nile_Sem_signal (&nl->ready_q_has_kernel);
}

static void
nile_Kernel_ready_later (nile_t *nl, nile_Kernel_t *k)
{
    nile_lock (&nl->ready_q_lock);
        nile_Kernel_t *ready_q = nl->ready_q;
        if (ready_q) {
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
    int n = 1;
    int must_activate = 0;
    nile_Buffer_t *inbox, *b_;

    if (k == &NULL_KERNEL) {
        nile_Buffer_free (nl, b);
        return;
    }

    for (b_ = b; b_->next; b_ = b_->next)
        n++;

    nile_lock (&k->lock); 
        if (k->inbox_n) {
            for (inbox = k->inbox; inbox->next; inbox = inbox->next)
                ;
            inbox->next = b;
        }
        else {
            k->inbox = b;
            must_activate = !k->active;
        }
        k->inbox_n += n;
    nile_unlock (&k->lock); 

    if (must_activate)
        nile_Kernel_ready_now (nl, k);
}

void
nile_Kernel_inbox_prepend (nile_t *nl, nile_Kernel_t *k, nile_Buffer_t *b)
{
    nile_lock (&k->lock);
        b->next = k->inbox;
        k->inbox = b;
        k->inbox_n++;
    nile_unlock (&k->lock);
}

/* Kernel execution */

static int
nile_Kernel_exec (nile_t *nl, nile_Kernel_t *k)
{
    nile_Buffer_t *in, *out;
    int eos = 0;
    int response = NILE_INPUT_FORWARD;

    if (k->downstream && k->downstream->inbox_n >= NILE_INBOX_LIMIT) {
        nile_Kernel_ready_later (nl, k);
        return NILE_INPUT_SUSPEND;
    }

    out = nile_Buffer_new (nl);
    while (k->inbox_n) {
        nile_lock (&k->lock);
            k->inbox_n--;
            in = k->inbox;
            k->inbox = in->next;
        nile_unlock (&k->lock);
        in->next = NULL;

        response = k->process (nl, k, &in, &out);
        eos = in ? in->eos : 0;
        if (response == NILE_INPUT_CONSUMED && in->i < in->n)
            response = NILE_INPUT_SUSPEND;
        switch (response) {
            case NILE_INPUT_CONSUMED:
                nile_Buffer_free (nl, in);
                break;
            case NILE_INPUT_FORWARD:
                if (out && out->n) {
                    nile_Kernel_inbox_append (nl, k->downstream, out);
                    out = NULL;
                }
                nile_Kernel_inbox_append (nl, k->downstream, in);
                if (!eos && k->downstream->inbox_n >= NILE_INBOX_LIMIT)
                    response = NILE_INPUT_SUSPEND;
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
        if (response == NILE_INPUT_CONSUMED || response == NILE_INPUT_SUSPEND)
            nile_Kernel_inbox_append (nl, k->downstream, out);
        else
            nile_Buffer_free (nl, out);
    }

    if (response == NILE_INPUT_SUSPEND && k->downstream->inbox_n >= NILE_INBOX_LIMIT)
        nile_Kernel_ready_later (nl, k);

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

    for (clone->n = 0; clone->n < k->n; clone->n++)
        clone->ks[clone->n] = k->ks[clone->n]->clone (nl, k->ks[clone->n]);

    return (nile_Kernel_t *) clone;
}

static int
nile_Pipeline_process (nile_t *nl, nile_Kernel_t *k_,
                       nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Pipeline_t *k = (nile_Pipeline_t *) k_;
    int i;

    if (!k_->initialized) {
        k_->initialized = 1;
        k_->downstream = k_->downstream ? k_->downstream : &NULL_KERNEL;
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

nile_Kernel_t *
nile_Pipeline_v (nile_t *nl, nile_Kernel_t **ks, int n)
{
    nile_Pipeline_t *k = NILE_KERNEL_NEW (nl, nile_Pipeline);
    for (k->n = 0; k->n < n; k->n++)
        k->ks[k->n] = ks[k->n];

    return (nile_Kernel_t *) k;
}

/* Capture kernel */

typedef struct {
    nile_Kernel_t base;
    nile_Real_t *sink;
    int size;
    int *n;
} nile_Capture_t;

static nile_Kernel_t *
nile_Capture_clone (nile_t *nl, nile_Kernel_t *k_)
{
    nile_Capture_t *k = (nile_Capture_t *) k_;
    nile_Capture_t *clone =
        (nile_Capture_t *) nile_Kernel_clone (nl, k_);
    clone->sink = k->sink;
    clone->size = k->size;
    clone->n    = k->n;
    return (nile_Kernel_t *) clone;
}

static int
nile_Capture_process (nile_t *nl, nile_Kernel_t *k_,
                      nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Capture_t *k = (nile_Capture_t *) k_;
    nile_Buffer_t *in = *in_;

    while (in->i < in->n) {
        nile_Real_t r = nile_Buffer_shift (in);
        if (*k->n < k->size)
            k->sink[*k->n] = r;
        (*k->n)++;
    }

    return NILE_INPUT_CONSUMED;
}

nile_Kernel_t *
nile_Capture (nile_t *nl, nile_Real_t *sink, int size, int *n)
{
    nile_Capture_t *k = NILE_KERNEL_NEW (nl, nile_Capture);
    k->sink = sink;
    k->size = size;
    k->n    = n;
    return (nile_Kernel_t *) k;
}

/* Mix kernel */

typedef struct {
    nile_Kernel_t base;
    nile_Kernel_t *v_k1;
    nile_Kernel_t *v_k2;
} nile_Mix_t;

static nile_Kernel_t *
nile_Mix_clone (nile_t *nl, nile_Kernel_t *k_)
{
    nile_Mix_t *k = (nile_Mix_t *) k_;
    nile_Mix_t *clone = (nile_Mix_t *) nile_Kernel_clone (nl, k_);
    clone->v_k1 = k->v_k1->clone (nl, k->v_k1);
    clone->v_k2 = k->v_k2->clone (nl, k->v_k2);
    return (nile_Kernel_t *) clone;
}

typedef struct {
    nile_Kernel_t base;
    int eos_seen;
} nile_MixChild_t;

static int
nile_MixChild_process (nile_t *nl, nile_Kernel_t *k_,
                       nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_MixChild_t *k = (nile_MixChild_t *) k_;
    nile_Buffer_t *in = *in_;

    k_->initialized = 1;
    if (*out_) {
        nile_Buffer_free (nl, *out_);
        *out_ = NULL;
    }

    if (in->eos && !k->eos_seen) {
        k->eos_seen = 1;
        in->eos = 0;
    }

    return NILE_INPUT_FORWARD;
}

static nile_MixChild_t *
nile_MixChild (nile_t *nl)
{
    nile_MixChild_t *k = (nile_MixChild_t *)
        nile_Kernel_new (nl, nile_MixChild_process, NULL);
    k->eos_seen = 0;
    return k;
}

static int
nile_Mix_process (nile_t *nl, nile_Kernel_t *k_,
                  nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Mix_t *k = (nile_Mix_t *) k_;

    if (!k_->initialized) {
        k_->initialized = 1;
        nile_MixChild_t *child = nile_MixChild (nl);
        child->base.downstream = k_->downstream;
        k->v_k1->downstream = &child->base;
        k->v_k2->downstream = &child->base;
        k_->downstream = k->v_k2;
    }

    nile_Kernel_inbox_append (nl, k->v_k1, nile_Buffer_clone (nl, *in_));
    return NILE_INPUT_FORWARD;
}

nile_Kernel_t *
nile_Mix (nile_t *nl, nile_Kernel_t *k1, nile_Kernel_t *k2)
{
    nile_Mix_t *k = NILE_KERNEL_NEW (nl, nile_Mix);
    k->v_k1 = k1;
    k->v_k2 = k2;
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

typedef struct nile_InterleaveChild nile_InterleaveChild_t;
struct nile_InterleaveChild {
    nile_Kernel_t base;
    nile_InterleaveChild_t *sibling;
    int quantum;
    int j0;
    int n;
    int j;
};

static int
nile_InterleaveChild_process (nile_t *nl, nile_Kernel_t *k_,
                              nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_InterleaveChild_t *k = (nile_InterleaveChild_t *) k_;
    nile_Buffer_t *in = *in_;
    nile_Buffer_t *out;
    uint32_t *lock = &k_->downstream->lock;
    int sibling_is_suspended;
    int sibling_is_done;
    int j; 

    k_->initialized = 1;
    if (*out_) {
        nile_Buffer_free (nl, *out_);
        *out_ = NULL;
    }

    nile_lock (lock);
        out = k_->downstream->inbox;
        j = k->j;
    nile_unlock (lock);

    for (;;) {
        int i0 = in->i;
        while (in->i < in->n && j < k->n) {
            int q = k->quantum;
            while (q--)
                out->data[j++] = in->data[in->i++];
            j += k->sibling->quantum;
        }

        nile_lock (lock);
            out->n += in->i - i0;
            k->j = j;
            sibling_is_suspended = k->sibling->j >= k->sibling->n;
        nile_unlock (lock);

        if (in->i < in->n && sibling_is_suspended) {
            nile_Kernel_inbox_append (nl, k_->downstream->downstream, out);
            out = k_->downstream->inbox = nile_Buffer_new (nl);
            j = k->j = k->j0;
            k->sibling->j = k->sibling->j0;
            nile_Kernel_ready_now (nl, &k->sibling->base);
        }
        else break;
    }

    if (in->i == in->n && in->eos) {
        nile_lock (lock);
            sibling_is_done = out->eos;
            out->eos = 1;
        nile_unlock (lock);
        if (sibling_is_done) {
            nile_Kernel_inbox_append (nl, k_->downstream->downstream, out);
            nile_Kernel_free (nl, k_->downstream);
            nile_Kernel_free (nl, &k->sibling->base);
        }
        else {
            nile_Buffer_free (nl, in);
            *in_ = NULL;
            return NILE_INPUT_SUSPEND;
        }
    }

    return in->i == in->n ? NILE_INPUT_CONSUMED : NILE_INPUT_SUSPEND;
}

static nile_InterleaveChild_t *
nile_InterleaveChild (nile_t *nl, int quantum, int j0, int n)
{
    nile_InterleaveChild_t *k = (nile_InterleaveChild_t *)
        nile_Kernel_new (nl, nile_InterleaveChild_process, NULL);
    k->quantum = quantum;
    k->j0 = j0;
    k->n = n;
    k->j = j0;
    return k;
}

static int
nile_Interleave_process (nile_t *nl, nile_Kernel_t *k_,
                         nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Interleave_t *k = (nile_Interleave_t *) k_;

    if (!k_->initialized) {
        k_->initialized = 1;
        nile_Kernel_t *gchild = nile_Kernel_new (nl, NULL, NULL);
        gchild->inbox = nile_Buffer_new (nl);
        int eob = NILE_BUFFER_SIZE - (k->quantum1 + k->quantum2) + 1;
        nile_InterleaveChild_t *child1 =
            nile_InterleaveChild (nl, k->quantum1, 0, eob);
        nile_InterleaveChild_t *child2 =
            nile_InterleaveChild (nl, k->quantum2, k->quantum1, eob + k->quantum1);
        gchild->downstream = k_->downstream;
        child1->base.downstream = gchild;
        child2->base.downstream = gchild;
        child1->sibling = child2;
        child2->sibling = child1;
        k->v_k1->downstream = &child1->base;
        k->v_k2->downstream = &child2->base;
        k_->downstream = k->v_k1;
    }

    nile_Kernel_inbox_append (nl, k->v_k2, nile_Buffer_clone (nl, *in_));
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
            k_->downstream = clone;
            nile_Kernel_inbox_prepend (nl, k_, in);
            nile_Kernel_ready_later (nl, k_);
            *in_ = *out_ = NULL;
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
        while (out->next != NULL && key >= out->next->data[k->index])
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
                next->data[next->n++] = out->data[j++];
            out->n -= next->n;

            if (key >= next->data[k->index])
                out = next;
        }

        /* insert new element */
        int j = out->n - k->quantum;
        while (j >= 0 && key < out->data[j + k->index]) {
            int jj = j + k->quantum;
            int q = k->quantum;
            while (q--)
                out->data[jj++] = out->data[j++];
            j -= k->quantum + k->quantum;
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
