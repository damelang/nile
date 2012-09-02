#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#define NILE_INCLUDE_PROCESS_API
#include "nile.h"

#ifdef __cplusplus
extern "C" {
#endif

#include "nile-platform.h"
#include "nile-sleep.h"
#include "nile-heap.h"
#include "nile-deque.h"
#include "nile-thread.h"
#include "nile-buffer.h"

#define INPUT_QUOTA 5
#define INPUT_MAX (2 * INPUT_QUOTA)

#include "nile-process.c"
#include "nile-builtins.c"

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

    nile_Process_activate (&boot, &threads[nthreads]);
    init = nile_Process (&boot, 0, 0, NULL, NULL, NULL);
    nile_Process_deactivate (&boot, NULL);
    if (init)
        nile_Process_activate (init, &threads[nthreads]);
    return init;
}

void
nile_sync (nile_Process_t *init)
{
    int i;
    nile_Process_t *p;
    nile_Thread_t *liaison = nile_Process_deactivate (init, NULL);
    nile_Thread_t *worker = &liaison->threads[0];

    nile_Thread_transfer_heaps (liaison, worker);
    for (i = 1; i < liaison->nthreads; i++)
        liaison->threads[i].sync = 1;

    if ((p = (nile_Process_t *) nile_Thread_steal_from_q (worker)))
        nile_Thread_work (worker, p);
    while (worker->status == NILE_STATUS_OK) {
        p = (nile_Process_t *) nile_Thread_steal (worker, nile_Thread_steal_from_q);
        if (p)
            nile_Thread_work (worker, p);
        else if (nile_Sleep_is_quiescent (worker->sleep))
            break;
        else
            nile_Sleep_doze (1000);
    }

    for (i = 1; i < liaison->nthreads; i++)
        liaison->threads[i].sync = 0;
    nile_Thread_transfer_heaps (worker, liaison);
    nile_Process_activate (init, liaison);
}

nile_Status_t
nile_status (nile_Process_t *init)
{
    return init->thread->status;
}

char *
nile_shutdown (nile_Process_t *init)
{
    int i;
    nile_Thread_t *t = nile_Process_deactivate (init, NULL);
    for (i = 0; i < t->nthreads + 1; i++)
        t->threads[i].status = NILE_STATUS_SHUTTING_DOWN;
    for (i = 0; i < t->nthreads; i++)
        nile_Sleep_awaken (t->sleep);
    for (i = 1; i < t->nthreads; i++)
        nile_OSThread_join (&t->threads[i].osthread);
    nile_Sleep_fini (t->sleep);
    return t->memory;
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
    nile_Thread_t *t = nile_Process_deactivate (init, NULL);
    nile_Block_t *block = (nile_Block_t *) (t->threads + t->nthreads + 1);
    nile_Block_t *EOB   = (nile_Block_t *) (t->memory + t->nbytes - sizeof (*block) + 1);
    int nblocks = EOB - block; // minus the init block
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
    nile_Process_activate (init, t);
}

#ifdef __cplusplus
}
#endif
