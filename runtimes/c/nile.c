#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#include "nile-platform.h"
#include "nile-heap.h"
#include "nile-deque.h"
#define DEBUG
#include "test/nile-debug.h"

#define INPUT_QUOTA 5
#define INPUT_MAX (2 * INPUT_QUOTA)
#define Real nile_Real_t
#define BAT(b, i) ((&b->data)[i])

typedef struct nile_Thread_ nile_Thread_t;

static void
nile_Thread_work_until_below (nile_Thread_t *liaison, int *var, int value);

static void
nile_Process_run (nile_Process_t *p, nile_Thread_t *thread);

/* Thread sleeping */

typedef CACHE_ALIGNED struct {
    nile_Lock_t lock;
    int         nthreads;
    int         nsleeping;
    nile_Sem_t  wakeup;
    nile_Sem_t  quiecent;
} CACHE_ALIGNED nile_Sleep_t;

static void
nile_Sleep_init (nile_Sleep_t *s, int nthreads)
{
    s->nthreads = nthreads;
    s->lock = s->nsleeping = 0;
    nile_Sem_init (&s->wakeup, 0);
    nile_Sem_init (&s->quiecent, 0);
}

static void
nile_Sleep_fini (nile_Sleep_t *s)
{
    nile_Sem_fini (&s->wakeup);
    nile_Sem_fini (&s->quiecent);
}

static void
nile_Sleep_issue_wakeup (nile_Sleep_t *s)
{
    if (s->nsleeping)
        nile_Sem_signal (&s->wakeup);
}

static void
nile_Sleep_prepare_to_sleep (nile_Sleep_t *s)
{
    int nsleeping;
    nile_Lock_acq (&s->lock);
        nsleeping = ++s->nsleeping;
    nile_Lock_rel (&s->lock);
    if (nsleeping == s->nthreads)
        nile_Sem_signal (&s->quiecent);
}

static void
nile_Sleep_wokeup (nile_Sleep_t *s)
{
    nile_Lock_acq (&s->lock);
        s->nsleeping--;
    nile_Lock_rel (&s->lock);
}

static void
nile_Sleep_wait_for_quiecent (nile_Sleep_t *s)
{
    nile_Sleep_prepare_to_sleep (s);
    do {
        nile_Sem_wait (&s->quiecent);
    } while (s->nsleeping != s->nthreads);
    nile_Sleep_wokeup (s);
}

static void
nile_Sleep_wait_for_wakeup (nile_Sleep_t *s)
{
    nile_Sleep_prepare_to_sleep (s);
    nile_Sem_wait (&s->wakeup);
    nile_Sleep_wokeup (s);
}

static void
nile_Sleep_doze (int npauses)
    { while (npauses--) nile_pause (); }

/* Threads */

CACHE_ALIGNED struct nile_Thread_ {
    nile_Lock_t      lock;
    nile_Heap_t      private_heap;
    nile_Heap_t      public_heap;
    nile_Deque_t     q;
    int              index;
    nile_Thread_t   *threads;
    int              nthreads;
    nile_Sleep_t    *sleep;
    char            *memory;
    int              nbytes;
    int              sync;
    int              abort;
    nile_OSThread_t  osthread;
} CACHE_ALIGNED;

static void
nile_Thread (int index, nile_Thread_t *threads, int nthreads,
             nile_Sleep_t *sleep, char *memory, int nbytes)
{
    nile_Thread_t *t = &threads[index];
    t->lock = 0;
    t->private_heap = t->public_heap = NULL;
    t->q.n = 0;
    t->q.head = t->q.tail = NULL;
    t->index = index;
    t->threads = threads;
    t->nthreads = nthreads;
    t->sleep = sleep;
    t->memory = memory;
    t->nbytes = nbytes;
    t->sync = t->abort = 0;
}

static void *
nile_Thread_steal (nile_Thread_t *t, void *(*action) (nile_Thread_t *))
{
    int i;
    int j = t->index + t->nthreads;
    void *v;
    nile_Thread_t *victim;

    if (t->abort)
        return NULL;
    for (i = 1; i < t->nthreads; i++) {
        j += ((i % 2) ^ (t->index % 2) ? i : -i);
        victim = &t->threads[j % t->nthreads];
        if ((v = action (victim)))
            return v;
    }
    return action (&t->threads[t->nthreads]);
}

static void *
nile_Thread_steal_from_heap (nile_Thread_t *victim)
{
    nile_Chunk_t *c = NULL;
    if (victim->public_heap) {
        nile_Lock_acq (&victim->lock);
            c = nile_Heap_pop_chunk (&victim->public_heap);
        nile_Lock_rel (&victim->lock);
    }
    return c;
}

static void *
nile_Thread_steal_from_q (nile_Thread_t *victim)
{
    nile_Process_t *p = NULL;
    if (victim->q.n) {
        nile_Lock_acq (&victim->lock);
            p = (nile_Process_t *) nile_Deque_pop_head (&victim->q);
        nile_Lock_rel (&victim->lock);
    }
    return p;
}

static void
nile_Thread_append_to_q (nile_Thread_t *t, nile_Process_t *p)
{
    nile_Lock_acq (&t->lock);
        nile_Deque_push_tail (&t->q, (nile_Node_t *) p);
    nile_Lock_rel (&t->lock);
    nile_Sleep_issue_wakeup (t->sleep);
}

static nile_Chunk_t *
nile_Thread_alloc_chunk (nile_Thread_t *t)
{
    int i;
    nile_Chunk_t *c;
    nile_Lock_acq (&t->lock);
        c = nile_Heap_pop_chunk (&t->public_heap);
    nile_Lock_rel (&t->lock);
    if (c || t->abort)
        return c;
    c = nile_Thread_steal (t, nile_Thread_steal_from_heap);
    if (!c)
        for (i = 0; i < t->nthreads + 1; i++)
            t->threads[i].abort = 1;
    return c;
}

static void
nile_Thread_free_chunk (nile_Thread_t *t, nile_Chunk_t *c)
{
    nile_Lock_acq (&t->lock);
        nile_Heap_push_chunk (&t->public_heap, c);
    nile_Lock_rel (&t->lock);
}

