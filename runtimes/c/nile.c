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
    nile_Process_t *ready_q;
    int ready_q_length;
    int shutdown;
    nile_Buffer_t *freelist;
    uint32_t freelist_lock;
    uint32_t ready_q_lock;
    nile_Sem_t ready_q_has_process;
    nile_Sem_t ready_q_no_longer_too_long_sem;
    nile_Sem_t idle_sem;
    nile_Thread_t threads[MAX_THREADS];
};

/* Main thread loop */

static nile_Process_t NULL_PROCESS = {0};

static int
nile_Process_run (nile_Process_t *p);

static void * 
nile_Thread_main (nile_t *nl)
{
    nile_Process_t *p;
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

        nile_Sem_wait (&nl->ready_q_has_process);

        nile_lock (&nl->ready_q_lock);
            nl->nthreads_active++;
            p = nl->ready_q;
            if (p) {
                nl->ready_q = p->next;
                nl->ready_q_length--;
            }
            signal_q_no_longer_too_long =
                nl->ready_q_length == READY_Q_TOO_LONG_LENGTH - 1;
            shutdown = nl->shutdown;
        nile_unlock (&nl->ready_q_lock);

        if (shutdown)
            break;
        if (!p)
            continue;
        p->next = NULL;

        if (signal_q_no_longer_too_long)
           nile_Sem_signal (&nl->ready_q_no_longer_too_long_sem);

        for (;;) {
            nile_lock (&p->lock);
                active = p->active = p->inbox_n > 0;
            nile_unlock (&p->lock);
            if (!active)
                break;
            response = nile_Process_run (p);
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
    nile_Sem_new (&nl->ready_q_has_process, 0);
    nile_Sem_new (&nl->ready_q_no_longer_too_long_sem, 0);
    nile_Sem_new (&nl->idle_sem, 0);

    for (i = 0; i < nl->nthreads; i++)
        nile_Thread_new (nl, &(nl->threads[i]), nile_Thread_main);

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
        nile_Sem_signal (&nl->ready_q_has_process);

    for (i = 0; i < nl->nthreads; i++)
        nile_Thread_join (&(nl->threads[i]));

    nile_Sem_free (&nl->idle_sem);
    nile_Sem_free (&nl->ready_q_no_longer_too_long_sem);
    nile_Sem_free (&nl->ready_q_has_process);

    return (char *) nl;
}

/* External stream data */

void
nile_feed (nile_Process_t *p, nile_Real_t *data, int quantum, int n, int eos)
{
    nile_t *nl = p->nl;
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
            nile_Process_inbox_append (p, in);
            in = nile_Buffer_new (nl);
        }
    }
    in->eos = eos;
    nile_Process_inbox_append (p, in);

#ifndef NILE_MULTI_THREADED
    nl->nthreads_active++;
    nile_Thread_main (nl);
#endif
}

/* External synchronization (waiting until all processes are done) */

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

    b->nl = nl;
    b->next = NULL;
    b->i = 0;
    b->n = 0;
    b->eos = 0;
    return b;
}

void
nile_Buffer_free (nile_Buffer_t *b)
{
    nile_t *nl = b->nl;
    if (b) {
        nile_Buffer_t *next = b->next;
        nile_lock (&nl->freelist_lock);
            b->next = nl->freelist;
            nl->freelist = b;
        nile_unlock (&nl->freelist_lock);
        nile_Buffer_free (next);
    }
}

nile_Buffer_t *
nile_Buffer_clone (nile_Buffer_t *b)
{
    int i;
    nile_Buffer_t *clone = nile_Buffer_new (b->nl);
    clone->i = b->i;
    clone->n = b->n;
    clone->eos = b->eos;
    for (i = b->i; i < b->n; i++)
        clone->data[i] = b->data[i];
    return clone;
}

/* Process */

nile_Process_t *
nile_Process_new (nile_t *nl, nile_Process_work_t work)
{
    nile_Process_t *p = (nile_Process_t *) nile_Buffer_new (nl);
    p->nl = nl;
    p->next = NULL;
    p->work = work;
    p->downstream = NULL;
    p->lock = 0;
    p->inbox = NULL;
    p->inbox_n = 0;
    p->initialized = 0;
    p->active = 0;
    return p;
}

void
nile_Process_free (nile_Process_t *p)
{
    nile_Buffer_free ((nile_Buffer_t *) p);
}

static void
nile_Process_ready_now (nile_Process_t *p)
{
    nile_t *nl = p->nl;
    nile_lock (&nl->ready_q_lock);
        p->next = nl->ready_q;
        nl->ready_q = p;
        nl->ready_q_length++;
    nile_unlock (&nl->ready_q_lock);

    nile_Sem_signal (&nl->ready_q_has_process);
}

