#include <stddef.h>
#include <stdarg.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#include "nile-platform.h"
#include "nile-heap.h"
#include "nile-deque.h"
#define DEBUG
#include "test/nile-debug.h"

#define INPUT_QUOTA 5
#define Real nile_Real_t
#define BAT(b, i) ((&b->data)[i])

typedef struct nile_Thread_ nile_Thread_t;

static nile_Heap_t
nile_Thread_work_until_below (nile_Thread_t *liaison, nile_Heap_t h, int *var, int value);

static nile_Heap_t
nile_Process_run (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap);

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
    nile_Heap_t      heap;
    nile_Deque_t     q;
    int              id;
    nile_Thread_t   *threads;
    int              nthreads;
    nile_Sleep_t    *sleep;
    char            *memory;
    int              sync;
    int              abort;
    nile_OSThread_t  osthread;
} CACHE_ALIGNED;

static void
nile_Thread (int id, nile_Thread_t *threads, int nthreads,
             nile_Sleep_t *sleep, char *memory)
{
    nile_Thread_t *t = &threads[id];
    t->lock = 0;
    t->heap = NULL;
    t->q.n = 0;
    t->q.head = t->q.tail = NULL;
    t->id = id;
    t->threads = threads;
    t->nthreads = nthreads;
    t->sleep = sleep;
    t->memory = memory;
    t->sync = t->abort = 0;
}

static void *
nile_Thread_steal (nile_Thread_t *t, void *(*action) (nile_Thread_t *, nile_Thread_t *))
{
    int i;
    int j = t->id + t->nthreads;
    void *v;
    nile_Thread_t *victim;
    if (t->abort)
        return 0;
    for (i = 1; i < t->nthreads; i++) {
        j += ((i % 2) ^ (t->id % 2) ? i : -i);
        victim = &t->threads[j % t->nthreads];
        if ((v = action (t, victim)))
            return v;
    }
    return action (t, &t->threads[t->nthreads]);
}

static void *
nile_Thread_steal_from_heap (nile_Thread_t *t, nile_Thread_t *victim)
{
    nile_Chunk_t *c = NULL;
    if (victim->heap) {
        nile_Lock_acq (&victim->lock);
            c = nile_Heap_pop_chunk (&victim->heap);
        nile_Lock_rel (&victim->lock);
    }
    return c;
}

static void *
nile_Thread_steal_from_q (nile_Thread_t *t, nile_Thread_t *victim)
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

static void
nile_Thread_prefix_to_q (nile_Thread_t *t, nile_Process_t *p)
{
    nile_Lock_acq (&t->lock);
        nile_Deque_push_head (&t->q, (nile_Node_t *) p);
    nile_Lock_rel (&t->lock);
    nile_Sleep_issue_wakeup (t->sleep);
}

static nile_Chunk_t *
nile_Thread_alloc_chunk (nile_Thread_t *t)
{
    int i;
    nile_Chunk_t *c;
    nile_Lock_acq (&t->lock);
        c = nile_Heap_pop_chunk (&t->heap);
    nile_Lock_rel (&t->lock);
    if (c || t->abort)
        return c;
    c = nile_Thread_steal (t, nile_Thread_steal_from_heap);
    if (c)
        return c;
    for (i = 0; i < t->nthreads + 1; i++)
        t->threads[i].abort = 1;
    return c;
}

static void
nile_Thread_free_chunk (nile_Thread_t *t, nile_Chunk_t *c)
{
    nile_Lock_acq (&t->lock);
        nile_Heap_push_chunk (&t->heap, c);
    nile_Lock_rel (&t->lock);
}

static nile_Heap_t
nile_Thread_work (nile_Thread_t *t, nile_Process_t *p, nile_Heap_t h)
{
    do {
        h = nile_Process_run (p, t, h);
        nile_Lock_acq (&t->lock);
            p = (nile_Process_t *) nile_Deque_pop_tail (&t->q);
        nile_Lock_rel (&t->lock);
    } while (p && !t->abort);
    return h;
}