static void
nile_Thread_work (nile_Thread_t *t, nile_Process_t *p)
{
    do {
        nile_Process_run (p, t);
        nile_Lock_acq (&t->lock);
            p = (nile_Process_t *) nile_Deque_pop_tail (&t->q);
        nile_Lock_rel (&t->lock);
    } while (p && !t->abort);
}

static void *
nile_Thread_main (void *arg)
{
    nile_Thread_t *t = arg;
    nile_Process_t *p;
    const int MIN_PAUSES =    1000;
    const int MAX_PAUSES = 1000000;
    int npauses = MIN_PAUSES;

    while (!t->abort) {
        if ((p = nile_Thread_steal (t, nile_Thread_steal_from_q))) {
            nile_Thread_work (t, p);
            npauses = MIN_PAUSES;
        }
        else if (npauses > MAX_PAUSES || t->sync) {
            nile_Sleep_wait_for_wakeup (t->sleep);
            npauses = MIN_PAUSES;
        }
        else {
            nile_Sleep_doze (npauses);
            npauses *= 2;
        }
    }
    nile_Sleep_prepare_to_sleep (t->sleep);
    return arg;
}

static void
nile_Thread_transfer_heaps (nile_Thread_t *from, nile_Thread_t *to)
{
    nile_Lock_acq (&from->lock);
        to->public_heap = from->public_heap;
        from->public_heap = NULL;
    nile_Lock_rel (&from->lock);
    to->private_heap = from->private_heap;
    from->private_heap = NULL;
}

static void
nile_Thread_work_until_below (nile_Thread_t *liaison, int *var, int value)
{
    nile_Process_t *p;
    nile_Thread_t *worker = &liaison->threads[0];
    nile_Thread_transfer_heaps (liaison, worker);

    do {
        nile_Lock_acq (&worker->lock);
            p = (nile_Process_t *) nile_Deque_pop_tail (&worker->q);
        nile_Lock_rel (&worker->lock);
        if (!p)
            p = nile_Thread_steal (worker, nile_Thread_steal_from_q);
        if (!p)
            break;
        nile_Process_run (p, worker);
    } while (!worker->abort && *var >= value);

    nile_Thread_transfer_heaps (worker, liaison);
}

/* Stream buffers */

static void *
nile_Process_alloc_node (nile_Process_t *p);

#define BUFFER_TO_NODE(b) (((nile_Node_t   *)  b) - 1)
#define NODE_TO_BUFFER(n) ( (nile_Buffer_t *) (n + 1))

INLINE nile_Buffer_t *
nile_Buffer (nile_Process_t *p)
{
    nile_Node_t *nd = nile_Process_alloc_node (p);
    nile_Buffer_t *b = NODE_TO_BUFFER (nd);
    if (!nd)
        return NULL;
    nd->type = NILE_BUFFER_TYPE;
    b->head = b->tail = 0;
    b->tag = NILE_TAG_NONE;
    b->capacity = (sizeof (nile_Block_t) - sizeof (*nd) - sizeof (*b)) / sizeof (Real) + 1;
    return b;
}

static void
nile_Buffer_copy (nile_Buffer_t *from, nile_Buffer_t *to)
{
    // FIXME this assumes nile_Real_t == float (for the autovectorizer)
    float *from_data = &from->data.f;
    float *to_data = &to->data.f;
    int head = to->head = from->head;
    int tail = to->tail = from->tail;
    for (; head < tail; head++)
        to_data[head] = from_data[head];
}

/* Processes */

typedef enum {
    NILE_BLOCKED_ON_GATE,
    NILE_BLOCKED_ON_PRODUCER,
    NILE_BLOCKED_ON_CONSUMER,
    NILE_NOT_BLOCKED,
} nile_ProcessState_t;

struct nile_Process_ {
    nile_Node_t           node;
    nile_Thread_t        *thread;
    nile_Lock_t           lock;
    nile_Heap_t           heap;
    nile_Deque_t          input;
    int                   quantum;
    int                   sizeof_vars;
    nile_Process_logue_t  prologue;
    nile_Process_body_t   body;
    nile_Process_logue_t  epilogue;
    nile_ProcessState_t   state;
    nile_Process_t       *producer;
    nile_Process_t       *consumer;
    nile_Process_t       *gatee;
    nile_Process_t       *parent;
};

static void *
nile_Process_alloc_node (nile_Process_t *p)
{
    nile_Chunk_t *c;
    void *v = nile_Heap_pop (&p->heap);
    if (v)
        return v;
    c = nile_Thread_alloc_chunk (p->thread);
    if (c)
        nile_Heap_push_chunk (&p->heap, c);
    return nile_Heap_pop (&p->heap);
}

static void
nile_Process_free_node (nile_Process_t *p, nile_Node_t *nd)
{
    if (nile_Heap_push (&p->heap, nd))
        nile_Thread_free_chunk (p->thread, nile_Heap_pop_chunk (&p->heap));
}

static nile_Buffer_t *
nile_Process_default_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
    { return nile_Process_swap (p, NULL, out); }

nile_Process_t *
nile_Process (nile_Process_t *p, int quantum, int sizeof_vars,
              nile_Process_logue_t prologue,
              nile_Process_body_t  body,
              nile_Process_logue_t epilogue)
{
    nile_Process_t *parent = p;
    if (!parent)
        return NULL;
    p = nile_Process_alloc_node (p);
    if (!p)
        return NULL;
    p->node.type = NILE_PROCESS_TYPE;
    p->node.next = NULL;
    p->thread = parent->thread;
    p->lock = 0;
    p->heap = NULL;
    p->input.head = p->input.tail = NULL;
    p->input.n = 0;
    p->quantum = quantum;
    p->sizeof_vars = sizeof_vars;
    p->prologue = prologue;
    p->body = body ? body : nile_Process_default_body;
    p->epilogue = epilogue;
    p->state = NILE_BLOCKED_ON_PRODUCER;
    p->producer = p;
    p->consumer = p->gatee = NULL;
    p->parent = parent;
    return p;
}

