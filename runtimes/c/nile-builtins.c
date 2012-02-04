/* Identity process */

nile_Process_t *
nile_Identity (nile_Process_t *p, int quantum)
    { return nile_Process (p, quantum, 0, NULL, NULL, NULL); }

/* Funnel process */

typedef struct {
    int   *i;
    float *data;
    int    n;
} nile_Funnel_vars_t;

static nile_Buffer_t *
nile_Funnel_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    nile_Process_prefix_input (p, NULL);
    return out;
}

static nile_Buffer_t *
nile_Funnel_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    nile_Funnel_vars_t *vars = nile_Process_vars (p);
    nile_Funnel_vars_t v = *vars;
    int quantum = p->consumer ? p->consumer->quantum : p->quantum;
    int m = (out->capacity / quantum) * quantum;
    int i = *(v.i);

    while (i < v.n && !nile_Buffer_quota_hit (out)) {
        int q = v.n - i;
        q = m < q ? m : q;
        while (q--)
            nile_Buffer_push_tail (out, nile_Real (v.data[i++]));
        if (i < v.n)
            out = nile_Process_append_output (p, out);
    }
    *(vars->i) = i;
    if (i == v.n)
        out->tag = NILE_TAG_NONE;
    return out;
}

nile_Process_t *
nile_Funnel (nile_Process_t *init)
    { return nile_Process (init, 1, 0, NULL, nile_Funnel_body, NULL); }

void
nile_Funnel_pour (nile_Process_t *p, float *data, int n, int EOS)
{
    nile_Funnel_vars_t *vars = nile_Process_vars (p);
    nile_Process_t *init;
    nile_Thread_t *liaison;
    int i = 0;
    if (!p)
        return;
    init = p->parent;
    liaison = nile_Process_deactivate (init, NULL);
    if (liaison->ngated > 4 * liaison->nthreads)
        nile_Thread_work_until_below (liaison, &liaison->ngated, 2 * liaison->nthreads);
    if (liaison->q.n > 4 * liaison->nthreads)
        nile_Thread_work_until_below (liaison, &liaison->q.n, 2 * liaison->nthreads);
    vars->i = &i;
    vars->data = data;
    vars->n = n;
    p->producer = EOS ? NULL : p->producer;
    for (;;) {
        p->prologue = nile_Funnel_prologue;
        nile_Process_run (p, liaison);
        if (i == n || liaison->status != NILE_STATUS_OK)
            break;
        if (p->consumer->input.n > INPUT_MAX)
            nile_Thread_work_until_below (liaison, (int *)&p->state, NILE_BLOCKED_ON_CONSUMER);
    }
    nile_Process_activate (init, liaison);
}

/* Capture process */

typedef struct {
    float *data;
    int   *n;
    int    size;
} nile_Capture_vars_t;

static nile_Buffer_t *
nile_Capture_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    nile_Capture_vars_t *vars = nile_Process_vars (p);
    nile_Capture_vars_t v = *vars;
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
    nile_Buffer_t *out = nile_Buffer (p);
    if (!out)
        return nile_Process_deactivate (p, NULL), NULL;
    out->head = out->tail = out->capacity;

    while (!nile_Buffer_is_empty (in)) {
        int q      = p->quantum;
        out->head -= p->quantum;
        while (q--)
            BAT (out, out->head++) = nile_Buffer_pop_head (in);
        out->head -= p->quantum;
    }
    if (p->consumer)
        nile_Deque_push_head (&p->consumer->input, BUFFER_TO_NODE (out));
    else
        nile_Process_free_node (p, BUFFER_TO_NODE (out));

    unused->tag = NILE_TAG_NONE;
    return unused;
}

nile_Process_t *
nile_Reverse (nile_Process_t *p, int quantum)
{
    return nile_Process (p, quantum, 0, NULL, nile_Reverse_body, NULL);
}

/* SortBy process */

typedef struct {
    int index;
} nile_SortBy_vars_t;

static nile_Buffer_t *
nile_SortBy_split_buffer (nile_Buffer_t *b1, nile_Buffer_t *b2, int quantum, int index, nile_Deque_t *output, nile_Real_t key)
{
    int i;
    nile_Node_t *nd1 = BUFFER_TO_NODE (b1);
    nile_Node_t *nd2 = BUFFER_TO_NODE (b2);
    if (!b2)
        return NULL;
    if (output->tail == nd1)
        output->tail = nd2;
    nd2->next = nd1->next;
    nd1->next = nd2;
    output->n++;
    i = b1->tail / quantum / 2 * quantum;
    while (i < b1->tail)
        nile_Buffer_push_tail (b2, BAT (b1, i++));
    b1->tail -= b2->tail;
    if (nile_Real_nz (nile_Real_geq (key, BAT (b2, index))))
        return b2;
    else
        return b1;
}