static void
nile_Process_ready_later (nile_Process_t *p)
{
    nile_t *nl = p->nl;
    nile_lock (&nl->ready_q_lock);
        nile_Process_t *ready_q = nl->ready_q;
        if (ready_q) {
            while (ready_q->next)
                ready_q = ready_q->next;
            ready_q->next = p;
        }
        else
            nl->ready_q = p;
        nl->ready_q_length++;
    nile_unlock (&nl->ready_q_lock);

    nile_Sem_signal (&nl->ready_q_has_process);
}

/* Process inbox management */

void
nile_Process_inbox_append (nile_Process_t *p, nile_Buffer_t *b)
{
    int n = 1;
    int must_activate = 0;
    nile_Buffer_t *inbox, *b_;

    if (p == &NULL_PROCESS || !b || (!b->n && !b->eos)) {
        nile_Buffer_free (b);
        return;
    }

    for (b_ = b; b_->next; b_ = b_->next)
        n++;

    nile_lock (&p->lock); 
        if (p->inbox_n) {
            for (inbox = p->inbox; inbox->next; inbox = inbox->next)
                ;
            inbox->next = b;
        }
        else {
            p->inbox = b;
            must_activate = !p->active;
        }
        p->inbox_n += n;
    nile_unlock (&p->lock); 

    if (must_activate)
        nile_Process_ready_now (p);
}

void
nile_Process_inbox_prepend (nile_Process_t *p, nile_Buffer_t *b)
{
    nile_lock (&p->lock);
        b->next = p->inbox;
        p->inbox = b;
        p->inbox_n++;
    nile_unlock (&p->lock);
}

/* Process execution */

static int
nile_Process_run (nile_Process_t *p)
{
    nile_Buffer_t *in, *out;
    int eos = 0;
    int response = NILE_INPUT_FORWARD;

    if (p->downstream && p->downstream->inbox_n >= NILE_INBOX_LIMIT) {
        nile_Process_ready_later (p);
        return NILE_INPUT_SUSPEND;
    }

    out = nile_Buffer_new (p->nl);
    while (p->inbox_n) {
        nile_lock (&p->lock);
            p->inbox_n--;
            in = p->inbox;
            p->inbox = in->next;
        nile_unlock (&p->lock);
        in->next = NULL;

        response = p->work (p, &in, &out);
        eos = in ? in->eos : 0;
        if (response == NILE_INPUT_CONSUMED && in->i < in->n)
            response = NILE_INPUT_SUSPEND;
        switch (response) {
            case NILE_INPUT_CONSUMED:
                nile_Buffer_free (in);
                break;
            case NILE_INPUT_FORWARD:
                nile_Process_inbox_append (p->downstream, out);
                out = NULL;
                nile_Process_inbox_append (p->downstream, in);
                if (!eos && p->downstream->inbox_n >= NILE_INBOX_LIMIT)
                    response = NILE_INPUT_SUSPEND;
                break;
            case NILE_INPUT_SUSPEND:
                if (in)
                    nile_Process_inbox_prepend (p, in);
                eos = 0;
                break;
        }
        if (response == NILE_INPUT_SUSPEND)
            break;
    }

    if (out && (response == NILE_INPUT_CONSUMED ||
                response == NILE_INPUT_SUSPEND)) {
        out->eos = eos;
        nile_Process_inbox_append (p->downstream, out);
    }
    else
        nile_Buffer_free (out);

    if (response == NILE_INPUT_SUSPEND && p->downstream->inbox_n >= NILE_INBOX_LIMIT)
        nile_Process_ready_later (p);

    if (eos) {
        nile_Process_free (p);
        response = NILE_INPUT_EOS;
    }

    return response;
}

/* Pipeline process */

typedef struct {
    nile_Process_t base;
    int n;
    nile_Process_t *ps[20];
} nile_Pipeline_t;

static int
nile_Pipeline_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Pipeline_t *p = (nile_Pipeline_t *) p_;
    int i;

    if (!p_->initialized) {
        p_->initialized = 1;
        p_->downstream = p_->downstream ? p_->downstream : &NULL_PROCESS;
        for (i = p->n - 1; i >= 0; i--) {
            p->ps[i]->downstream = p_->downstream;
            p_->downstream = p->ps[i];
        }
    }
    return NILE_INPUT_FORWARD;
}

nile_Process_t *
nile_Pipeline (nile_t *nl, ...)
{
    va_list args;
    nile_Process_t *pi;
    nile_Pipeline_t *p = (nile_Pipeline_t *)
        nile_Process_new (nl, nile_Pipeline_work);

    va_start (args, nl); 
    pi = va_arg (args, nile_Process_t *);
    for (p->n = 0; pi != NULL; p->n++) {
        p->ps[p->n] = pi;
        pi = va_arg (args, nile_Process_t *);
    }
    va_end (args);

    return (nile_Process_t *) p;
}