static void *
nile_Thread_main (void *arg)
{
    nile_Thread_t *t = arg;
    nile_Process_t *p;
    nile_Heap_t h = NULL;
    const int MIN_PAUSES =    1000;
    const int MAX_PAUSES = 1000000;
    int npauses = MIN_PAUSES;
    while (!t->abort) {
        if ((p = nile_Thread_steal (t, nile_Thread_steal_from_q))) {
            h = nile_Thread_work (t, p, h);
            npauses = MIN_PAUSES;
        }
        else if (t->sync || npauses > MAX_PAUSES) {
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

static nile_Heap_t
nile_Thread_work_until_below (nile_Thread_t *liaison, nile_Heap_t h, int *var, int value)
{
    nile_Process_t *p;
    nile_Thread_t *worker = &liaison->threads[0];

    nile_Lock_acq (&liaison->lock);
        worker->heap = liaison->heap;
        liaison->heap = NULL;
    nile_Lock_rel (&liaison->lock);

    while (!worker->abort && *var >= value)
       if ((p = nile_Thread_steal (worker, nile_Thread_steal_from_q)))
            h = nile_Thread_work (worker, p, h);
       else
           nile_Sleep_doze (1000);

    nile_Lock_acq (&worker->lock);
        liaison->heap = worker->heap;
        worker->heap = NULL;
    nile_Lock_rel (&worker->lock);

    return h;
}

/* Stream buffers */

#define BUFFER_TO_NODE(b) (((nile_Node_t   *)  b) - 1)
#define NODE_TO_BUFFER(n) ( (nile_Buffer_t *) (n + 1))

INLINE nile_Buffer_t *
nile_Buffer (nile_Node_t *nd)
{
    nile_Buffer_t *b = NODE_TO_BUFFER (nd);
    if (!nd)
        return NULL;
    b->head = b->tail = b->tag = 0;
    b->capacity = (sizeof (nile_Block_t) - sizeof (*nd) - sizeof (*b)) / sizeof (Real) + 1;
    return b;
}

/* Processes */

typedef enum {
    NILE_BLOCKED_ON_GATE,
    NILE_BLOCKED_ON_PRODUCER,
    NILE_BLOCKED_ON_CONSUMER,
    NILE_READY,
    NILE_RUNNING,
    NILE_SWAPPED
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
};

static void *
nile_Process_alloc_block (nile_Process_t *p)
{
    nile_Chunk_t *c;
    void *v = nile_Heap_pop (&p->heap);
    if (v)
        return v;
    c = nile_Thread_alloc_chunk (p->thread);
    if (!c)
        return NULL;
    nile_Heap_push_chunk (&p->heap, c);
    return nile_Heap_pop (&p->heap);
}

static void
nile_Process_free_block (nile_Process_t *p, void *v)
{
    if (nile_Heap_push (&p->heap, v))
        nile_Thread_free_chunk (p->thread, nile_Heap_pop_chunk (&p->heap));
}

static nile_Buffer_t *
nile_Process_default_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
    { return nile_Process_swap (p, 0, out); }

nile_Process_t *
nile_Process (nile_Process_t *p, int quantum, int sizeof_vars,
              nile_Process_logue_t prologue,
              nile_Process_body_t  body,
              nile_Process_logue_t epilogue)
{
    nile_Process_t *q = nile_Process_alloc_block (p);
    if (q) {
        q->node.next = NULL;
        q->thread = p->thread;
        q->lock = 0;
        q->heap = NULL;
        q->input.head = q->input.tail = NULL;
        q->input.n = 0;
        q->quantum = quantum;
        q->sizeof_vars = sizeof_vars;
        q->prologue = prologue;
        q->body = body ? body : nile_Process_default_body;
        q->epilogue = epilogue;
        q->state = NILE_BLOCKED_ON_PRODUCER;
        q->producer = q;
        q->consumer = q->gatee = NULL;
    }
    return q;
}

/*
nile_Process_t *
nile_Process_clone (nile_Process_t *p)
{
    char *vars = nile_Process_vars (p);
    p = nile_Process (p, p->quantum, p->sizeof_vars, p->prologue, p->body, p->epilogue);
    if (p) {
        int i;
        char *cvars = nile_Process_vars (p);
        for (i = 0; i < p->sizeof_vars; i++)
            cvars[i] = vars[i];
    }
    return p;
}
*/

void *
nile_Process_vars (nile_Process_t *p)
    { return (void *) (p + 1); }

nile_Process_t *
nile_Process_gate (nile_Process_t *gater, nile_Process_t *gatee)
{
    if (!gater || !gatee)
        return NULL;
    gater->gatee = gatee;
    gatee->state = NILE_BLOCKED_ON_GATE;
    return gater;
}

static void
nile_Process_ungate (nile_Process_t *gatee, nile_Thread_t *thread)
{
    int state = NILE_BLOCKED_ON_GATE;
    nile_Lock_acq (&gatee->lock);
        if (gatee->input.n < INPUT_QUOTA && gatee->producer)
            state = gatee->state = NILE_BLOCKED_ON_PRODUCER;
        else
            state = gatee->state = NILE_READY;
    nile_Lock_rel (&gatee->lock);
    if (state == NILE_READY)
        nile_Thread_prefix_to_q (thread, gatee);
}

nile_Process_t *
nile_Process_pipe_v (nile_Process_t **ps, int n)
{
    int i;
    nile_Process_t *pi, *pj;
    if (!n)
        return NILE_NULL;
    pi = ps[0];
    for (i = 1; i < n; i++) {
        pj = ps[i];
        pi->consumer = pj;
        pj->producer = pi;
        while (pj->consumer)
            pj = pj->consumer;
        pi = pj;
    }
    return ps[0];
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

static nile_Heap_t
nile_Process_remove (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap)
{
    int cstate;
    nile_Process_t *producer = p->producer;
    nile_Process_t *consumer = p->consumer;
    nile_Deque_t    input    = p->input;

    if (p->gatee)
        nile_Process_ungate (p->gatee, thread);
    if (!consumer && input.n) {
        p->thread = thread;
        p->heap = heap;
        while (input.n)
            nile_Process_free_block (p, nile_Deque_pop_head (&input));
        heap = p->heap;
    }
    if (producer)
        producer->consumer = consumer;
    if (!consumer) {
        if (nile_Heap_push (&heap, p))
            nile_Thread_free_chunk (thread, nile_Heap_pop_chunk (&heap));
        if (producer && producer->state == NILE_BLOCKED_ON_CONSUMER)
            return nile_Process_run (producer, thread, heap);
        return heap;
    }
    nile_Lock_acq (&consumer->lock);
        consumer->producer = producer;
        while (input.n)
            nile_Deque_push_tail (&consumer->input, nile_Deque_pop_head (&input));
        cstate = consumer->state;
    nile_Lock_rel (&consumer->lock);
    if (nile_Heap_push (&heap, p))
        nile_Thread_free_chunk (thread, nile_Heap_pop_chunk (&heap));
    if (cstate == NILE_SWAPPED)
        return nile_Process_remove (consumer, thread, heap);
    if (cstate == NILE_BLOCKED_ON_PRODUCER &&
        (!producer || producer->state == NILE_BLOCKED_ON_CONSUMER))
        return nile_Process_run (consumer, thread, heap);
    return heap;
}

static void
nile_Process_enqueue_output (nile_Process_t *producer, nile_Buffer_t *out)
{
    nile_Node_t *nd = BUFFER_TO_NODE (out);
    nile_Process_t *consumer = producer->consumer;
    if (!consumer || nile_Buffer_is_empty (out))
        nile_Process_free_block (producer, nd);
    else {
        nile_Lock_acq (&consumer->lock);
            nile_Deque_push_tail (&consumer->input, nd);
        nile_Lock_rel (&consumer->lock);
    }
}

nile_Buffer_t *
nile_Process_append_output (nile_Process_t *producer, nile_Buffer_t *out)
{
    nile_Buffer_t *b = nile_Buffer (nile_Process_alloc_block (producer));
    if (!b) {
        out->tag = NILE_TAG_OOM;
        out->head = out->tail = 0;
        return out;
    }
    if (out->tag != NILE_TAG_OOM)
        nile_Process_enqueue_output (producer, out);
    if (producer->consumer) {
        int n = producer->consumer->input.n;
        int cstate = producer->consumer->state;
        if ((n >= INPUT_QUOTA - 1 && cstate == NILE_BLOCKED_ON_PRODUCER) ||
            n > 2 * INPUT_QUOTA)
            b->tag = NILE_TAG_QUOTA_HIT;
    }
    return b;
}

nile_Buffer_t *
nile_Process_prefix_input (nile_Process_t *producer, nile_Buffer_t *in)
{
    nile_Buffer_t *b = nile_Buffer (nile_Process_alloc_block (producer));
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

nile_Buffer_t *
nile_Process_swap (nile_Process_t *p, nile_Process_t *sub, nile_Buffer_t *out)
{
    if (out->tag == NILE_TAG_OOM)
        return out;
    nile_Process_enqueue_output (p, out);
    if (sub) {
        nile_Process_t *end = sub;
        while (end->consumer)
            end = end->consumer;
        if (p->consumer)
            p->consumer->producer = end;
        end->consumer = p->consumer;
        end->gatee = p->gatee;
        sub->producer = p;
        p->consumer = sub;
    }
    else if (p->gatee)
        nile_Process_ungate (p->gatee, p->thread);
    p->gatee = NULL;
    return NULL;
}

static nile_Heap_t
nile_Process_finish_swap (nile_Process_t *p)
{
    nile_Heap_t heap = p->heap;
    int pstate = -1;

    nile_Lock_acq (&p->lock);
        pstate = p->producer ? p->producer->state : pstate;
        p->state = NILE_SWAPPED;
    nile_Lock_rel (&p->lock);

    if (pstate == -1 || pstate == NILE_BLOCKED_ON_CONSUMER)
        return nile_Process_remove (p, p->thread, p->heap);
    return heap;
}

static nile_Heap_t
nile_Process_backpressure (nile_Process_t *p, nile_Buffer_t *out)
{
    int state, cstate;
    nile_Process_t *consumer = p->consumer;
    nile_Heap_t heap = p->heap;

    nile_Lock_acq (&consumer->lock);
        nile_Deque_push_tail (&consumer->input, BUFFER_TO_NODE (out));
        if (consumer->input.n >= INPUT_QUOTA)
            p->state = NILE_BLOCKED_ON_CONSUMER;
        state = p->state;
        cstate = consumer->state;
    nile_Lock_rel (&consumer->lock);

    if (state != NILE_BLOCKED_ON_CONSUMER)
        return nile_Process_run (p, p->thread, p->heap);
    if (cstate == NILE_SWAPPED)
        return nile_Process_remove (consumer, p->thread, p->heap);   
    if (cstate == NILE_BLOCKED_ON_PRODUCER) {
        nile_Thread_t *thread = p->thread;
        consumer->state = NILE_READY;
        if (p->input.n >= INPUT_QUOTA) {
            p->state = NILE_READY;
            nile_Thread_append_to_q (thread, p);
        }
        return nile_Process_run (consumer, thread, heap);
    }
    return heap;
}

static nile_Heap_t
nile_Process_out_of_input (nile_Process_t *p, nile_Buffer_t *out)
{
    int state;
    int pstate = -1;
    nile_Heap_t heap;

    nile_Process_enqueue_output (p, out);
    heap = p->heap;
    nile_Lock_acq (&p->lock);
        if (p->input.n < INPUT_QUOTA)
            p->state = NILE_BLOCKED_ON_PRODUCER;
        state = p->state;
        pstate = p->producer ? p->producer->state : pstate;
    nile_Lock_rel (&p->lock);

    if (state != NILE_BLOCKED_ON_PRODUCER || (pstate == -1 && p->input.n))
        return nile_Process_run (p, p->thread, p->heap);
    if (pstate == -1) {
        if (p->epilogue) {
            nile_Buffer_t b;
            b.tag = NILE_TAG_OOM;
            out = p->epilogue (p, nile_Process_append_output (p, &b));
            if (!out)
                return nile_Process_finish_swap (p);
            if (out->tag == NILE_TAG_OOM)
                return NULL;
            nile_Process_enqueue_output (p, out);
        }
        return nile_Process_remove (p, p->thread, p->heap);
    }
    return heap; 
}

static void
nile_Process_check_on_producer (nile_Process_t *p)
{
    int pstate = -1;
    nile_Lock_acq (&p->lock);
        pstate = p->producer ? p->producer->state : pstate;
    nile_Lock_rel (&p->lock);
    if (pstate == NILE_BLOCKED_ON_CONSUMER) {
        nile_Process_t *producer = p->producer;
        nile_Lock_acq (&producer->lock);
            if (producer->producer && producer->input.n < INPUT_QUOTA)
                pstate = producer->state = NILE_BLOCKED_ON_PRODUCER;
        nile_Lock_rel (&producer->lock);
        if (pstate == NILE_BLOCKED_ON_CONSUMER) {
            producer->state = NILE_READY;
            nile_Thread_append_to_q (p->thread, producer);
        }
    }
}

static nile_Heap_t
nile_Process_run (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap)
{
    nile_Node_t *head;
    nile_Buffer_t *out;
    nile_Buffer_t b;

    p->thread = thread;
    p->heap = heap;
    p->state = NILE_RUNNING;
    b.tag = NILE_TAG_OOM;
    out = nile_Process_append_output (p, &b);

    if (p->prologue) {
        out = p->prologue (p, out);
        if (!out)
            return nile_Process_finish_swap (p);
        p->prologue = NULL;
    }

    head = p->input.head;
    while (head) {
        if (nile_Buffer_quota_hit (out))
            return nile_Process_backpressure (p, out);
        out = p->body (p, NODE_TO_BUFFER (head), out);
        if (!out)
            return nile_Process_finish_swap (p);
        if (out->tag == NILE_TAG_OOM)
            return NULL;
        if (nile_Buffer_is_empty (NODE_TO_BUFFER (p->input.head))) {
            if (p->input.n == INPUT_QUOTA)
                nile_Process_check_on_producer (p);
            nile_Lock_acq (&p->lock);
                head = nile_Deque_pop_head (&p->input);
            nile_Lock_rel (&p->lock);
            nile_Process_free_block (p, head);
        }
        head = p->input.head;
    }
    return nile_Process_out_of_input (p, out);
}

/* Runtime maintenance */

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
        nile_Thread (i, threads, nthreads, sleep, memory);

    block = (nile_Block_t *) (threads + nthreads + 1);
    EOB   = (nile_Block_t *) (memory + nbytes - sizeof (*block) + 1);
    while (block < EOB)
        for (i = 1; i < nthreads + 1 && block < EOB; i++, block++)
            nile_Heap_push (&threads[i].heap, block);

    for (i = 1; i < nthreads; i++)
        nile_OSThread_spawn (&threads[i].osthread, nile_Thread_main, &threads[i]);

    boot.heap = NULL;
    boot.thread = &threads[nthreads];
    init = nile_Process (&boot, 0, 0, 0, 0, 0);
    if (init)
        init->heap = boot.heap;
    return init;
}

int
nile_sync (nile_Process_t *init)
{
    int i;
    nile_Thread_t *liaison = init->thread;
    nile_Thread_t *worker = &liaison->threads[0];
    nile_Process_t *p;

    for (i = 1; i < liaison->nthreads; i++)
        liaison->threads[i].sync = 1;

    nile_Lock_acq (&liaison->lock);
        worker->heap = liaison->heap;
        liaison->heap = NULL;
    nile_Lock_rel (&liaison->lock);

    while (!worker->abort &&
           (p = nile_Thread_steal (worker, nile_Thread_steal_from_q)))
            init->heap = nile_Thread_work (worker, p, init->heap);

    nile_Lock_acq (&worker->lock);
        liaison->heap = worker->heap;
        worker->heap = NULL;
    nile_Lock_rel (&worker->lock);

    nile_Sleep_wait_for_quiecent (liaison->sleep);
    for (i = 1; i < liaison->nthreads; i++)
        liaison->threads[i].sync = 0;

    return liaison->abort;
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
    { return nile_Process (p, quantum, 0, 0, 0, 0); }

/* Funnel process */

nile_Process_t *
nile_Funnel (nile_Process_t *init, int quantum)
{
    nile_Process_t *p = nile_Process (init, quantum, 0, 0, 0, 0);
    if (p) {
        nile_Process_t **init_ = nile_Process_vars (p);
        *init_ = init;
    }
    return p;
}

void
nile_Funnel_pour (nile_Process_t *p, float *data, int n, int EOS)
{
    int i, m, q, cstate;
    nile_Process_t *init, *consumer;
    nile_Thread_t *liaison;
    nile_Buffer_t *out;
    nile_Buffer_t b;
    b.tag = NILE_TAG_OOM;
    if (!p)
        return;
    liaison = p->thread;
    init = *(nile_Process_t **) nile_Process_vars (p);
    if (liaison->q.n > 4 * liaison->nthreads)
        init->heap = nile_Thread_work_until_below (liaison, init->heap, &liaison->q.n, 2 * liaison->nthreads);
    p->heap = init->heap;
    out = nile_Process_append_output (p, &b);
    i = 0;
    m = (out->capacity / p->quantum) * p->quantum;
    for (;;) {
        if (out->tag == NILE_TAG_OOM)
            return;
        if (out->tag == NILE_TAG_QUOTA_HIT) {
            if (p->consumer->state == NILE_SWAPPED)
                p->heap = nile_Process_remove (p->consumer, liaison, p->heap);
            else if (p->consumer->state == NILE_BLOCKED_ON_PRODUCER) {
                p->consumer->state = NILE_READY;
                nile_Thread_append_to_q (liaison, p->consumer);
            }
            else if (p->consumer->input.n > 4 * INPUT_QUOTA)
                p->heap = nile_Thread_work_until_below (liaison, p->heap, &p->consumer->input.n, 4 * INPUT_QUOTA);
        }
        q = (m < n - i) ? m : n - i;
        while (q--)
            nile_Buffer_push_tail (out, nile_Real (data[i++]));
        if (i == n || !p->consumer)
            break;
        out = nile_Process_append_output (p, out);
    }
    nile_Process_enqueue_output (p, out);
    init->heap = p->heap;
    if (!EOS)
        return;
    consumer = p->consumer;
    if (!consumer) {
        nile_Process_free_block (init, p);
        return;
    }
    nile_Lock_acq (&consumer->lock);
        consumer->producer = NULL;
        cstate = consumer->state;
    nile_Lock_rel (&consumer->lock);
    nile_Process_free_block (init, p);
    if (cstate == NILE_SWAPPED)
        init->heap = nile_Process_remove (consumer, liaison, init->heap);
    else if (cstate == NILE_BLOCKED_ON_PRODUCER) {
        consumer->state = NILE_READY;
        nile_Thread_append_to_q (liaison, consumer);
    }
}

/* SortBy process */

typedef struct {
    int            index;
    nile_Buffer_t *bs;
    int            n;
} nile_SortBy_vars_t;

nile_Buffer_t *
nile_SortBy_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_SortBy_vars_t *vars = nile_Process_vars (p); 
    vars->bs = nile_Buffer (nile_Process_alloc_block (p));
    vars->n = 1;
    if (!vars->bs)
        out->tag = NILE_TAG_OOM;
    else
        BUFFER_TO_NODE (vars->bs)->next = NULL;
    return out;
}

nile_Buffer_t *
nile_SortBy_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *unused)
{
    nile_SortBy_vars_t *vars = nile_Process_vars (p); 
    nile_SortBy_vars_t v = *vars; 
    int quantum = p->quantum;

    while (!nile_Buffer_is_empty (in)) {
        int q, j;
        nile_Buffer_t *b;
        nile_Node_t *nd = BUFFER_TO_NODE (v.bs);
        Real key = BAT (in, in->head + v.index);

        /* find the right buffer */
        while (nd->next && 
               nile_Real_nz (nile_Real_geq (key, BAT (NODE_TO_BUFFER (nd->next), v.index))))
            nd = nd->next;

        /* split the buffer if it's full */
        b = NODE_TO_BUFFER (nd);
        if (b->tail > b->capacity - quantum) {
            nile_Buffer_t *b2 = nile_Buffer (nile_Process_alloc_block (p));
            if (!b2) {
                unused->tag = NILE_TAG_OOM;
                return unused;
            }
            BUFFER_TO_NODE (b2)->next = nd->next;
            nd->next = BUFFER_TO_NODE (b2);
            v.n++;
            j = b->tail / quantum / 2 * quantum;
            while (j < b->tail)
                BAT (b2, b2->tail++) = BAT (b, j++);
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
            BAT (b, j++) = BAT (in, in->head++);
        b->tail += quantum;
    }

    *vars = v;
    return unused;
}

nile_Buffer_t *
nile_SortBy_epilogue (nile_Process_t *p, nile_Buffer_t *unused)
{
    nile_SortBy_vars_t v = *(nile_SortBy_vars_t *) nile_Process_vars (p);
    nile_Node_t *head = v.n ? BUFFER_TO_NODE (v.bs) : NULL;
    if (p->consumer) {
        p->consumer->input.head = head;
        p->consumer->input.n = v.n;
    }
    else {
        nile_Node_t *next;
        for (; head; head = next) {
            next = head->next;
            nile_Process_free_block (p, head);
        }
    }
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
    }
    return p;
}

nile_Process_t *
nile_DupZip (nile_Process_t *p,
             nile_Process_t *p1, int quantum1,
             nile_Process_t *p2, int quantum2)
{
    // TODO
    return nile_Identity (p, 1);
}
