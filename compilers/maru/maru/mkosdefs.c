#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

#if defined(__WIN32__)
# include <w32dlfcn.h>
#else
# include <dlfcn.h>
#endif

#ifndef RTLD_DEFAULT
# define RTLD_DEFAULT 0
#endif

#define STR(X)		#X

#define defint(X)	printf("(define %s %ld)\n", #X, (long)X)
#define defstr(X)	printf("(define %s \"%s\")\n", #X, STR(X))
#define defsize(X)	printf("(define-constant sizeof-%s %ld)\n", #X, (long)sizeof(X))
#define defalign(X)	{ struct { char _;  X x; } x;  printf("(define-constant alignof-%s %ld)\n", #X, (long)&x.x - (long)&x); }
#define defsao(X)	defsize(X);  defalign(X)

typedef long long longlong;
typedef long double longdouble;
typedef void *pointer;
typedef int32_t int32;
typedef int64_t int64;
typedef wchar_t wchar;

int main()
{
# ifdef __APPLE__
    defint(__APPLE__);
# endif
# ifdef __ELF__
    defint(__ELF__);
# endif
# ifdef __LITTLE_ENDIAN__
    defint(__LITTLE_ENDIAN__);
# endif
# ifdef __MACH__
    defint(__MACH__);
# endif
# ifdef __WIN32__
    defint(__WIN32__);
# endif
# ifdef __USER_LABEL_PREFIX__
    defstr(__USER_LABEL_PREFIX__);
# endif
# ifdef __i386__
    defint(__i386__);
# endif
# ifdef __i586__
    defint(__i586__);
# endif
# ifdef __linux__
    defint(__linux__);
# endif
    defsao(char);
    defsao(short);
    defsao(int);
    defsao(long);
    defsao(longlong);
    defsao(int32);
    defsao(int64);
    defsao(wchar);
    defsao(float);
    defsao(double);
    defsao(longdouble);
    defsao(pointer);
    defint(RTLD_NOW);
    defint(RTLD_GLOBAL);
    defint(RTLD_DEFAULT);
    return 0;
}
