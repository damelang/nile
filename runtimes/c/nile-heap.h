#define BLOCK_SIZE    512
#define CHUNK_MAX_LEN  16

typedef ALIGNED (BLOCK_SIZE) struct nile_Block_ {
    struct nile_Block_ *next;
    struct nile_Block_ *eoc;
    int                 i;
} ALIGNED (BLOCK_SIZE) nile_Block_t;

typedef nile_Block_t  nile_Chunk_t;
typedef nile_Block_t *nile_Heap_t;

static int
nile_Heap_push (nile_Heap_t *h, void *v)
{
    nile_Block_t *b = (nile_Block_t *)v;
    nile_Block_t *head = *h;
    b->next = head;
    if (head && head->i < CHUNK_MAX_LEN) {
        b->eoc = head->eoc;
        b->i = head->i + 1;
    }
    else {
        b->eoc = b;
        b->i = 1;
    }
    *h = b;
    return b->i == CHUNK_MAX_LEN && b->eoc->next;
}

static void
nile_Heap_push_chunk (nile_Heap_t *h, nile_Chunk_t *c)
{
    c->eoc->next = *h;
    *h = c;
}

static void *
nile_Heap_pop (nile_Heap_t *h)
{
    nile_Block_t *b = *h;
    *h = b ? b->next : b;
    return b;
}

static nile_Chunk_t *
nile_Heap_pop_chunk (nile_Heap_t *h)
{
    nile_Block_t *b = *h;
    *h = b ? b->eoc->next : b;
    return b;
}
