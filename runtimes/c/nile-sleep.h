typedef CACHE_ALIGNED struct {
    nile_Lock_t lock;
    int         nthreads;
    int         nsleeping;
    nile_Sem_t  wakeup;
} CACHE_ALIGNED nile_Sleep_t;

static void
nile_Sleep_init (nile_Sleep_t *s, int nthreads)
{
    s->lock = 0;
    s->nthreads = nthreads;
    s->nsleeping = 0;
    nile_Sem_init (&s->wakeup, 0);
}

static void
nile_Sleep_fini (nile_Sleep_t *s)
{
    nile_Sem_fini (&s->wakeup);
}

static void
nile_Sleep_awaken (nile_Sleep_t *s)
{
    int nsleeping;
    nile_Lock_acq (&s->lock);
        nsleeping = s->nsleeping;
        s->nsleeping = nsleeping ? nsleeping - 1 : nsleeping;
    nile_Lock_rel (&s->lock);
    if (nsleeping)
        nile_Sem_signal (&s->wakeup);
}

static void
nile_Sleep_sleep (nile_Sleep_t *s)
{
    nile_Lock_acq (&s->lock);
        s->nsleeping++;
    nile_Lock_rel (&s->lock);
    nile_Sem_wait (&s->wakeup);
}

static void
nile_Sleep_doze (int npauses)
{
    while (npauses--)
        nile_pause ();
}

static int
nile_Sleep_is_quiescent (nile_Sleep_t *s)
{
    return s->nsleeping == (s->nthreads - 1);
}
