#include <stdio.h>
#include <string.h>

#define GC_APP_HEADER	int type;

#include "gc.c"
#include "buffer.c"

union Object;

typedef union Object *oop;

#define nil ((oop)0)

enum { Undefined, Long, String, Symbol, Pair, Array };

struct Long	{ long bits; };
struct String	{ char *bits; };
struct Symbol	{ char *bits; };
struct Pair	{ oop head, tail; };

union Object {
  struct Long	Long;
  struct String	String;
  struct Symbol	Symbol;
  struct Pair	Pair;
};

#define setType(OBJ, TYPE)		(ptr2hdr(OBJ)->type= (TYPE))

static inline int getType(oop obj)	{ return obj ? ptr2hdr(obj)->type : Undefined; }

#define is(TYPE, OBJ)			((OBJ) && (TYPE == getType(OBJ)))

#if defined(NDEBUG)
# define checkType(OBJ, TYPE) OBJ
#else
# define checkType(OBJ, TYPE) _checkType(OBJ, TYPE, #TYPE, __FILE__, __LINE__)
  static inline oop _checkType(oop obj, int type, char *name, char *file, int line)
  {
    if (!is(type, obj)) {
      fprintf(stderr, "%s:%i: typecheck failed for %s (%i != %i)", file, line, name, type, getType(obj));
      exit(1);
    }
    assert(is(type, obj));
    return obj;
  }
#endif

#define get(OBJ, TYPE, FIELD)		(checkType(OBJ, TYPE)->TYPE.FIELD)
#define set(OBJ, TYPE, FIELD, VALUE)	(checkType(OBJ, TYPE)->TYPE.FIELD= (VALUE))

#define getHead(OBJ)	get(OBJ, Pair,head)
#define getTail(OBJ)	get(OBJ, Pair,tail)

#define newBits(TYPE)	_newBits(TYPE, sizeof(struct TYPE))
#define newOops(TYPE)	_newOops(TYPE, sizeof(struct TYPE))

static oop _newBits(int type, size_t size)	{ oop obj= GC_malloc_atomic(size);	setType(obj, type);  return obj; }
static oop _newOops(int type, size_t size)	{ oop obj= GC_malloc(size);		setType(obj, type);  return obj; }

static oop symbols= nil, s_quote= nil, s_unquote= nil, s_unquote_splicing= nil;
static oop globals= nil;

static oop newLong(long bits)		{ oop obj= newBits(Long);	set(obj, Long,bits, bits);				return obj; }
static oop newString(char *cstr)	{ oop obj= newBits(String);	set(obj, String,bits, strdup(cstr));			return obj; }
static oop newSymbol(char *cstr)	{ oop obj= newBits(Symbol);	set(obj, Symbol,bits, strdup(cstr));			return obj; }
static oop newPair(oop head, oop tail)	{ oop obj= newOops(Pair);	set(obj, Pair,head, head);  set(obj, Pair,tail, tail);	return obj; }
static oop newArray(int tally)		{ return _newOops(Array, sizeof(oop) * tally); }

static oop intern(char *cstr)
{
  oop list= nil;
  for (list= symbols;  is(Pair, list);  list= getTail(list)) {
    oop sym= getHead(list);
    if (!strcmp(cstr, get(sym, Symbol,bits))) return sym;
  }
  oop sym= nil;
  GC_PROTECT(sym);
  sym= newSymbol(cstr);
  symbols= newPair(sym, symbols);
  GC_UNPROTECT(sym);
  return sym;
}

#include "chartab.h"

static int isPrint(int c)	{ return 0 <= c && c <= 127 && (CHAR_PRINT   & chartab[c]); }
static int isDigit(int c)	{ return 0 <= c && c <= 127 && (CHAR_DIGIT10 & chartab[c]); }
static int isLetter(int c)	{ return 0 <= c && c <= 127 && (CHAR_LETTER  & chartab[c]); }

static oop read(FILE *fp);

static oop readList(FILE *fp, int delim)
{
  oop head= nil, tail= head, obj= nil;
  GC_PROTECT(head);
  GC_PROTECT(obj);
  obj= read(fp);
  if (obj == (oop)EOF) goto eof;
  head= tail= newPair(obj, nil);
  for (;;) {
    obj= read(fp);
    if (obj == (oop)EOF) goto eof;
    obj= newPair(obj, nil);
    tail= set(tail, Pair,tail, obj);
  }
eof:;
  int c= getc(fp);
  if (c != delim) {
    fprintf(stderr, "EOF while reading list\n");
    exit(1);
  }
  GC_UNPROTECT(obj);
  GC_UNPROTECT(head);
  return head;
}

static int digitValue(int c)
{
  switch (c) {
    case '0' ... '9':  return c - '0';
    case 'A' ... 'Z':  return c - 'A' + 10;
    case 'a' ... 'z':  return c - 'a' + 10;
  }
  fprintf(stderr, "illegal digit in character escape\n");
  exit(1);
}

static int isHexadecimal(int c)
{
  switch (c) {
    case '0' ... '9':
    case 'A' ... 'F':
    case 'a' ... 'f':
      return 1;
  }
  return 0;
}

static int isOctal(int c)
{
  return '0' <= c && c <= '7';
}