/*
nile_Process_t *
nile_Process_clone (nile_Process_t *p)
{
    char *vars = nile_Process_vars (p);
    p = nile_Process (p, p->quantum, p->sizeof_vars, p->prologue, p->body, p->epilogue);
    if (p) {
        int i;
        int n = p->sizeof_vars;
        char *cvars = nile_Process_vars (p);
        for (i = 0; i < n; i++)
            cvars[i] = vars[i];
    }
    return p;
}
*/

void *
nile_Process_vars (nile_Process_t *p)
    { return (void *) (p + 1); }

void
nile_Process_gate (nile_Process_t *gater, nile_Process_t *gatee)
{
    if (gater && gatee) {
        gater->gatee = gatee;
        gatee->state = NILE_BLOCKED_ON_GATE;
    }
}

nile_Process_t *
nile_Process_pipe (nile_Process_t *p1, ...)
{
    va_list args;
    nile_Process_t *pi, *pj;
    if (!p1)
        return p1;
    va_start (args, p1); 
    pi = p1;
    while (pi->consumer)
        pi = pi->consumer;
    pj = va_arg (args, nile_Process_t *);
    while (pj) {
        pi->consumer = pj;
        pj->producer = pi;
        while (pj->consumer)
            pj = pj->consumer;
        pi = pj;
        pj = va_arg (args, nile_Process_t *);
    }
    va_end (args);
    return p1;
}

nile_Process_t *
nile_Process_pipe_v (nile_Process_t **ps, int n)
{
    int j;
    nile_Process_t *pi, *pj;
    if (!n)
        return NULL;
    pi = ps[0];
    if (!pi)
        return NULL;
    while (pi->consumer)
        pi = pi->consumer;
    for (j = 1; j < n; j++) {
        pj = ps[j];
        if (!pj)
            return NULL;
        pi->consumer = pj;
        pj->producer = pi;
        while (pj->consumer)
            pj = pj->consumer;
        pi = pj;
    }
    return ps[0];
}

void
nile_Process_feed (nile_Process_t *p, float *data, int n)
{
    nile_Funnel_pour (nile_Process_pipe (nile_Funnel (p->parent), p, NILE_NULL), data, n, 1);
}

static int
nile_Process_block_on_producer (nile_Process_t *p)
{
    nile_ProcessState_t pstate = -1;
    nile_Lock_acq (&p->lock);
        p->state = NILE_BLOCKED_ON_PRODUCER;
        pstate = p->producer ? p->producer->state : pstate;
    nile_Lock_rel (&p->lock);
    return !(pstate == -1 || pstate == NILE_BLOCKED_ON_CONSUMER);
}

static nile_Heap_t
nile_Process_remove (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap);

static nile_Heap_t
nile_Process_schedule (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap)
{
    if (!p->body)
        return nile_Process_remove (p, thread, heap);
    if (p->input.n >= INPUT_QUOTA || !p->producer || !nile_Process_block_on_producer (p)) {
        p->state = NILE_NOT_BLOCKED;
        nile_Thread_append_to_q (thread, p);
    }
    return heap;
}

static nile_Heap_t
nile_Process_remove (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap)
{
    nile_ProcessState_t cstate;
    nile_Process_t *producer = p->producer;
    nile_Process_t *consumer = p->consumer;
    nile_Deque_t input = p->input;

    if (p->gatee)
        heap = nile_Process_schedule (p->gatee, thread, heap);
    if (producer)
        producer->consumer = consumer;
    if (consumer) {
        nile_Lock_acq (&consumer->lock);
            while (input.n)
                nile_Deque_push_tail (&consumer->input, nile_Deque_pop_head (&input));
            consumer->producer = producer;
            cstate = consumer->state;
        nile_Lock_rel (&consumer->lock);
        nile_Heap_push (&heap, p);
        if (cstate == NILE_BLOCKED_ON_PRODUCER)
            heap = nile_Process_schedule (consumer, thread, heap);
    }
    else {
        p->thread = thread;
        p->heap = heap;
        while (input.n)
            nile_Process_free_node (p, nile_Deque_pop_head (&input));
        heap = p->heap;
        nile_Heap_push (&heap, p);
        if (producer && producer->state == NILE_BLOCKED_ON_CONSUMER)
            heap = nile_Process_schedule (producer, thread, heap);
    }
    return heap;
}

static void
nile_Process_enqueue_output (nile_Process_t *producer, nile_Buffer_t *out)
{
    nile_Node_t *nd = BUFFER_TO_NODE (out);
    nile_Process_t *consumer = producer->consumer;
    if (!consumer || nile_Buffer_is_empty (out))
        nile_Process_free_node (producer, nd);
    else {
        nile_Lock_acq (&consumer->lock);
            nile_Deque_push_tail (&consumer->input, nd);
        nile_Lock_rel (&consumer->lock);
    }
}

static int
nile_Process_quota_hit (nile_Process_t *p)
{
    int n;
    if (!p)
        return 0;
    n = p->input.n;
    return (n >= INPUT_QUOTA - 1 &&
            (p->state == NILE_BLOCKED_ON_PRODUCER || n > INPUT_MAX));
}

nile_Buffer_t *
nile_Process_append_output (nile_Process_t *producer, nile_Buffer_t *out)
{
    nile_Buffer_t *b = nile_Buffer (producer);
    if (!b) {
        out->tag = NILE_TAG_OOM;
        out->head = out->tail = 0;
        return out;
    }
    nile_Process_enqueue_output (producer, out);
    if (nile_Process_quota_hit (producer->consumer))
        b->tag = NILE_TAG_QUOTA_HIT;
    return b;
}

nile_Buffer_t *
nile_Process_prefix_input (nile_Process_t *producer, nile_Buffer_t *in)
{
    nile_Buffer_t *b = nile_Buffer (producer);
    if (b) {
        nile_Lock_acq (&producer->lock);
            nile_Deque_push_head (&producer->input, BUFFER_TO_NODE (b));
        nile_Lock_rel (&producer->lock);
    }
    else
        b = in;
    b->head = b->tail = b->capacity;
    return b;
}