/* Capture process */

typedef struct {
    nile_Process_t base;
    nile_Real_t *sink;
    int size;
    int *n;
} nile_Capture_t;

static int
nile_Capture_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Capture_t *p = (nile_Capture_t *) p_;
    nile_Buffer_t *in = *in_;

    while (in->i < in->n) {
        nile_Real_t r = nile_Buffer_shift (in);
        if (*p->n < p->size)
            p->sink[*p->n] = r;
        (*p->n)++;
    }

    return NILE_INPUT_CONSUMED;
}

nile_Process_t *
nile_Capture (nile_t *nl, nile_Real_t *sink, int size, int *n)
{
    nile_Capture_t *p = (nile_Capture_t *)
        nile_Process_new (nl, nile_Capture_work);
    p->sink = sink;
    p->size = size;
    p->n    = n;
    return (nile_Process_t *) p;
}

/* Mix process */

typedef struct {
    nile_Process_t base;
    nile_Process_t *v_p1;
    nile_Process_t *v_p2;
} nile_Mix_t;

typedef struct {
    nile_Process_t base;
    int eos_seen;
} nile_MixChild_t;

static int
nile_MixChild_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_MixChild_t *p = (nile_MixChild_t *) p_;
    nile_Buffer_t *in = *in_;

    p_->initialized = 1;
    if (*out_) {
        nile_Buffer_free (*out_);
        *out_ = NULL;
    }

    if (in->eos && !p->eos_seen) {
        p->eos_seen = 1;
        in->eos = 0;
    }

    return NILE_INPUT_FORWARD;
}

static nile_MixChild_t *
nile_MixChild (nile_t *nl)
{
    nile_MixChild_t *p = (nile_MixChild_t *)
        nile_Process_new (nl, nile_MixChild_work);
    p->eos_seen = 0;
    return p;
}

static int
nile_Mix_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Mix_t *p = (nile_Mix_t *) p_;

    if (!p_->initialized) {
        p_->initialized = 1;
        nile_MixChild_t *child = nile_MixChild (p_->nl);
        child->base.downstream = p_->downstream;
        p->v_p1->downstream = &child->base;
        p->v_p2->downstream = &child->base;
        p_->downstream = p->v_p2;
    }

    nile_Process_inbox_append (p->v_p1, nile_Buffer_clone (*in_));
    return NILE_INPUT_FORWARD;
}

nile_Process_t *
nile_Mix (nile_t *nl, nile_Process_t *p1, nile_Process_t *p2)
{
    nile_Mix_t *p = (nile_Mix_t *)
        nile_Process_new (nl, nile_Mix_work);
    p->v_p1 = p1;
    p->v_p2 = p2;
    return (nile_Process_t *) p;
}

/* Interleave process */

typedef struct {
    nile_Process_t base;
    nile_Process_t *v_p1;
    int quantum1;
    nile_Process_t *v_p2;
    int quantum2;
} nile_Interleave_t;

typedef struct nile_InterleaveChild nile_InterleaveChild_t;
struct nile_InterleaveChild {
    nile_Process_t base;
    nile_InterleaveChild_t *sibling;
    int quantum;
    int j0;
    int n;
    int j;
};

static int
nile_InterleaveChild_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_InterleaveChild_t *p = (nile_InterleaveChild_t *) p_;
    nile_Buffer_t *in = *in_;
    nile_Buffer_t *out;
    uint32_t *lock = &p_->downstream->lock;
    int sibling_is_suspended;
    int sibling_is_done;
    int j; 

    p_->initialized = 1;
    if (*out_) {
        nile_Buffer_free (*out_);
        *out_ = NULL;
    }

    nile_lock (lock);
        out = p_->downstream->inbox;
        j = p->j;
    nile_unlock (lock);

    for (;;) {
        int i0 = in->i;
        while (in->i < in->n && j < p->n) {
            int q = p->quantum;
            while (q--)
                out->data[j++] = in->data[in->i++];
            j += p->sibling->quantum;
        }

        nile_lock (lock);
            out->n += in->i - i0;
            p->j = j;
            sibling_is_suspended = p->sibling->j >= p->sibling->n;
        nile_unlock (lock);

        if (in->i < in->n && sibling_is_suspended) {
            nile_Process_inbox_append (p_->downstream->downstream, out);
            out = p_->downstream->inbox = nile_Buffer_new (p_->nl);
            j = p->j = p->j0;
            p->sibling->j = p->sibling->j0;
            nile_Process_ready_now (&p->sibling->base);
        }
        else break;
    }

    if (in->i == in->n && in->eos) {
        nile_lock (lock);
            sibling_is_done = out->eos;
            out->eos = 1;
        nile_unlock (lock);
        if (sibling_is_done) {
            nile_Process_inbox_append (p_->downstream->downstream, out);
            nile_Process_free (p_->downstream);
            nile_Process_free (&p->sibling->base);
        }
        else {
            nile_Buffer_free (in);
            *in_ = NULL;
            return NILE_INPUT_SUSPEND;
        }
    }

    return in->i == in->n ? NILE_INPUT_CONSUMED : NILE_INPUT_SUSPEND;
}

