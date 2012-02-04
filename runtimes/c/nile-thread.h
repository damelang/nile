typedef struct nile_Thread_ nile_Thread_t;

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
    int              ngated;
    int              sync;
    nile_Status_t    status;
    nile_OSThread_t  osthread;
} CACHE_ALIGNED;

static void
nile_Thread_work_until_below (nile_Thread_t *liaison, int *var, int value);

static void
nile_Process_run (nile_Process_t *p, nile_Thread_t *thread);

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
    t->ngated = t->sync = 0;
    t->status = NILE_STATUS_OK;
}

static void *
nile_Thread_steal (nile_Thread_t *t, void *(*action) (nile_Thread_t *))
{
    int i;
    int j = t->index + t->nthreads;
    void *v;
    nile_Thread_t *victim;

    if (t->status != NILE_STATUS_OK)
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
    if (c || t->status != NILE_STATUS_OK)
        return c;
    c = nile_Thread_steal (t, nile_Thread_steal_from_heap);
    if (!c)
        for (i = 0; i < t->nthreads + 1; i++)
            t->threads[i].status = NILE_STATUS_OUT_OF_MEMORY;
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
    } while (p && t->status == NILE_STATUS_OK);
}

static void *
nile_Thread_main (void *arg)
{
    nile_Thread_t *t = arg;
    nile_Process_t *p;
    const int MIN_PAUSES =    1000;
    const int MAX_PAUSES = 1000000;
    int npauses = MIN_PAUSES;

    while (t->status == NILE_STATUS_OK) {
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
            nile_Sleep_doze (1000);
        else
            nile_Process_run (p, worker);
    } while (worker->status == NILE_STATUS_OK && *var >= value);

    nile_Thread_transfer_heaps (worker, liaison);
}
