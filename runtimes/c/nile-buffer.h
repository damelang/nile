#ifndef NILE_BUFFER_H
#define NILE_BUFFER_H

static void *
nile_Process_alloc_node (nile_Process_t *p);

#define BAT(b, i)         ((&b->data)[i])
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
    b->capacity = (sizeof (nile_Block_t) - sizeof (*nd) - sizeof (*b)) / sizeof (nile_Real_t) + 1;
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

#endif
