#ifndef NILE_DEQUE_H
#define NILE_DEQUE_H

typedef struct nile_Node_ {
    struct nile_Node_ *next;
} nile_Node_t;

typedef struct {
    nile_Node_t *head;
    nile_Node_t *tail;
    int          n;
} nile_Deque_t;

static void
nile_Deque_push_head (nile_Deque_t *d, nile_Node_t *nd)
{
    nd->next = d->head;
    d->head = nd;
    d->tail = d->tail ? d->tail : nd;
    d->n++;
}

static void
nile_Deque_push_tail (nile_Deque_t *d, nile_Node_t *nd)
{
    nd->next = NULL;
    if (d->tail)
        d->tail->next = nd;
    else
        d->head = nd;
    d->tail = nd;
    d->n++;
}

static nile_Node_t *
nile_Deque_pop_head (nile_Deque_t *d)
{
    nile_Node_t *nd = d->head;
    if (nd) {
        d->head = nd->next;
        d->tail = d->head ? d->tail : NULL;
        d->n--;
    }
    return nd;
}

static nile_Node_t *
nile_Deque_pop_tail (nile_Deque_t *d)
{
    nile_Node_t *nd = d->tail;
    if (nd) {
        if (d->head == nd)
            d->head = d->tail = NULL;
        else {
            nile_Node_t *tail = d->head;
            while (tail->next != nd)
                tail = tail->next;
            tail->next = NULL;
            d->tail = tail;
        }
        d->n--;
    }
    return nd;
}

#endif