static nile_Thread_t *
nile_Process_halting (nile_Process_t *p, nile_Buffer_t *out)
{
    if (out->tag != NILE_TAG_OOM) {
        nile_Process_enqueue_output (p, out);
        p->thread->private_heap = p->heap;
    }
    return p->thread;
}

nile_Buffer_t *
nile_Process_swap (nile_Process_t *p, nile_Process_t *sub, nile_Buffer_t *out)
{
    nile_Thread_t *thread = nile_Process_halting (p, out);
    if (sub) {
        nile_Process_t *consumer = p->consumer;
        p->consumer = NULL;
        nile_Process_pipe (p, sub, consumer, NILE_NULL);
    }
    p->body = NULL;
    if (!p->producer || !nile_Process_block_on_producer (p))
        thread->private_heap = nile_Process_remove (p, thread, thread->private_heap);
    return NULL;
}

static void
nile_Process_handle_backpressure (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_ProcessState_t cstate;
    nile_Process_t *consumer = p->consumer;
    nile_Thread_t *thread = nile_Process_halting (p, out);

    nile_Lock_acq (&consumer->lock);
        p->state = NILE_BLOCKED_ON_CONSUMER;
        cstate = consumer->state;
    nile_Lock_rel (&consumer->lock);

    if (cstate == NILE_BLOCKED_ON_PRODUCER)
        thread->private_heap = nile_Process_schedule (consumer, thread, thread->private_heap);
}

static void
nile_Process_handle_out_of_input (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_Thread_t *thread = nile_Process_halting (p, out);

    if (p->producer && nile_Process_block_on_producer (p))
        return;
    else if (p->producer)
        thread->private_heap = nile_Process_schedule (p->producer, thread, thread->private_heap);
    else if (p->input.n)
        thread->private_heap = nile_Process_schedule (p, thread, thread->private_heap);
    else if (p->epilogue) {
        p->heap = thread->private_heap;
        out = nile_Buffer (p);
        if (!out)
            return;
        out = p->epilogue (p, out);
        if (!out || out->tag == NILE_TAG_OOM)
            return;
        nile_Process_halting (p, out);
        thread->private_heap = nile_Process_remove (p, thread, thread->private_heap);
    }
    else
        thread->private_heap = nile_Process_remove (p, thread, thread->private_heap);
}

static void
nile_Process_pop_input (nile_Process_t *p)
{
    nile_ProcessState_t pstate = -1;
    nile_Node_t *head = p->input.head;
    int at_quota = (p->input.n == INPUT_QUOTA);
    if (!head || !nile_Buffer_is_empty (NODE_TO_BUFFER (head)))
        return;

    nile_Lock_acq (&p->lock);
        nile_Deque_pop_head (&p->input);
        if (at_quota && p->producer)
            pstate = p->producer->state;
    nile_Lock_rel (&p->lock);

    nile_Process_free_node (p, head);
    if (pstate == NILE_BLOCKED_ON_CONSUMER)
        p->heap = nile_Process_schedule (p->producer, p->thread, p->heap);
}

static void
nile_Process_run (nile_Process_t *p, nile_Thread_t *thread)
{
    nile_Buffer_t *out;
    p->thread = thread;
    p->heap = thread->private_heap;
    out = nile_Buffer (p);
    if (!out)
        return;

    if (p->prologue) {
        out = p->prologue (p, out);
        if (!out || out->tag == NILE_TAG_OOM)
            return;
        p->prologue = NULL;
    }

    while (p->input.head) {
        out = p->body (p, NODE_TO_BUFFER (p->input.head), out);
        if (!out || out->tag == NILE_TAG_OOM)
            return;
        nile_Process_pop_input (p);
        if (out->tag == NILE_TAG_QUOTA_HIT)
            return nile_Process_handle_backpressure (p, out);
    }
    nile_Process_handle_out_of_input (p, out);
}

/* Runtime routines */

nile_Process_t *
nile_startup (char *memory, int nbytes, int nthreads)
{
    int i;
    nile_Process_t *init;
    nile_Sleep_t *sleep;
    nile_Thread_t *threads;
    nile_Block_t *block, *EOB;
    nile_Process_t boot;

#ifdef NILE_DISABLE_THREADS
    nthreads = 1;
#endif

    if ((size_t) nbytes < CACHE_LINE_SIZE + sizeof (*sleep) + sizeof (*threads) * (nthreads + 1))
        return NULL;

    sleep = (nile_Sleep_t *)
        (((size_t) memory + CACHE_LINE_SIZE - 1) & ~(CACHE_LINE_SIZE - 1));
    nile_Sleep_init (sleep, nthreads);

    threads = (nile_Thread_t *) (sleep + 1);
    for (i = 0; i < nthreads + 1; i++)
        nile_Thread (i, threads, nthreads, sleep, memory, nbytes);

    block = (nile_Block_t *) (threads + nthreads + 1);
    EOB   = (nile_Block_t *) (memory + nbytes - sizeof (*block) + 1);
    while (block < EOB)
        for (i = 1; i < nthreads + 1 && block < EOB; i++, block++)
            nile_Heap_push (&threads[i].public_heap, block);

    for (i = 1; i < nthreads; i++)
        nile_OSThread_spawn (&threads[i].osthread, nile_Thread_main, &threads[i]);

    boot.thread = &threads[nthreads];
    boot.heap = boot.thread->private_heap;
    init = nile_Process (&boot, 0, 0, NULL, NULL, NULL);
    if (init)
        init->heap = boot.heap;
    return init;
}

void
nile_sync (nile_Process_t *init)
{
    int i;
    nile_Process_t *p;
    nile_Thread_t *liaison = init->thread;
    nile_Thread_t *worker = &liaison->threads[0];

    liaison->private_heap = init->heap;
    nile_Thread_transfer_heaps (liaison, worker);
    for (i = 1; i < liaison->nthreads; i++)
        liaison->threads[i].sync = 1;

    if ((p = nile_Thread_steal_from_q (worker)))
        nile_Thread_work (worker, p);
    while (!worker->abort && (p = nile_Thread_steal (worker, nile_Thread_steal_from_q)))
        nile_Thread_work (worker, p);
    nile_Sleep_wait_for_quiecent (liaison->sleep);

    for (i = 1; i < liaison->nthreads; i++)
        liaison->threads[i].sync = 0;
    nile_Thread_transfer_heaps (worker, liaison);
    init->heap = liaison->private_heap;
}