static nile_Buffer_t *
nile_SortBy_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *unused)
{
    nile_SortBy_vars_t *vars = nile_Process_vars (p); 
    nile_SortBy_vars_t v = *vars; 
    int quantum = p->quantum;
    nile_Deque_t *output;

    if (!p->consumer) {
        in->head = in->tail;
        return unused;
    }
    output = &p->consumer->input;
    if (!output->n) {
        nile_Buffer_t *b = nile_Buffer (p);
        if (!b)
            return nile_Process_deactivate (p, NULL), NULL;
        nile_Deque_push_head (output, BUFFER_TO_NODE (b));
    }

    while (!nile_Buffer_is_empty (in)) {
        int q, j;
        nile_Buffer_t *b;
        nile_Node_t *nd = output->head;
        nile_Real_t key = BAT (in, in->head + v.index);

        /* find the right buffer */
        while (nd->next && 
               nile_Real_nz (nile_Real_geq (key, BAT (NODE_TO_BUFFER (nd->next), v.index))))
            nd = nd->next;

        /* split the buffer if it's full */
        b = NODE_TO_BUFFER (nd);
        if (nile_Buffer_tailroom (b) < quantum) {
            b = nile_SortBy_split_buffer (b, nile_Buffer (p), quantum, v.index, output, key);
            if (!b)
                return nile_Process_deactivate (p, NULL), NULL;
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
    unused->tag = NILE_TAG_NONE;
    return unused;
}

nile_Process_t *
nile_SortBy (nile_Process_t *p, int quantum, int index)
{
    p = nile_Process (p, quantum, sizeof (nile_SortBy_vars_t),
                      NULL, nile_SortBy_body, NULL);
    if (p) {
        nile_SortBy_vars_t *vars = nile_Process_vars (p);
        vars->index = index;
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

    unused->tag = NILE_TAG_NONE;
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
                return nile_Process_deactivate (p, NULL), NULL;
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
                if (nile_Process_quota_hit (p->consumer))
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
    nile_Thread_t *thread = nile_Process_deactivate (p, unused);
    int finished_first;

    nile_Lock_acq (&v.shared->lock);
        finished_first = !!sibling->gatee;
        p->gatee = NULL;
    nile_Lock_rel (&v.shared->lock);

    if (finished_first)
        return NULL;
    nile_Process_activate (p, thread);
    p->consumer = p->consumer ? p->consumer : sibling->consumer;
    if (p->consumer)
        p->consumer->producer = p;
    nile_Process_free_node (p, &sibling->node);
    nile_Process_free_node (p, &v.shared->node);
    out->tail = v.j - v.j0;
    return out;
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
        return nile_Process_deactivate (p, NULL), NULL;

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

    if (nile_Process_quota_hit (p1) || nile_Process_quota_hit (p2)) {
        if (p1->input.n > p2->input.n) {
            vars->p1 = NULL;
            p->consumer = p1;
            p1->producer = p;
            p2->producer = p2;
            out->tag = NILE_TAG_QUOTA_HIT;
        }
        else {
            vars->p2 = NULL;
            p->consumer = p2;
            p1->producer = p1;
            p2->producer = p;
            out->tag = NILE_TAG_QUOTA_HIT;
        }
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
        return nile_Process_deactivate (p, NULL), NULL;
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
    nile_Cat_vars_t *vars = nile_Process_vars (p);
    nile_Buffer_copy (in, out);
    in->head = in->tail;
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
    nile_Cat_vars_t *vars = nile_Process_vars (p);
    nile_Cat_vars_t v = *vars;
    if (v.is_top) {
        nile_ProcessState_t gstate;
        if (p->consumer)
            p->consumer->producer = p->gatee;
        nile_Lock_acq (&p->gatee->lock);
            p->gatee->gatee = NULL; 
            gstate = p->gatee->state;
        nile_Lock_rel (&p->gatee->lock);
        if (gstate == NILE_BLOCKED_ON_GATE)
            p->heap = nile_Process_schedule (p->gatee, p->thread, p->heap);
        p->consumer = NULL;
        p->gatee = NULL;
        return unused;
    }
    else {
        nile_ProcessState_t state;
        nile_Thread_t *thread = nile_Process_deactivate (p, unused);
        nile_Lock_acq (&p->lock);
            state = p->state = (p->gatee ? NILE_BLOCKED_ON_GATE : p->state);
        nile_Lock_rel (&p->lock);
        if (state == NILE_BLOCKED_ON_GATE)
            return NULL;
        nile_Process_activate (p, thread);
        p->input = v.output;
        return nile_Buffer (p); 
    }
}

nile_Process_t *
nile_Cat (nile_Process_t *p, int quantum, int is_top)
{
    p = nile_Process (p, quantum, 0, NULL, nile_Cat_body, nile_Cat_epilogue);
    if (p) {
        nile_Cat_vars_t *vars = nile_Process_vars (p);
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
    nile_DupCat_vars_t *vars = nile_Process_vars (p);
    nile_DupCat_vars_t v = *vars;
    nile_Process_t *c1 = nile_Cat (p, v.p1_out_quantum, 1);
    nile_Process_t *c2 = nile_Cat (p, v.p2_out_quantum, 0);
    nile_Process_t *dup = nile_Dup (p, p->quantum,
                                    v.p1 ? nile_Process_pipe (v.p1, c1, NILE_NULL) : c1,
                                    v.p2 ? nile_Process_pipe (v.p2, c2, NILE_NULL) : c2);
    if (!c1 || !c2 || !dup)
        return nile_Process_deactivate (p, NULL), NULL;
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
