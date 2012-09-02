typedef enum {
    NILE_NOT_BLOCKED,
    NILE_BLOCKED_ON_PRODUCER,
    NILE_BLOCKED_ON_CONSUMER,
    NILE_BLOCKED_ON_GATE,
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

static nile_Node_t *
nile_Process_alloc_node (nile_Process_t *p)
{
    nile_Chunk_t *c;
    void *v = nile_Heap_pop (&p->heap);
    if (v)
        return (nile_Node_t *) v;
    c = nile_Thread_alloc_chunk (p->thread);
    if (c)
        nile_Heap_push_chunk (&p->heap, c);
    return (nile_Node_t *) nile_Heap_pop (&p->heap);
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
    p = (nile_Process_t *) nile_Process_alloc_node (p);
    if (!p)
        return NULL;
    p->node.type = NILE_PROCESS_TYPE;
    p->node.next = NULL;
    p->thread = NULL;
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
        nile_Thread_t *liaison = gatee->parent->thread;
        nile_Lock_acq (&liaison->lock);
            liaison->ngated++;
        nile_Lock_rel (&liaison->lock);
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
    if (p)
        nile_Funnel_pour (nile_Process_pipe (nile_Funnel (p->parent), p, NILE_NULL), data, n, 1);
}

static int
nile_Process_block_on_producer (nile_Process_t *p)
{
    nile_ProcessState_t pstate = (nile_ProcessState_t ) -1;
    if (!p->producer)
        return 0;
    nile_Lock_acq (&p->lock);
        p->state = NILE_BLOCKED_ON_PRODUCER;
        pstate = p->producer ? p->producer->state : pstate;
    nile_Lock_rel (&p->lock);
    return !(pstate == -1 || pstate == NILE_BLOCKED_ON_CONSUMER);
}

static nile_Heap_t
nile_Process_remove (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap);

static nile_Buffer_t *
nile_Funnel_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out);

static nile_Heap_t
nile_Process_schedule (nile_Process_t *p, nile_Thread_t *thread, nile_Heap_t heap)
{
    if (!p->body)
        return nile_Process_remove (p, thread, heap);
    if (p->body == nile_Funnel_body)
        p->state = NILE_NOT_BLOCKED;
    else if (p->input.n >= INPUT_QUOTA || !nile_Process_block_on_producer (p)) {
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

    if (p->gatee) {
        nile_Thread_t *liaison = &thread->threads[thread->nthreads];
        nile_Lock_acq (&liaison->lock);
            liaison->ngated--;
        nile_Lock_rel (&liaison->lock);
        heap = nile_Process_schedule (p->gatee, thread, heap);
    }
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
    if (b)
        b->head = b->tail = b->capacity;
    return b;
}

static void
nile_Process_activate (nile_Process_t *p, nile_Thread_t *thread)
{
    p->thread = thread;
    p->heap = thread->private_heap;
    thread->private_heap = NULL;
}

static nile_Thread_t *
nile_Process_deactivate (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_Thread_t *thread = p->thread;
    if (out && out->tag != NILE_TAG_OOM)
        nile_Process_enqueue_output (p, out);
    thread->private_heap = p->heap;
    p->thread = NULL;
    p->heap = NULL;
    return thread;
}

nile_Buffer_t *
nile_Process_swap (nile_Process_t *p, nile_Process_t *sub, nile_Buffer_t *out)
{
    nile_Thread_t *thread = nile_Process_deactivate (p, out);
    if (sub) {
        nile_Process_t *consumer = p->consumer;
        p->consumer = NULL;
        nile_Process_pipe (p, sub, consumer, NILE_NULL);
    }
    p->body = NULL;
    if (!nile_Process_block_on_producer (p))
        thread->private_heap = nile_Process_remove (p, thread, thread->private_heap);
    return NULL;
}

static void
nile_Process_handle_backpressure (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_ProcessState_t cstate;
    nile_Process_t *consumer = p->consumer;
    nile_Thread_t *thread = nile_Process_deactivate (p, out);

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
    nile_Thread_t *thread = nile_Process_deactivate (p, out);

    if (nile_Process_block_on_producer (p))
        return;
    else if (p->producer)
        thread->private_heap = nile_Process_schedule (p->producer, thread, thread->private_heap);
    else if (p->input.n)
        thread->private_heap = nile_Process_schedule (p, thread, thread->private_heap);
    else if (p->epilogue) {
        nile_Process_activate (p, thread);
        out = nile_Buffer (p);
        if (!out)
            return (void) nile_Process_deactivate (p, NULL);
        out = p->epilogue (p, out);
        if (!out)
            return;
        thread = nile_Process_deactivate (p, out);
        thread->private_heap = nile_Process_remove (p, thread, thread->private_heap);
    }
    else
        thread->private_heap = nile_Process_remove (p, thread, thread->private_heap);
}

static void
nile_Process_pop_input (nile_Process_t *p)
{
    nile_ProcessState_t pstate = (nile_ProcessState_t) -1;
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
    nile_Process_activate (p, thread);
    out = nile_Buffer (p);
    if (!out)
        return (void) nile_Process_deactivate (p, NULL);
    if (nile_Process_quota_hit (p->consumer))
        out->tag = NILE_TAG_QUOTA_HIT;

    if (p->prologue) {
        out = p->prologue (p, out);
        if (!out)
            return;
        p->prologue = NULL;
    }

    while (p->input.head) {
        out = p->body (p, NODE_TO_BUFFER (p->input.head), out);
        if (!out)
            return;
        nile_Process_pop_input (p);
        if (out->tag == NILE_TAG_OOM)
            return (void) nile_Process_deactivate (p, NULL);
        if (out->tag == NILE_TAG_QUOTA_HIT)
            return nile_Process_handle_backpressure (p, out);
    }
    nile_Process_handle_out_of_input (p, out);
}