int
nile_error (nile_Process_t *init)
{
    return init->thread->abort;
}

char *
nile_shutdown (nile_Process_t *init)
{
    int i;
    nile_Thread_t *t = init->thread;
    for (i = 0; i < t->nthreads + 1; i++)
        t->threads[i].abort = 1;
    for (i = 0; i < t->nthreads; i++)
        nile_Sleep_issue_wakeup (t->sleep);
    for (i = 1; i < t->nthreads; i++)
        nile_OSThread_join (&t->threads[i].osthread);
    nile_Sleep_fini (t->sleep);
    return t->memory;
}

/* Identity process */

nile_Process_t *
nile_Identity (nile_Process_t *p, int quantum)
    { return nile_Process (p, quantum, 0, NULL, NULL, NULL); }

/* Funnel process */

typedef struct {
    nile_Process_t *init;
    int            *i;
    float          *data;
    int             n;
} nile_Funnel_vars_t;

static nile_Buffer_t *
nile_Funnel_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_Funnel_vars_t *vars = nile_Process_vars (p);
    nile_Funnel_vars_t v = *vars;
    nile_Thread_t *thread = p->thread;
    nile_Process_t *consumer = p->consumer;
    int quantum = consumer ? consumer->quantum : 1;
    int m = (out->capacity / quantum) * quantum;
    int i = *(v.i);

    for (;;) {
        int q = (m < v.n - i) ? m : v.n - i;
        while (q--)
            nile_Buffer_push_tail (out, nile_Real (v.data[i++]));
        if (i == v.n)
            break;
        out = nile_Process_append_output (p, out);
        if (out->tag == NILE_TAG_QUOTA_HIT && consumer->input.n >= INPUT_QUOTA) {
            if (consumer->state == NILE_BLOCKED_ON_PRODUCER)
                p->heap = nile_Process_schedule (consumer, thread, p->heap);
            else
                break;
        }
    }

    *(vars->i) = i;
    if (i == v.n && !p->producer) {
        out->tag = NILE_TAG_NONE;
        return out;
    }
    nile_Process_halting (p, out);
    return NULL;
}

nile_Process_t *
nile_Funnel (nile_Process_t *init)
{
    nile_Process_t *p = nile_Process (init, 1, 0, nile_Funnel_prologue, NULL, NULL);
    if (p) {
        nile_Funnel_vars_t *vars = nile_Process_vars (p);
        vars->init = init;
        p->state = NILE_BLOCKED_ON_GATE;
    }
    return p;
}

void
nile_Funnel_pour (nile_Process_t *p, float *data, int n, int EOS)
{
    int i = 0;
    nile_Funnel_vars_t *vars;
    nile_Process_t *init;
    nile_Thread_t *liaison;
    if (!p)
        return;
    vars = nile_Process_vars (p);
    init = vars->init;
    liaison = init->thread;
    liaison->private_heap = init->heap;
    if (liaison->q.n > 4 * liaison->nthreads)
        nile_Thread_work_until_below (liaison, &liaison->q.n, 2 * liaison->nthreads);
    vars->i = &i;
    vars->data = data;
    vars->n = n;
    p->producer = EOS ? NULL : p->producer;
    nile_Process_run (p, liaison);
    if (i != n) {
        nile_Thread_work_until_below (liaison, &p->consumer->input.n, INPUT_MAX);
        init->heap = liaison->private_heap;
        return nile_Funnel_pour (p, data + i, n - i, EOS);
    }
    init->heap = liaison->private_heap;
}

/* Capture process */

typedef struct {
    float *data;
    int   *n;
    int    size;
} nile_Capture_vars_t;

nile_Buffer_t *
nile_Capture_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    nile_Capture_vars_t v = *(nile_Capture_vars_t *) nile_Process_vars (p);
    while (!nile_Buffer_is_empty (in)) {
        nile_Real_t r = nile_Buffer_pop_head (in);
        if (*v.n < v.size)
            v.data[*v.n] = nile_Real_tof (r);
        (*v.n)++;
    }
    return out;
}

nile_Process_t *
nile_Capture (nile_Process_t *p, float *data, int *n, int size)
{
    p = nile_Process (p, 1, sizeof (nile_Capture_vars_t),
                      NULL, nile_Capture_body, NULL);
    if (p) {
        nile_Capture_vars_t *vars = nile_Process_vars (p);
        vars->data = data;
        vars->n = n;
        vars->size = size;
    }
    return p;
}

/* Reverse process */

static nile_Buffer_t *
nile_Reverse_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *unused)
{
    nile_Buffer_t *out;
    if (!p->consumer) {
        in->head = in->tail;
        return unused;
    }
    out = nile_Buffer (p);
    if (!out)
        return NULL;
    out->head = out->tail = out->capacity;

    while (!nile_Buffer_is_empty (in)) {
        int q = p->quantum;
        out->head -= q;
        while (q)
            BAT (out, out->head++) = nile_Buffer_pop_head (in);
        out->head -= q;
    }
    nile_Deque_push_head (&p->consumer->input, BUFFER_TO_NODE (out));

    return unused;
}

nile_Process_t *
nile_Reverse (nile_Process_t *p, int quantum)
{
    return nile_Process (p, quantum, 0, NULL, nile_Reverse_body, NULL);
}

/* SortBy process */

typedef struct {
    int          index;
    nile_Deque_t output;
} nile_SortBy_vars_t;

static nile_Buffer_t *
nile_SortBy_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_SortBy_vars_t *vars = nile_Process_vars (p);
    nile_Buffer_t *b = nile_Buffer (p);
    if (!b) 
        return NULL;
    nile_Deque_push_head (&vars->output, BUFFER_TO_NODE (b));
    return out;
}