static nile_InterleaveChild_t *
nile_InterleaveChild (nile_t *nl, int quantum, int j0, int n)
{
    nile_InterleaveChild_t *p = (nile_InterleaveChild_t *)
        nile_Process_new (nl, nile_InterleaveChild_work);
    p->quantum = quantum;
    p->j0 = j0;
    p->n = n;
    p->j = j0;
    return p;
}

static int
nile_Interleave_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_Interleave_t *p = (nile_Interleave_t *) p_;

    if (!p_->initialized) {
        p_->initialized = 1;
        nile_Process_t *gchild = nile_Process_new (p_->nl, NULL);
        gchild->inbox = nile_Buffer_new (p_->nl);
        int eob = NILE_BUFFER_SIZE - (p->quantum1 + p->quantum2) + 1;
        nile_InterleaveChild_t *child1 =
            nile_InterleaveChild (p_->nl, p->quantum1, 0, eob);
        nile_InterleaveChild_t *child2 =
            nile_InterleaveChild (p_->nl, p->quantum2, p->quantum1, eob + p->quantum1);
        gchild->downstream = p_->downstream;
        child1->base.downstream = gchild;
        child2->base.downstream = gchild;
        child1->sibling = child2;
        child2->sibling = child1;
        p->v_p1->downstream = &child1->base;
        p->v_p2->downstream = &child2->base;
        p_->downstream = p->v_p1;
    }

    nile_Process_inbox_append (p->v_p2, nile_Buffer_clone (*in_));
    return NILE_INPUT_FORWARD;
}

nile_Process_t *
nile_Interleave (nile_t *nl, nile_Process_t *v_p1, int quantum1,
                             nile_Process_t *v_p2, int quantum2)
{
    nile_Interleave_t *p = (nile_Interleave_t *)
        nile_Process_new (nl, nile_Interleave_work);
    p->v_p1 = v_p1;
    p->quantum1 = quantum1;
    p->v_p2 = v_p2;
    p->quantum2 = quantum2;
    return (nile_Process_t *) p;
}

/* SortBy process */

typedef struct {
    nile_Process_t base;
    int index;
    int quantum;
    nile_Buffer_t *out;
} nile_SortBy_t;

static int
nile_SortBy_work (nile_Process_t *p_, nile_Buffer_t **in_, nile_Buffer_t **out_)
{
    nile_SortBy_t *p = (nile_SortBy_t *) p_;
    nile_Buffer_t *in = *in_;

    if (!p_->initialized) {
        p_->initialized = 1;
        p->out = *out_;
        p->out->eos = 1;
        *out_ = NULL;
    }

    if (*out_) {
        nile_Buffer_free (*out_);
        *out_ = NULL;
    }

    while (in->i < in->n) {
        nile_Buffer_t *out = p->out;
        real key = in->data[in->i + p->index];

        /* find the right buffer */
        while (out->next != NULL && key >= out->next->data[p->index])
            out = out->next;

        /* split the buffer if it's full */
        if (out->n > NILE_BUFFER_SIZE - p->quantum) {
            nile_Buffer_t *next = nile_Buffer_new (p_->nl);
            next->eos = out->eos;
            next->next = out->next;
            out->eos = 0;
            out->next = next;

            int j = out->n / p->quantum / 2 * p->quantum;
            while (j < out->n)
                next->data[next->n++] = out->data[j++];
            out->n -= next->n;

            if (key >= next->data[p->index])
                out = next;
        }

        /* insert new element */
        int j = out->n - p->quantum;
        while (j >= 0 && key < out->data[j + p->index]) {
            int jj = j + p->quantum;
            int q = p->quantum;
            while (q--)
                out->data[jj++] = out->data[j++];
            j -= p->quantum + p->quantum;
        }
        j += p->quantum;
        int q = p->quantum;
        while (q--)
            out->data[j++] = in->data[in->i++];
        out->n += p->quantum;
    }

    if (in->eos)
        nile_Process_inbox_append (p_->downstream, p->out);

    return NILE_INPUT_CONSUMED;
}

nile_Process_t *
nile_SortBy (nile_t *nl, int index, int quantum)
{
    nile_SortBy_t *p = (nile_SortBy_t *)
        nile_Process_new (nl, nile_SortBy_work);
    p->index = index;
    p->quantum = quantum;
    return (nile_Process_t *) p;
}
