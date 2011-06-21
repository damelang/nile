#ifndef NILE_SLEEP_H
#define NILE_SLEEP_H

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

#endif
