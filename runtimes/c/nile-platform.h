#define CACHE_LINE_SIZE 64
#define SIMD_SIZE 16

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#ifdef _MSC_VER
#define INLINE static __forceinline
#else
#define INLINE static inline
#endif

/* Memory alignment */

#ifdef __GNUC__
#define ALIGNED(a) __attribute__ ((aligned (a)))
#elif defined (_MSC_VER)
#define ALIGNED(a) __declspec (align (a))
#else
#error Unsupported compiler!
#endif
#define CACHE_ALIGNED ALIGNED (CACHE_LINE_SIZE)

/* CPU pause and cache prefetch */

#if defined (__i386__) || defined (__x86_64__) || \
    defined (_M_IX86)  || defined (_M_X64)
#include <xmmintrin.h>
#define nile_pause _mm_pause
#define nile_prefetch(a) _mm_prefetch (a, _MM_HINT_T0)
#else
#error Unsupported architecture!
#endif

#ifndef NILE_DISABLE_THREADS

/* Spin locks */

typedef long nile_Lock_t;

#if defined (__i386__) || defined (__x86_64__) || \
    defined (_M_IX86)  || defined (_M_X64)

#ifdef __INTEL_COMPILER
#define nile_xchg _InterlockedExchange
#elif defined (_MSC_VER)
#include <intrin.h>
#pragma intrinsic (_InterlockedExchange)
#define nile_xchg _InterlockedExchange
#elif defined (__GNUC__)
INLINE long
nile_xchg (nile_Lock_t *l, long v)
{
    __asm__ __volatile__("xchg %0, %1"
                         : "=r" (v) : "m" (*l), "0" (v) : "memory");
    return v;
}
#else
#error Unsupported compiler!
#endif

INLINE void nile_Lock_acq  (nile_Lock_t *l) { while (nile_xchg (l, 1)) nile_pause (); }
INLINE void nile_Lock_rel  (nile_Lock_t *l) { _mm_mfence (); *l = 0;                  }

#else
#error Unsupported architecture!
#endif

/* Semaphores */

#ifdef __MACH__

#include <mach/mach.h>
#include <mach/semaphore.h>
typedef semaphore_t nile_Sem_t;

static void nile_Sem_init   (nile_Sem_t *s, int v) { semaphore_create (mach_task_self (), s,
                                                                       SYNC_POLICY_FIFO, v);    }
static void nile_Sem_fini   (nile_Sem_t *s)        { semaphore_destroy (mach_task_self (), *s); }
static void nile_Sem_signal (nile_Sem_t *s)        { semaphore_signal (*s);                     }
static void nile_Sem_wait   (nile_Sem_t *s)        { kern_return_t status;
                                                     do status = semaphore_wait (*s);
                                                     while (status == KERN_ABORTED);            }
#elif defined (__linux)

#include <semaphore.h>
#include <errno.h>
typedef sem_t nile_Sem_t;

static void nile_Sem_init   (nile_Sem_t *s, int v) { sem_init (s, 0, v);                     }
static void nile_Sem_fini   (nile_Sem_t *s)        { sem_destroy (s);                        }
static void nile_Sem_signal (nile_Sem_t *s)        { sem_post (s);                           }
static void nile_Sem_wait   (nile_Sem_t *s)        { int status;
                                                     do status = sem_wait (s);
                                                     while (status == -1 && errno == EINTR); }
#elif defined (_WIN32)

typedef HANDLE nile_Sem_t;

static void nile_Sem_init   (nile_Sem_t *s, int v) { *s = CreateSemaphore (NULL, v, 9999, 0); }
static void nile_Sem_fini   (nile_Sem_t *s)        { CloseHandle (*s);                        }
static void nile_Sem_signal (nile_Sem_t *s)        { ReleaseSemaphore (*s, 1, NULL);          } 
static void nile_Sem_wait   (nile_Sem_t *s)        { WaitForSingleObject (*s, INFINITE);      }

#else
#error Unsupported operating system!
#endif

/* OS Threads */

#if defined(__unix__) || defined(__APPLE__)

#include <pthread.h>
typedef pthread_t nile_OSThread_t;
#define NILE_DECLARE_THREAD_START_ROUTINE(name, arg) \
    static void *name (void *arg)

static void
nile_OSThread_spawn (nile_OSThread_t *t, void *(*f)(void *), void *arg)
{
    pthread_create (t, NULL, f, arg);
}

static void
nile_OSThread_join (nile_OSThread_t *t)
{
    pthread_join (*t, NULL);
}

#elif defined(_WIN32)

typedef HANDLE nile_OSThread_t;
#define NILE_DECLARE_THREAD_START_ROUTINE(name, arg) \
    static DWORD __stdcall name (LPVOID arg)

static void
nile_OSThread_spawn (nile_OSThread_t *t, LPTHREAD_START_ROUTINE f, void *arg)
{
    *t = CreateThread (NULL, 0, f, arg, 0, NULL);
}

static void
nile_OSThread_join (nile_OSThread_t *t)
{
    WaitForSingleObject (*t, INFINITE);
    CloseHandle (*t);
}

#else
#error Unsupported operating system!
#endif

#else

typedef int nile_Lock_t;
#define nile_Lock_acq(l)
#define nile_Lock_rel(l)
typedef int nile_Sem_t;
#define nile_Sem_init(s, v)
#define nile_Sem_fini(s)
#define nile_Sem_signal(s)
#define nile_Sem_wait(s)
typedef int nile_OSThread_t;
#define nile_OSThread_spawn(t, f, arg)
#define nile_OSThread_join(t)

#endif