static nile_Buffer_t *
nile_SortBy_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *unused)
{
    nile_SortBy_vars_t *vars = nile_Process_vars (p); 
    nile_SortBy_vars_t v = *vars; 
    int quantum = p->quantum;

    while (!nile_Buffer_is_empty (in)) {
        int q, j;
        nile_Buffer_t *b;
        nile_Node_t *nd = v.output.head;
        Real key = BAT (in, in->head + v.index);

        /* find the right buffer */
        while (nd->next && 
               nile_Real_nz (nile_Real_geq (key, BAT (NODE_TO_BUFFER (nd->next), v.index))))
            nd = nd->next;

        /* split the buffer if it's full */
        b = NODE_TO_BUFFER (nd);
        if (b->tail > b->capacity - quantum) {
            nile_Buffer_t *b2 = nile_Buffer (p);
            nile_Node_t *nd2 = BUFFER_TO_NODE (b2);
            if (!b2)
                return NULL;
            nd2->next = nd->next;
            nd->next = nd2;
            if (!nd2->next)
                v.output.tail = nd2;
            v.output.n++;
            j = b->tail / quantum / 2 * quantum;
            while (j < b->tail)
                nile_Buffer_push_tail (b2, BAT (b, j++));
            b->tail -= b2->tail;
            if (nile_Real_nz (nile_Real_geq (key, BAT (b2, v.index))))
                b = b2;
        }

        /* insert new element */
        j = b->tail - quantum;
        while (j >= 0 && nile_Real_nz (nile_Real_lt (key, BAT (b, j + v.index)))) {
            int jj = j + quantum;
            q = quantum;
            while (q--)
                BAT (b, jj++) = BAT (b, j++);
            j -= quantum + quantum;
        }
        j += quantum;
        q = quantum;
        while (q--)
            BAT (b, j++) = nile_Buffer_pop_head (in);
        b->tail += quantum;
    }

    *vars = v;
    return unused;
}

static nile_Buffer_t *
nile_SortBy_epilogue (nile_Process_t *p, nile_Buffer_t *unused)
{
    nile_Deque_t output = ((nile_SortBy_vars_t *) nile_Process_vars (p))->output;
    if (nile_Buffer_is_empty (NODE_TO_BUFFER (output.head)))
        nile_Process_free_node (p, nile_Deque_pop_head (&output));
    if (p->consumer)
        p->consumer->input = output;
    else
        p->input = output;
    return unused;
}

nile_Process_t *
nile_SortBy (nile_Process_t *p, int quantum, int index)
{
    p = nile_Process (p, quantum, sizeof (nile_SortBy_vars_t),
                      nile_SortBy_prologue, nile_SortBy_body, nile_SortBy_epilogue);
    if (p) {
        nile_SortBy_vars_t *vars = nile_Process_vars (p);
        vars->index = index;
        vars->output.n = 0;
        vars->output.head = vars->output.tail = NULL;
    }
    return p;
}

/* Zip process */

typedef struct {
    int j;
    int j0;
    int jn;
    nile_Process_t *shared;
    nile_Buffer_t  *out;
} nile_Zip_vars_t;

static nile_Buffer_t *
nile_Zip_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *unused)
{
    nile_Zip_vars_t *vars = nile_Process_vars (p);
    nile_Zip_vars_t v = *vars;
    nile_Process_t *sibling = p->gatee;
    int quantum = p->quantum;
    int squantum = sibling->quantum;
    nile_Deque_t *output = &v.shared->input;
    nile_Buffer_t *out = v.out ? v.out : NODE_TO_BUFFER (output->head);

    while (!nile_Buffer_is_empty (in) && unused->tag == NILE_TAG_NONE) {
        int i = in->head;
        int j = v.j;
        nile_Real_t *idata = &in->data;
        nile_Real_t *odata = &out->data;
        if (quantum == 4 && squantum == 4) {
            int m = (in->tail - i) / 4;
            int o = (v.jn - j) / 8;
            m = m < o ? m : o;
            while (m--) {
                odata[j++] = idata[i++];
                odata[j++] = idata[i++];
                odata[j++] = idata[i++];
                odata[j++] = idata[i++];
                j += 4;
            }
        }
        else {
            int m = (in->tail - i) / quantum;
            int o = (v.jn - j) / (quantum + squantum);
            m = m < o ? m : o;
            while (m--) {
                int q = quantum;
                while (q--)
                    odata[j++] = idata[i++];
                j += squantum;
            }
        }
        in->head = i;
        v.j = j;

        if (v.j == v.jn) {
            nile_Buffer_t *out_ = nile_Buffer (p);
            if (!out_)
                return NULL;
            v.j = v.j0;
            nile_Lock_acq (&v.shared->lock);
                if (output->tail == BUFFER_TO_NODE (out)) {
                    nile_Deque_push_tail (output, BUFFER_TO_NODE (out_));
                    out = out_;
                }
                else
                    nile_Deque_pop_head (output);
            nile_Lock_rel (&v.shared->lock);
            if (out != out_) {
                nile_Process_free_node (p, BUFFER_TO_NODE (out_));
                out->tail = v.jn - v.j0;
                p->consumer = p->consumer ? p->consumer : sibling->consumer;
                nile_Process_enqueue_output (p, out);
                out = NODE_TO_BUFFER (output->head);
                if (p->consumer && p->consumer->input.n >= INPUT_QUOTA &&
                    nile_Process_quota_hit (p->consumer))
                    unused->tag = NILE_TAG_QUOTA_HIT;
            }
        }
    }

    if (unused->tag == NILE_TAG_QUOTA_HIT) {
        p->consumer->producer = p;
        sibling->consumer = NULL;
    }

    v.out = out;
    *vars = v;
    return unused;
}
    
