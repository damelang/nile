#include <gc/gc.h>

struct _header
{
    GC_APP_HEADER
    int	size;
};

#define hdr2ptr(ptr)		((void *)((struct _header *)(ptr) + 1))
#define ptr2hdr(ptr)		(        ((struct _header *)(ptr) - 1))

static inline void *GC_malloc_z(size_t size)
{
    struct _header *hdr= GC_malloc(sizeof(struct _header) + size);
    memset(hdr, 0, sizeof(struct _header) + size);
    hdr->size= size;
    return hdr2ptr(hdr);
}

static inline void *GC_malloc_atomic_z(size_t size)
{
    struct _header *hdr= GC_malloc(sizeof(struct _header) + size);
    memset(hdr, 0, sizeof(struct _header) + size);
    hdr->size= size;
    return hdr2ptr(hdr);
}

static inline void *GC_realloc_z(void *ptr, size_t size)
{
    struct _header *hdr= GC_realloc(ptr2hdr(ptr), sizeof(struct _header) + size);
    return hdr2ptr(hdr);
}

#define FUDGE			0

#define GC_malloc(size)		GC_malloc_z(size)
#define GC_malloc_atomic(size)	GC_malloc_atomic_z(size)
#define GC_realloc(ptr, size)	GC_realloc_z(ptr, size)

#define GC_size(ptr)		(ptr2hdr(ptr)->size)
#define GC_atomic(obj)		(ptr2hdr(obj)->type == Long || ptr2hdr(obj)->type == Double || ptr2hdr(obj)->type == Symbol || ptr2hdr(obj)->type == Subr)

#define GC_add_root(oopp)

#define GC_PROTECT(obj)
#define GC_UNPROTECT(obj)