static int readChar(FILE *fp)
{
  int c= getc(fp);
  if ('\\' == c) {
    c= getc(fp);
    switch (c) {
      case 'a':   return '\a';
      case 'b':   return '\b';
      case 'f':   return '\f';
      case 'n':   return '\n';
      case 'r':   return '\r';
      case 't':   return '\t';
      case 'v':   return '\v';
      case '\'':  return '\'';
      case '"':   return '"';
      case '\\':  return '\\';
      case 'u': {
	int a= getc(fp), b= getc(fp), c= getc(fp), d= getc(fp);
	return (digitValue(a) << 24) + (digitValue(b) << 16) + (digitValue(c) << 8) + digitValue(d);
      }
      case 'x': {
	int x= 0;
	while (isHexadecimal(c= getc(fp)))
	  x= x * 16 + digitValue(c);
	ungetc(c, fp);
	return x;
      }
      case '0' ... '7': {
	int x= 0;
	if (isOctal(c= getc(fp))) {
	  x= x * 8 + digitValue(c);
	  if (isOctal(c= getc(fp))) {
	    x= x * 8 + digitValue(c);
	    if (isOctal(c= getc(fp))) {
	      x= x * 8 + digitValue(c);
	      c= getc(fp);
	    }
	  }
	}
	ungetc(c, fp);
	return x;
      }
      default:
	fprintf(stderr, "illegal character escape: \\%c", c);
	exit(1);
	break;
    }
  }
  return c;
}

static oop read(FILE *fp)
{
  for (;;) {
    int c= getc(fp);
    switch (c) {
      case EOF: {
	return (oop)EOF;
      }
      case '\t':  case '\n':  case '\r':  case ' ' : {
	continue;
      }
      case ';': {
	for (;;) {
	  c= getc(fp);
	  if ('\n' == c || '\r' == c || EOF == c) break;
	}
	continue;
      }
      case '"': {
	static struct buffer buf= BUFFER_INITIALISER;
	buffer_reset(&buf);
	for (;;) {
	  c= getc(fp);
	  if ('"' == c) break;
	  ungetc(c, fp);
	  c= readChar(fp);
	  if (EOF == c) {
	    fprintf(stderr, "EOF in string literal\n");
	    exit(1);
	  }
	  buffer_append(&buf, c);
	}
	return newString(buffer_contents(&buf));
      }
      case '\'': {
	oop obj= read(fp);
	GC_PROTECT(obj);
	obj= newPair(s_quote, obj);
	GC_UNPROTECT(obj);
	return obj;
      }
      case ',': {
	oop sym= s_unquote;
	c= getc(fp);
	if ('@' == c)	sym= s_unquote_splicing;
	else		ungetc(c, fp);
	oop obj= read(fp);
	GC_PROTECT(obj);
	obj= newPair(sym, obj);
	GC_UNPROTECT(obj);
	return obj;
      }
      case '0' ... '9': {
	static struct buffer buf= BUFFER_INITIALISER;
	buffer_reset(&buf);
	while (isDigit(c)) {
	  buffer_append(&buf, c);
	  c= getc(fp);
	}
	ungetc(c, fp);
	return newLong(strtoul(buffer_contents(&buf), 0, 0));
      }
      case '(': return readList(fp, ')');      case ')': ungetc(c, fp);  return (oop)EOF;
      case '[': return readList(fp, ']');      case ']': ungetc(c, fp);  return (oop)EOF;
      case '{': return readList(fp, '}');      case '}': ungetc(c, fp);  return (oop)EOF;
      default: {
	if (isLetter(c)) {
	  static struct buffer buf= BUFFER_INITIALISER;
	  buffer_reset(&buf);
	  while (isLetter(c)) {
	    buffer_append(&buf, c);
	    c= getc(fp);
	  }
	  ungetc(c, fp);
	  return intern(buffer_contents(&buf));
	}
	fprintf(stderr, "illegal character: 0x%02x", c);
	if (isPrint(c)) fprintf(stderr, " '%c'", c);
	fprintf(stderr, "\n");
	exit(1);
      }
    }
  }
}
    
static void dump(oop obj)
{
  if (!obj) {
    printf("nil");
    return;
  }
  switch (getType(obj)) {
    case Undefined:	printf("UNDEFINED");				break;
    case Long:		printf("%ld", get(obj, Long,bits));		break;
    case String:	printf("\"%s\"", get(obj, String,bits));	break;
    case Symbol:	printf("%s", get(obj, Symbol,bits));		break;
    case Pair: {
      printf("(");
      for (;;) {
	dump(getHead(obj));
	obj= getTail(obj);
	if (!is(Pair, obj)) break;
	printf(" ");
      }
      printf(")");
      break;
    }
    default: {
      fprintf(stderr, "illegal type: %i in dump\n", getType(obj));
      exit(1);
    }
  }
}

static void dumpln(oop obj)
{
  dump(obj);
  printf("\n");
}

int main()
{
  GC_add_root(&symbols);
  GC_add_root(&globals);

  s_quote		= intern("quote");
  s_unquote		= intern("unquote");
  s_unquote_splicing	= intern("unquote-splicing");

  for (;;) {
    printf(".");
    fflush(stdout);
    oop obj= read(stdin);
    if (obj == (oop)EOF) break;
    dumpln(obj);
    fflush(stdout);
    GC_gcollect();
  }
  int c= getc(stdin);
  if (EOF != c) {
    fprintf(stderr, "unexpected character 0x%02x '%c'\n", c, c);
    exit(1);
  }
  printf("\nmorituri te salutant\n");

  return 0;
}
