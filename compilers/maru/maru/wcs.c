#define _WIDEN(x)  L ## x
#define WIDEN(x)   _WIDEN(x)

#include <wchar.h>
#include <stdlib.h>

static wchar_t *mbs2wcs(char *mbs)
{
    static wchar_t *wcs= 0;
    static size_t bufSize= 0;
    size_t len= strlen(mbs) + 1;
    if (bufSize < len)
    {
	wcs= wcs ? (wchar_t *)realloc(wcs, sizeof(wchar_t) * len) : (wchar_t *)malloc(sizeof(wchar_t) * len);
	bufSize= len;
    }
    mbstowcs(wcs, mbs, bufSize);
    return wcs;
}

static char *wcs2mbs(wchar_t *wcs)
{
    typedef struct { char *mbs;  size_t size; } buf_t;
    static buf_t bufs[32]= {{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}};
    static int bufn= 0;
    buf_t *buf= bufs + bufn++;
    if (bufn == 32) bufn= 0;
    size_t len= 6 * wcslen(wcs) + 1;
    if (buf->size < len) {
	buf->mbs= buf->mbs ? (char *)realloc(buf->mbs, len) : (char *)malloc(len);
	buf->size= len;
    }
    wcstombs(buf->mbs, wcs, buf->size);
    return buf->mbs;
}


#if defined(__MACH__) && !defined(__MAC_10_7)

static wchar_t *wcsdup(wchar_t *s)
{
  size_t len= wcslen(s) + 1;
  wchar_t *t= malloc(sizeof(wchar_t) * len);
  if (t) wcscpy(t, s);
  return t;
}

#endif


#if 0

static void wperror(wchar_t *s)
{
    perror(wcs2mbs(s));
}

static FILE *wfopen(wchar_t *wpath, wchar_t *wmode)
{
    size_t pathlen= wcslen(wpath), modelen= wcslen(wmode);
    char *path= malloc(sizeof(wchar_t) * (pathlen + 1));  wcstombs(path, wpath, pathlen);
    char *mode= malloc(sizeof(wchar_t) * (modelen + 1));  wcstombs(mode, wmode, modelen);
    FILE *fp= fopen(path, mode);
    free(path);
    free(mode);
    return fp;
}

#endif