static nile_Buffer_t *
nile_Zip_epilogue (nile_Process_t *p, nile_Buffer_t *unused)
{
    nile_Zip_vars_t v = *(nile_Zip_vars_t *) nile_Process_vars (p);
    nile_Buffer_t *out = v.out ? v.out : NODE_TO_BUFFER (v.shared->input.head);
    nile_Process_t *sibling = p->gatee;
    nile_Thread_t *thread = nile_Process_halting (p, unused);
    int finished_first = 0;

    nile_Lock_acq (&v.shared->lock);
        finished_first = sibling->gatee ? 1 : finished_first;
        p->gatee = NULL;
    nile_Lock_rel (&v.shared->lock);

    if (finished_first)
        return NULL;
    p->heap = thread->private_heap;
    out->tail = v.j - v.j0;
    p->consumer = p->consumer ? p->consumer : sibling->consumer;
    nile_Process_enqueue_output (p, out);
    if (p->consumer)
        p->consumer->producer = p;
    nile_Process_free_node (p, &sibling->node);
    nile_Process_free_node (p, &v.shared->node);
    thread->private_heap = nile_Process_remove (p, thread, p->heap);
    return NULL;
}

static nile_Process_t *
nile_Zip (nile_Process_t *p, int quantum, int j0, int jn, nile_Process_t *shared)
{
    p = nile_Process (p, quantum, sizeof (nile_Zip_vars_t),
                      NULL, nile_Zip_body, nile_Zip_epilogue);
    if (p) {
        nile_Zip_vars_t *vars = nile_Process_vars (p);
        vars->j  = j0;
        vars->j0 = j0;
        vars->jn = jn;
        vars->shared = shared;
        vars->out = NULL;
    }
    return p;
}

/* Dup process */

typedef struct {
    nile_Process_t *p1;
    nile_Process_t *p2;
} nile_Dup_vars_t;

static nile_Buffer_t *
nile_Dup_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    nile_ProcessState_t pstate = -1;
    nile_Dup_vars_t *vars = nile_Process_vars (p);
    nile_Process_t *p1 = vars->p1;
    nile_Process_t *p2 = vars->p2;
    int at_quota = (p->input.n == INPUT_QUOTA);

    if (p->consumer) {
        p1 = vars->p1 = (vars->p1 ? vars->p1 : p->consumer);
        p2 = vars->p2 = (vars->p2 ? vars->p2 : p->consumer);
        p->consumer = NULL;
    }

    nile_Buffer_copy (in, out);
    nile_Lock_acq (&p1->lock);
        nile_Deque_push_tail (&p1->input, BUFFER_TO_NODE (out));
    nile_Lock_rel (&p1->lock);
    out = nile_Buffer (p);
    if (!out)
        return NULL;

    nile_Lock_acq (&p->lock);
        nile_Deque_pop_head (&p->input);
        if (at_quota && p->producer)
            pstate = p->producer->state;
    nile_Lock_rel (&p->lock);
    if (pstate == NILE_BLOCKED_ON_CONSUMER)
        p->heap = nile_Process_schedule (p->producer, p->thread, p->heap);

    nile_Lock_acq (&p2->lock);
        nile_Deque_push_tail (&p2->input, BUFFER_TO_NODE (in));
    nile_Lock_rel (&p2->lock);

    if (p1->input.n >= INPUT_QUOTA && nile_Process_quota_hit (p1)) {
        vars->p1 = NULL;
        p->consumer = p1;
        p1->producer = p;
        p2->producer = p2;
        out->tag = NILE_TAG_QUOTA_HIT;
    }
    else if (p2->input.n >= INPUT_QUOTA && nile_Process_quota_hit (p2)) {
        vars->p2 = NULL;
        p->consumer = p2;
        p1->producer = p1;
        p2->producer = p;
        out->tag = NILE_TAG_QUOTA_HIT;
    }
    return out;
}

static nile_Buffer_t *
nile_Dup_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_Dup_vars_t *vars = nile_Process_vars (p);
    nile_Process_t *p1 = vars->p1;
    nile_Process_t *p2 = vars->p2;
    nile_ProcessState_t p1state;

    if (p->consumer) {
        p1 = vars->p1 = (vars->p1 ? vars->p1 : p->consumer);
        p2 = vars->p2 = (vars->p2 ? vars->p2 : p->consumer);
        p->consumer = NULL;
    }

    nile_Lock_acq (&p1->lock);
        p1->producer = NULL;
        p1state = p1->state;
    nile_Lock_rel (&p1->lock);
    if (p1state == NILE_BLOCKED_ON_PRODUCER)
        p->heap = nile_Process_schedule (p1, p->thread, p->heap);

    p->consumer = p2;
    p2->producer = p;
    return out;
}

static nile_Process_t *
nile_Dup (nile_Process_t *p, int quantum, nile_Process_t *p1, nile_Process_t *p2)
{
    p = nile_Process (p, quantum, sizeof (nile_Dup_vars_t),
                      NULL, nile_Dup_body, nile_Dup_epilogue);
    if (p) {
        nile_Dup_vars_t *vars = nile_Process_vars (p);
        vars->p1 = NULL;
        p->consumer = p1;
        vars->p2 = p2;
    }
    return p;
}

/* DupZip process */

typedef struct {
    nile_Process_t *p1;
    int             p1_out_quantum;
    nile_Process_t *p2;
    int             p2_out_quantum;
} nile_DupZip_vars_t;

static nile_Buffer_t *
nile_DupZip_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_DupZip_vars_t v = *(nile_DupZip_vars_t *) nile_Process_vars (p);
    int out_quantum = v.p1_out_quantum + v.p2_out_quantum;
    int jn = (out->capacity / out_quantum) * out_quantum;
    nile_Process_t *shared = nile_Process (p, 0, 0, NULL, NULL, NULL);
    nile_Process_t *z1 =
        nile_Zip (p, v.p1_out_quantum, 0,          jn             , shared);
    nile_Process_t *z2 =
        nile_Zip (p, v.p2_out_quantum, v.p1_out_quantum, jn + v.p1_out_quantum, shared);
    nile_Process_t *dup = nile_Dup (p, p->quantum,
                                    v.p1 ? nile_Process_pipe (v.p1, z1, NILE_NULL) : z1,
                                    v.p2 ? nile_Process_pipe (v.p2, z2, NILE_NULL) : z2);
    nile_Buffer_t *b = nile_Buffer (p);
    if (!shared || !z1 || !z2 || !dup || !b)
        return NULL;
    nile_Deque_push_tail (&shared->input, BUFFER_TO_NODE (b));
    z1->gatee = z2;
    z2->gatee = z1;
    return nile_Process_swap (p, dup, out);
}

nile_Process_t *
nile_DupZip (nile_Process_t *p,  int quantum,
             nile_Process_t *p1, int p1_out_quantum,
             nile_Process_t *p2, int p2_out_quantum)
{
    p = nile_Process (p, quantum, sizeof (nile_DupZip_vars_t),
                      nile_DupZip_prologue, NULL, NULL);
    if (p) {
        nile_DupZip_vars_t *vars = nile_Process_vars (p);
        vars->p1 = p1;
        vars->p1_out_quantum = p1_out_quantum;
        vars->p2 = p2;
        vars->p2_out_quantum = p2_out_quantum;
    }
    return p;
}

/* Cat Process */

typedef struct {
    int          is_top;
    nile_Deque_t output;
} nile_Cat_vars_t;

static nile_Buffer_t *
nile_Cat_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    nile_Cat_vars_t *vars = (nile_Cat_vars_t *) nile_Process_vars (p);
    nile_Buffer_copy (in, out);
    if (vars->is_top)
        return nile_Process_append_output (p, out);
    else {
        nile_Deque_push_tail (&vars->output, BUFFER_TO_NODE (out));
        return nile_Buffer (p);
    }
}

static nile_Buffer_t *
nile_Cat_epilogue (nile_Process_t *p, nile_Buffer_t *unused)
{
    nile_Cat_vars_t v = *((nile_Cat_vars_t *) nile_Process_vars (p));
    if (v.is_top) {
        nile_ProcessState_t gstate;
        nile_Lock_acq (&p->gatee->lock);
            p->gatee->gatee = NULL; 
            gstate = p->gatee->state;
        nile_Lock_rel (&p->gatee->lock);
        if (gstate == NILE_BLOCKED_ON_GATE)
            p->heap = nile_Process_schedule (p->gatee, p->thread, p->heap);
        return unused;
    }
    else {
        nile_ProcessState_t state;
        nile_Process_halting (p, unused);
        nile_Lock_acq (&p->lock);
            state = p->state = (p->gatee ? NILE_BLOCKED_ON_GATE : p->state);
        nile_Lock_rel (&p->lock);
        if (state == NILE_BLOCKED_ON_GATE)
            return NULL;
        p->input = v.output;
        return nile_Buffer (p); 
    }
}

nile_Process_t *
nile_Cat (nile_Process_t *p, int quantum, int is_top)
{
    p = nile_Process (p, quantum, 0, NULL, nile_Cat_body, nile_Cat_epilogue);
    if (p) {
        nile_Cat_vars_t *vars = (nile_Cat_vars_t *) nile_Process_vars (p);
        vars->is_top = is_top;
        vars->output.n = 0;
        vars->output.head = vars->output.tail = NULL;
    }
    return p;
}

/* DupCat Process */

typedef struct {
    nile_Process_t *p1;
    int             p1_out_quantum;
    nile_Process_t *p2;
    int             p2_out_quantum;
} nile_DupCat_vars_t;

static nile_Buffer_t *
nile_DupCat_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_DupCat_vars_t v = *(nile_DupCat_vars_t *) nile_Process_vars (p);
    nile_Process_t *c1 = nile_Cat (p, v.p1_out_quantum, 1);
    nile_Process_t *c2 = nile_Cat (p, v.p2_out_quantum, 0);
    nile_Process_t *dup = nile_Dup (p, p->quantum,
                                    v.p1 ? nile_Process_pipe (v.p1, c1, NILE_NULL) : c1,
                                    v.p2 ? nile_Process_pipe (v.p2, c2, NILE_NULL) : c2);
    if (!c1 || !c2 || !dup)
        return NULL;
    c1->gatee = c2;
    c2->gatee = c1;
    c2->consumer = p->consumer;
    return nile_Process_swap (p, dup, out);
}

nile_Process_t *
nile_DupCat (nile_Process_t *p,  int quantum,
             nile_Process_t *p1, int p1_out_quantum,
             nile_Process_t *p2, int p2_out_quantum)
{
    p = nile_Process (p, quantum, sizeof (nile_DupCat_vars_t),
                      nile_DupCat_prologue, NULL, NULL);
    if (p) {
        nile_DupCat_vars_t *vars = nile_Process_vars (p);
        vars->p1 = p1;
        vars->p1_out_quantum = p1_out_quantum;
        vars->p2 = p2;
        vars->p2_out_quantum = p2_out_quantum;
    }
    return p;
}

/* Debugging */

/*
static int
nile_Heap_contains (nile_Heap_t h, nile_Block_t *b)
{
    while (h) {
        if (b == h)
            return 1;
        h = h->next;
    }
    return 0;
}
*/

static int
nile_Heap_size (nile_Heap_t h)
{
    int n = 0;
    nile_Block_t *b = h;
    while (b) {
        n += b->i;
        b = b->eoc->next;
    }
    return n;
}

void
nile_print_leaks (nile_Process_t *init)
{
    int i;
    int n = 0;
    nile_Thread_t *t = init->thread;
    nile_Block_t *block = (nile_Block_t *) (t->threads + t->nthreads + 1);
    nile_Block_t *EOB   = (nile_Block_t *) (t->memory + t->nbytes - sizeof (*block) + 1);
    int nblocks = EOB - block; // minus the init block
    t->private_heap = init->heap;
    for (i = 0; i < t->nthreads + 1; i++)
        n += nile_Heap_size (t->threads[i].private_heap) +
             nile_Heap_size (t->threads[i].public_heap);
    if (n != nblocks) {
        fprintf (stderr, "# blocks not in a heap: %d\n", nblocks - n);
        for (; block < EOB; block++) {
            nile_Node_t *nd = (nile_Node_t *) block;
            if (nd == &init->node)
                continue;
            if (nd->type == NILE_BUFFER_TYPE)
                fprintf (stderr, "LEAKED BUFFER : %p\n", nd);
            else if (nd->type == NILE_PROCESS_TYPE)
                fprintf (stderr, "LEAKED PROCESS: %p\n", nd);
        }
    }
    init->heap = t->private_heap;
}
