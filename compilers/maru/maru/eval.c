// last edited: 2011-05-11 17:05:49 by piumarta on 192.168.1.11

#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <stdarg.h>

extern int isatty(int);

//#define	TAG_INT	0

#define GC_APP_HEADER	int type;

#include "gc.c"
#include "buffer.c"

union Object;

typedef union Object *oop;

typedef oop (*imp_t)(oop args, oop env);

#define nil ((oop)0)

enum { Undefined, Long, String, Symbol, Pair, _Array, Array, Expr, Form, Fixed, Subr, Variable, Env, Context };

#if (TAG_INT)
  struct Long	{};
#else
  struct Long	{ long  bits; };
#endif

struct String	{ oop   size;  char *bits; };	/* bits is in managed memory */
struct Symbol	{ char *bits; };
struct Pair	{ oop 	head, tail, source; };
struct Array	{ oop   size, _array; };
struct Expr	{ oop 	name, defn, ctx; };
struct Form	{ oop 	function, symbol; };
struct Fixed	{ oop   function; };
struct Subr	{ imp_t imp;  char *name; };
struct Variable	{ oop 	name, value, env, index; };
struct Env	{ oop 	parent, level, offset, bindings, stable; };
struct Context	{ oop 	home, env, bindings, callee; };

union Object {
  struct Long		Long;
  struct String		String;
  struct Symbol		Symbol;
  struct Pair		Pair;
  struct Array		Array;
  struct Expr		Expr;
  struct Form		Form;
  struct Fixed		Fixed;
  struct Subr		Subr;
  struct Variable	Variable;
  struct Env		Env;
  struct Context	Context;
};

static void fatal(char *reason, ...);

#define setType(OBJ, TYPE)		(ptr2hdr(OBJ)->type= (TYPE))

#if (TAG_INT)
  static inline int getType(oop obj)	{ return obj ? (((long)obj & 1) ? Long : ptr2hdr(obj)->type) : Undefined; }
#else
  static inline int getType(oop obj)	{ return obj ? ptr2hdr(obj)->type : Undefined; }
#endif

#define is(TYPE, OBJ)			((OBJ) && (TYPE == getType(OBJ)))

#if defined(NDEBUG)
# define checkType(OBJ, TYPE) OBJ
#else
# define checkType(OBJ, TYPE) _checkType(OBJ, TYPE, #TYPE, __FILE__, __LINE__)
  static inline oop _checkType(oop obj, int type, char *name, char *file, int line)
  {
    if (obj && !((long)obj & 1) && !ptr2hdr(obj)->used)	fatal("%s:%i: attempt to access dead object %s\n", file, line, name);
    if (!is(type, obj))					fatal("%s:%i: typecheck failed for %s (%i != %i)\n", file, line, name, type, getType(obj));
    return obj;
  }
#endif

#define get(OBJ, TYPE, FIELD)		(checkType(OBJ, TYPE)->TYPE.FIELD)
#define set(OBJ, TYPE, FIELD, VALUE)	(checkType(OBJ, TYPE)->TYPE.FIELD= (VALUE))

#define getHead(OBJ)	get(OBJ, Pair,head)
#define getTail(OBJ)	get(OBJ, Pair,tail)

#define setHead(OBJ, VAL)	set(OBJ, Pair,head, VAL)
#define setTail(OBJ, VAL)	set(OBJ, Pair,tail, VAL)

static oop car(oop obj)			{ return is(Pair, obj) ? getHead(obj) : nil; }
static oop cdr(oop obj)			{ return is(Pair, obj) ? getTail(obj) : nil; }

static oop caar(oop obj)		{ return car(car(obj)); }
static oop cadr(oop obj)		{ return car(cdr(obj)); }
static oop cddr(oop obj)		{ return cdr(cdr(obj)); }
//static oop caaar(oop obj)		{ return car(car(car(obj))); }
//static oop cadar(oop obj)		{ return car(cdr(car(obj))); }
//static oop caddr(oop obj)		{ return car(cdr(cdr(obj))); }
//static oop cadddr(oop obj)		{ return car(cdr(cdr(cdr(obj)))); }

#define newBits(TYPE)	_newBits(TYPE, sizeof(struct TYPE))
#define newOops(TYPE)	_newOops(TYPE, sizeof(struct TYPE))

static oop _newBits(int type, size_t size)	{ oop obj= GC_malloc_atomic(size);	setType(obj, type);  return obj; }
static oop _newOops(int type, size_t size)	{ oop obj= GC_malloc(size);		setType(obj, type);  return obj; }

static oop symbols= nil;
static oop s_define= nil, s_set= nil, s_quote= nil, s_lambda= nil, s_let= nil, s_quasiquote= nil, s_unquote= nil, s_unquote_splicing= nil, s_t= nil, s_dot= nil; //, s_in= nil;
static oop f_lambda= nil, f_let= nil, f_quote= nil, f_set= nil, f_define;
static oop globals= nil, expanders= nil, encoders= nil, evaluators= nil, applicators= nil;
static oop arguments= nil, backtrace= nil, input= nil;

static int opt_b= 0, opt_v= 0;

#if (TAG_INT)
# define     isLong(X)			((long)(X) & 1)
# define     newLong(X)			((oop)(((X) << 1) | 1))
# define     getLong(X)			((long)(X) >> 1)
#else
# define     isLong(X)			is(Long, (X))
  static oop newLong(long bits)		{ oop obj= newBits(Long);  set(obj, Long,bits, bits);  return obj; }
# define     getLong(X)			get((X), Long,bits)
#endif

static oop _newString(size_t len)
{
  char *gstr= GC_malloc_atomic(len + 1);	GC_PROTECT(gstr);	/* + 1 to ensure null terminator */
  oop   obj=  newOops(String);			GC_PROTECT(obj);
  set(obj, String,size, newLong(len));		GC_UNPROTECT(obj);
  set(obj, String,bits, gstr);			GC_UNPROTECT(gstr);
  return obj;
}

static oop newString(char *cstr)
{
  size_t len= strlen(cstr);
  oop obj= _newString(len);
  memcpy(get(obj, String,bits), cstr, len);
  return obj;
}

static int stringLength(oop string)
{
  return getLong(get(string, String,size));
}

static oop newSymbol(char *cstr)	{ oop obj= newBits(Symbol);	set(obj, Symbol,bits, strdup(cstr));			return obj; }

static oop newPair(oop head, oop tail)	{ oop obj= newOops(Pair);	set(obj, Pair,head, head);  set(obj, Pair,tail, tail);	return obj; }

static oop newPairFrom(oop head, oop tail, oop source)
{
  oop obj= newOops(Pair);
  set(obj, Pair,head, 	head);
  set(obj, Pair,tail, 	tail);
  set(obj, Pair,source, get(source, Pair,source));
  return obj;
}

static oop newArray(int size)
{
  int cap=  size ? size : 1;
  oop elts= _newOops(_Array, sizeof(oop) * cap);	GC_PROTECT(elts);
  oop obj=   newOops( Array);				GC_PROTECT(obj);
  set(obj, Array,_array, elts);
  set(obj, Array,size, newLong(size));			GC_UNPROTECT(obj);  GC_UNPROTECT(elts);
  return obj;
}

static int arrayLength(oop obj)
{
  return is(Array, obj) ? getLong(get(obj, Array,size)) : 0;
}

static oop arrayAt(oop array, int index)
{
  if (is(Array, array)) {
    oop elts= get(array, Array,_array);
    int size= arrayLength(array);
    if ((unsigned)index < (unsigned)size)
      return ((oop *)elts)[index];
  }
  return nil;
}

static oop arrayAtPut(oop array, int index, oop val)
{
  if (is(Array, array)) {
    int size= arrayLength(array);
    oop elts= get(array, Array,_array);
    if ((unsigned)index >= (unsigned)size) {
      GC_PROTECT(array);
      int cap= GC_size(elts) / sizeof(oop);
      if (index >= cap) {
	while (cap <= index) cap *= 2;
	oop oops= _newOops(_Array, sizeof(oop) * cap);
	memcpy((oop *)oops, (oop *)elts, size * sizeof(oop));
	elts= set(array, Array,_array, oops);
      }
      set(array, Array,size, newLong(index + 1));
      GC_UNPROTECT(array);
    }
    return ((oop *)elts)[index]= val;
  }
  return nil;
}

static oop arrayAppend(oop array, oop val)
{
  return arrayAtPut(array, arrayLength(array), val);
}

static oop arrayInsert(oop obj, size_t index, oop value)
{
  size_t len= arrayLength(obj);
  arrayAppend(obj, value);
  if (index < len) {
    oop  elts= get(obj, Array,_array);
    oop *oops= (oop *)elts + index;
    memmove(oops + 1, oops, sizeof(oop) * (len - index));
  }
  arrayAtPut(obj, index, value);
  return value;
}

static oop oopAt(oop obj, int index)
{
  if (obj && !isLong(obj) && !GC_atomic(obj)) {
    int size= GC_size(obj) / sizeof(oop);
    if ((unsigned)index < (unsigned)size) return ((oop *)obj)[index];
  }
  return nil;
}

static oop oopAtPut(oop obj, int index, oop value)
{
  if (obj && !isLong(obj) && !GC_atomic(obj)) {
    int size= GC_size(obj) / sizeof(oop);
    if ((unsigned)index < (unsigned)size) return ((oop *)obj)[index]= value;
  }
  return nil;
}

static oop newExpr(oop defn, oop ctx)
{
  oop obj= newOops(Expr);
  set(obj, Expr,defn, defn);
  set(obj, Expr,ctx, ctx);
  return obj;
}

static oop newForm(oop fn, oop sym)	{ oop obj= newOops(Form);	set(obj, Form,function, fn);	set(obj, Form,symbol, sym);	return obj; }
static oop newFixed(oop function)	{ oop obj= newOops(Fixed);	set(obj, Fixed,function, function);				return obj; }

static oop newSubr(imp_t imp, char *name)
{
  oop obj= newBits(Subr);
  set(obj, Subr,imp,  imp);
  set(obj, Subr,name, name);
  return obj;
}

static oop newVariable(oop name, oop value, oop env, int index)
{
  oop obj= newOops(Variable);			GC_PROTECT(obj);
  set(obj, Variable,name,  name);
  set(obj, Variable,value, value);
  set(obj, Variable,env,   env);
  set(obj, Variable,index, newLong(index));	GC_UNPROTECT(obj);
  return obj;
}

static oop newEnv(oop parent, int level, int offset)
{
  oop obj= newOops(Env);			GC_PROTECT(obj);
  set(obj, Env,parent,   parent);
  set(obj, Env,level,    newLong((nil == parent) ? 0 : getLong(get(parent, Env,level)) + level));
  set(obj, Env,offset,   newLong(offset));
  set(obj, Env,bindings, newArray(0));		GC_UNPROTECT(obj);
  return obj;
}

static oop newBaseContext(oop home, oop caller, oop env)
{
  oop obj= newOops(Context);			GC_PROTECT(obj);
  set(obj, Context,home,     home);
  set(obj, Context,env,      env);
  set(obj, Context,bindings, newArray(0));	GC_UNPROTECT(obj);
  return obj;
}

static oop newContext(oop home, oop caller, oop env)
{
  oop obj= nil;
  if ((nil != caller) && (nil != (obj= get(caller, Context,callee)))) {
    set(obj, Context,home, home);
    set(obj, Context,env,  env);
    return obj;
  }
  obj= newBaseContext(home, caller, env);
  if (nil != caller) set(caller, Context,callee, obj);
  return obj;
}

static void dump(oop);
static void dumpln(oop);

static oop findVariable(oop env, oop name)
{
//  if (is(Pair, name) && s_in == getHead(name)) {
//    env= findVariable(env, cadr(name));
//    if (nil == env) fatal("undefined namespace: %s", get(cadr(name), Symbol,bits));
//    if (!is(Env, env)) fatal("not a namespace: %s", get(cadr(name), Symbol,bits));
//    return findVariable(env, caddr(name));
//  }
  while (nil != env) {
    oop bindings= get(env, Env,bindings);
    int index= arrayLength(bindings);
    while (--index >= 0) {
      oop var= arrayAt(bindings, index);
      if (get(var, Variable,name) == name)
	return var;
    }
    env= get(env, Env,parent);
  }
  return nil;
}

static oop lookup(oop env, oop name)
{
  oop var= findVariable(env, name);
  if (nil == var) fatal("undefined variable: %s", get(name, Symbol,bits));
  return get(var, Variable,value);
}

static oop define(oop env, oop name, oop value)
{
  oop bindings= get(env, Env,bindings);
  {
    int index= arrayLength(bindings);
    while (--index >= 0) {
      oop var= arrayAt(bindings, index);
      if (get(var, Variable,name) == name) {
	set(var, Variable,value, value);
	return var;
      }
    }
  }
  int off= getLong(get(env, Env,offset));
  oop var= newVariable(name, value, env, off);	GC_PROTECT(var);
  arrayAppend(bindings, var);			GC_UNPROTECT(var);
  set(env, Env,offset, newLong(off + 1));
  if (is(Expr, value) && (nil == get(value, Expr,name)))
    set(value, Expr,name, name);
  return var;
}

static int isGlobal(oop var)
{
  oop env= get(var, Variable,env);
  return (nil != env) && (0 == getLong(get(env, Env,level)));
}

static oop newBool(int b)		{ return b ? s_t : nil; }

static oop intern(char *string)
{
  ssize_t lo= 0, hi= arrayLength(symbols) - 1, c= 0;
  oop s= nil;
  while (lo <= hi) {
    size_t m= (lo + hi) / 2;
    s= arrayAt(symbols, m);
    c= strcmp(string, get(s, Symbol,bits));
    if      (c < 0)	hi= m - 1;
    else if (c > 0)	lo= m + 1;
    else		return s;
  }
  GC_PROTECT(s);
  s= newSymbol(string);
  arrayInsert(symbols, lo, s);
  GC_UNPROTECT(s);
  return s;
}

#include "chartab.h"

static int isPrint(int c)	{ return (0 <= c && c <= 127 && (CHAR_PRINT    & chartab[c])); }
static int isAlpha(int c)	{ return (0 <= c && c <= 127 && (CHAR_ALPHA    & chartab[c])); }
static int isDigit10(int c)	{ return (0 <= c && c <= 127 && (CHAR_DIGIT10  & chartab[c])); }
static int isDigit16(int c)	{ return (0 <= c && c <= 127 && (CHAR_DIGIT16  & chartab[c])); }
static int isLetter(int c)	{ return (0 <= c && c <= 127 && (CHAR_LETTER   & chartab[c])) || (c >= 128); }

#define DONE	((oop)-4)	/* cannot be a tagged immediate */

static oop currentPath= 0;
static oop currentLine= 0;
static oop currentSource= 0;

static void beginSource(char *path)
{
  currentPath= newString(path);
  currentLine= newLong(1);
  oop src= newPair(currentPath, currentLine);
  set(src, Pair,source, get(currentSource, Pair,source));
  set(currentSource, Pair,source, src);
}

static void advanceSource(void)
{
  currentLine= newLong(getLong(currentLine) + 1);
  set(currentSource, Pair,source, newPair(currentPath, currentLine));
}

static void endSource(void)
{
  set(currentSource, Pair,source, get(currentSource, Pair,source));
  oop src= get(currentSource, Pair,source);
  currentPath= car(src);
  currentLine= cdr(src);
}

static oop read(FILE *fp);

static oop readList(FILE *fp, int delim)
{
  oop head= nil, tail= head, obj= nil;
  GC_PROTECT(head);
  GC_PROTECT(obj);
  obj= read(fp);
  if (obj == DONE) goto eof;
  head= tail= newPairFrom(obj, nil, currentSource);
  for (;;) {
    obj= read(fp);
    if (obj == DONE) goto eof;
    if (obj == s_dot) {
      obj= read(fp);
      if (obj == DONE)		fatal("missing item after .");
      tail= set(tail, Pair,tail, obj);
      obj= read(fp);
      if (obj != DONE)		fatal("extra item after .");
      goto eof;
    }
    obj= newPairFrom(obj, nil, currentSource);
    tail= set(tail, Pair,tail, obj);
  }
eof:;
  int c= getc(fp);
  if (c != delim)			fatal("EOF while reading list");
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
  fatal("illegal digit in character escape");
  return 0;
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

static int readChar(int c, FILE *fp)
{
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
      case 'u': {
	int a= getc(fp), b= getc(fp), c= getc(fp), d= getc(fp);
	return (digitValue(a) << 24) + (digitValue(b) << 16) + (digitValue(c) << 8) + digitValue(d);
      }
      case 'x': {
	int x= 0;
	if (isHexadecimal(c= getc(fp))) {
	  x= digitValue(c);
	  if (isHexadecimal(c= getc(fp))) {
	    x= x * 16 + digitValue(c);
	    c= getc(fp);
	  }
	}
	ungetc(c, fp);
	return x;
      }
      case '0' ... '7': {
	int x= digitValue(c);
	if (isOctal(c= getc(fp))) {
	  x= x * 8 + digitValue(c);
	  if (isOctal(c= getc(fp))) {
	    x= x * 8 + digitValue(c);
	    c= getc(fp);
	  }
	}
	ungetc(c, fp);
	return x;
      }
      default:
	if (isAlpha(c) || isDigit10(c)) fatal("illegal character escape: \\%c", c);
	return c;
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
	return DONE;
      }
      case '\n': {
	while ('\r' == (c= getc(fp)));
	if (c >= 0) ungetc(c, fp);
	advanceSource();
	continue;
      }
      case '\r': {
	while ('\n' == (c= getc(fp)));
	ungetc(c, fp);
	advanceSource();
	continue;
      }
      case '\t':  case ' ': {
	continue;
      }
      case ';': {
	for (;;) {
	  c= getc(fp);
	  if (EOF == c) break;
	  if ('\n' == c || '\r' == c) {
	    ungetc(c, fp);
	    break;
	  }
	}
	continue;
      }
      case '"': {
	static struct buffer buf= BUFFER_INITIALISER;
	buffer_reset(&buf);
	for (;;) {
	  c= getc(fp);
	  if ('"' == c) break;
	  c= readChar(c, fp);
	  if (EOF == c)			fatal("EOF in string literal");
	  buffer_append(&buf, c);
	}
	oop obj= newString(buffer_contents(&buf));
	//buffer_free(&buf);
	return obj;
      }
      case '?': {
	return newLong(readChar(getc(fp), fp));
      }
      case '\'': {
	oop obj= read(fp);
	if (obj == DONE)
	  obj= s_quote;
	else {
	  GC_PROTECT(obj);
	  obj= newPairFrom(obj, nil, currentSource);
	  obj= newPairFrom(s_quote, obj, currentSource);
	  GC_UNPROTECT(obj);
	}
	return obj;
      }
      case '`': {
	oop obj= read(fp);
	if (obj == DONE)
	  obj= s_quasiquote;
	else {
	  GC_PROTECT(obj);
	  obj= newPairFrom(obj, nil, currentSource);
	  obj= newPairFrom(s_quasiquote, obj, currentSource);
	  GC_UNPROTECT(obj);
	}
	return obj;
      }
      case ',': {
	oop sym= s_unquote;
	c= getc(fp);
	if ('@' == c)	sym= s_unquote_splicing;
	else		ungetc(c, fp);
	oop obj= read(fp);
	if (obj == DONE)
	  obj= sym;
	else {
	  GC_PROTECT(obj);
	  obj= newPairFrom(obj, nil, currentSource);
	  obj= newPairFrom(sym, obj, currentSource);
	  GC_UNPROTECT(obj);
	}
	return obj;
      }
      case '0' ... '9':
      doDigits:	{
	static struct buffer buf= BUFFER_INITIALISER;
	buffer_reset(&buf);
	do {
	  buffer_append(&buf, c);
	  c= getc(fp);
	} while (isDigit10(c));
	if (('x' == c) && (1 == buf.position))
	  do {
	    buffer_append(&buf, c);
	    c= getc(fp);
	  } while (isDigit16(c));
	ungetc(c, fp);
	oop obj= newLong(strtoul(buffer_contents(&buf), 0, 0));
	return obj;
      }
      case '(': return readList(fp, ')');      case ')': ungetc(c, fp);  return DONE;
      case '[': return readList(fp, ']');      case ']': ungetc(c, fp);  return DONE;
      case '{': return readList(fp, '}');      case '}': ungetc(c, fp);  return DONE;
      case '-': {
	int d= getc(fp);
	ungetc(d, fp);
	if (isDigit10(d)) goto doDigits;
	/* fall through... */
      }
      default: {
	if (isLetter(c)) {
	  static struct buffer buf= BUFFER_INITIALISER;
	  oop obj= nil;						GC_PROTECT(obj);
	  oop in= nil;						GC_PROTECT(in);
	  buffer_reset(&buf);
	  while (isLetter(c) || isDigit10(c)) {
//	    if (('.' == c) && buf.position) {
//	      c= getc(fp);
//	      if (!isLetter(c) && !isDigit10(c)) {
//		ungetc(c, fp);
//		c= '.';
//	      }
//	      else {
//		obj= intern(buffer_contents(&buf));
//		in=  newPair(obj, in);
//		buffer_reset(&buf);
//	      }
//	    }
	    buffer_append(&buf, c);
	    c= getc(fp);
	  }
	  ungetc(c, fp);
	  obj= intern(buffer_contents(&buf));
//	  while (nil != in) {
//	    obj= newPair(obj, nil);
//	    obj= newPair(getHead(in), obj);
//	    obj= newPair(s_in, obj);
//	    in= getTail(in);
//	  }
	  GC_UNPROTECT(in);
	  GC_UNPROTECT(obj);
	  return obj;
	}
	fatal(isPrint(c) ? "illegal character: 0x%02x '%c'" : "illegal character: 0x%02x", c, c);
      }
    }
  }
}
    
static void doprint(FILE *stream, oop obj, int storing)
{
  if (!obj) {
    fprintf(stream, "()");
    return;
  }
  if (obj == get(globals, Variable,value)) {
    fprintf(stream, "<globals>");
    return;
  }
  switch (getType(obj)) {
    case Undefined:	fprintf(stream, "UNDEFINED");		break;
    case Long:		fprintf(stream, "%ld", getLong(obj));	break;
    case String: {
      if (!storing)
	fprintf(stream, "%s", get(obj, String,bits));
      else {
	char *p= get(obj, String,bits);
	int c;
	putc('"', stream);
	while ((c= *p++)) {
	  if (c >= ' ' && c < 127)
	    switch (c) {
	      case '"':  printf("\\\"");  break;
	      case '\\': printf("\\\\");  break;
	      default:	 putc(c, stream);  break;
	    }
	  else fprintf(stream, "\\%03o", c);
	}
	putc('"', stream);
      }
      break;
    }
    case Symbol:	fprintf(stream, "%s", get(obj, Symbol,bits));	break;
    case Pair: {
#if 0
      if (nil != get(obj, Pair,source)) {
	oop source= get(obj, Pair,source);
	oop path= car(source);
	oop line= cdr(source);
	fprintf(stream, "<%s:%ld>", get(path, String,bits), getLong(line));
      }
#endif
      fprintf(stream, "(");
      for (;;) {
	doprint(stream, getHead(obj), storing);
	obj= getTail(obj);
	if (!is(Pair, obj)) break;
	fprintf(stream, " ");
      }
      if (nil != obj) {
	fprintf(stream, " . ");
	doprint(stream, obj, storing);
      }
      fprintf(stream, ")");
      break;
    }
    case Array: {
      int i, len= arrayLength(obj);
      fprintf(stream, "Array<%d>(", arrayLength(obj));
      for (i= 0;  i < len;  ++i) {
	if (i) fprintf(stream, " ");
	doprint(stream, arrayAt(obj, i), storing);
      }
      fprintf(stream, ")");
      break;
    }
    case Expr: {
      fprintf(stream, "Expr");
      if (nil != (get(obj, Expr,name))) {
	fprintf(stream, ".");
	doprint(stream, get(obj, Expr,name), storing);
      }
      doprint(stream, cadr(get(obj, Expr,defn)), storing);
      break;
    }
    case Form: {
      fprintf(stream, "Form(");
      doprint(stream, get(obj, Form,function), storing);
      fprintf(stream, ", ");
      doprint(stream, get(obj, Form,symbol), storing);
      fprintf(stream, ")");
      break;
    }
    case Fixed: {
      if (isatty(1)) {
	fprintf(stream, "[1m");
	doprint(stream, get(obj, Fixed,function), storing);
	fprintf(stream, "[m");
      }
      else {
	fprintf(stream, "Fixed<");
	doprint(stream, get(obj, Fixed,function), storing);
	fprintf(stream, ">");
      }
      break;
    }
    case Subr: {
      if (get(obj, Subr,name))
	fprintf(stream, "%s", get(obj, Subr,name));
      else
	fprintf(stream, "Subr<%p>", get(obj, Subr,imp));
      break;
    }
    case Variable: {
      if (!isGlobal(obj) && isatty(1)) fprintf(stream, "[4m");
      doprint(stream, get(obj, Variable,name), 0);
      if (!isGlobal(obj) && isatty(1)) fprintf(stream, "[m");
#if 0
      oop env= get(obj, Variable,env);
      if (nil != env) fprintf(stream, ";%ld+%ld", getLong(get(env, Env,level)), getLong(get(obj, Variable,index)));
#endif
      break;
    }
    case Env: {
      fprintf(stream, "Env%s%s<%ld+%ld:", ((nil == get(obj, Env,parent)) ? "*" : ""), ((nil == get(obj, Env,stable)) ? "=" : ""),
	      getLong(get(obj, Env,level)), getLong(get(obj, Env,offset)));
#if 0
      oop bnd= get(obj, Env,bindings);
      int idx= arrayLength(bnd);
      while (--idx >= 0) {
	doprint(stream, arrayAt(bnd, idx), storing);
	if (idx) fprintf(stream, " ");
      }
#endif
      fprintf(stream, ">");
      break;
    }
    case Context: {
      fprintf(stream, "Context<");
      doprint(stream, get(obj, Context,env), storing);
      fprintf(stream, "=");
      doprint(stream, get(obj, Context,bindings), storing);
      fprintf(stream, ">");
      break;
    }
    default: {
      fprintf(stream, "<type=%i>", getType(obj));
      break;
    }
  }
}

static void print(oop obj)			{ doprint(stdout, obj, 0);  fflush(stdout); }

static void fdump(FILE *stream, oop obj)	{ doprint(stream, obj, 1);  fflush(stream); }
static void dump(oop obj)			{ fdump(stdout, obj); }

static void fdumpln(FILE *stream, oop obj)
{
  fdump(stream, obj);
  fprintf(stream, "\n");
  fflush(stream);
}

static void dumpln(oop obj)			{ fdumpln(stdout, obj); }

static oop apply(oop fun, oop args, oop ctx);

static oop concat(oop head, oop tail)
{
  if (!is(Pair, head)) return tail;
  tail= concat(getTail(head), tail);		GC_PROTECT(tail);
  head= newPairFrom(getHead(head), tail, head);	GC_UNPROTECT(tail);
  return head;
}

static void setSource(oop obj, oop src)
{
  if (!is(Pair, obj)) return;
  if (nil == get(obj, Pair,source)) set(obj, Pair,source, src);
  setSource(getHead(obj), src);
  setSource(getTail(obj), src);
}

static oop exlist(oop obj, oop env);

static oop expand(oop expr, oop env)
{
  if (opt_v > 1) { printf("EXPAND ");  dumpln(expr); }
  if (is(Pair, expr)) {
    oop head= expand(getHead(expr), env);			GC_PROTECT(head);
    if (is(Symbol, head)) {
      oop val= findVariable(env, head);
      if (is(Variable, val)) val= get(val, Variable,value);
      if (is(Form, val) && (nil != get(val, Form,function))) {
	oop args= newPairFrom(env, getTail(expr), expr);	GC_PROTECT(args);
	head= apply(get(val, Form,function), args, nil);	GC_UNPROTECT(args);
	head= expand(head, env);				GC_UNPROTECT(head);
	if (opt_v > 1) { printf("EXPAND => ");  dumpln(head); }
	setSource(head, get(expr, Pair,source));
	return head;
      }
    }
    oop tail= getTail(expr);					GC_PROTECT(tail);
    if (s_quote != head) tail= exlist(tail, env);
    if (s_set == head && is(Pair, car(tail)) && is(Symbol, caar(tail)) /*&& s_in != caar(tail)*/) {
      static struct buffer buf= BUFFER_INITIALISER;
      buffer_reset(&buf);
      buffer_appendAll(&buf, "set-");
      buffer_appendAll(&buf, get(getHead(getHead(tail)), Symbol,bits));
      head= intern(buffer_contents(&buf));
      tail= concat(getTail(getHead(tail)), getTail(tail));
    }
    expr= newPairFrom(head, tail, expr);			GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  }
  else if (is(Symbol, expr)) {
    oop val= findVariable(env, expr);
    if (is(Variable, val)) val= get(val, Variable,value);
    if (is(Form, val) && (nil != get(val, Form,symbol))) {
      oop args= newPair(expr, nil);			GC_PROTECT(args);
      args= newPair(env, args);
      args= apply(get(val, Form,symbol), args, nil);
      args= expand(args, env);				GC_UNPROTECT(args);
      setSource(args, expr);
      return args;
    }
  }
  else {
    oop fn= arrayAt(get(expanders, Variable,value), getType(expr));
    if (nil != fn) {
      oop args= newPair(expr, nil);		GC_PROTECT(args);
      args= apply(fn, args, nil);		GC_UNPROTECT(args);
      setSource(args, expr);
      return args;
    }
  }
  if (opt_v > 1) { printf("EXPAND => ");  dumpln(expr); }
  return expr;
}

static oop exlist(oop list, oop env)
{
  if (!is(Pair, list)) return expand(list, env);
  oop head= expand(getHead(list), env);			GC_PROTECT(head);
  oop tail= exlist(getTail(list), env);			GC_PROTECT(tail);
  head= newPairFrom(head, tail, list);			GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  return head;
}

static oop enlist(oop obj, oop env);

static oop encode(oop expr, oop env)
{
  if (opt_v > 1) { printf("ENCODE ");  dumpln(expr); }
  if (is(Pair, expr)) {
    oop head= encode(getHead(expr), env);			GC_PROTECT(head);
    oop tail= getTail(expr);					GC_PROTECT(tail);
    if (f_let == head) { // (let ENV (bindings...) . body)
      oop args= cadr(expr);
      env= newEnv(env, 0, getLong(get(env, Env,offset)));	GC_PROTECT(env);
      while (is(Pair, args)) {
	oop var= getHead(args);
	if (is(Pair, var)) var= getHead(var);
	define(env, var, nil);
	args= getTail(args);
      }
      tail= enlist(tail, env);
      tail= newPairFrom(env, tail, expr);			GC_UNPROTECT(env);
    }
    else if (f_lambda == head) { // (lambda ENV params . body)
      oop args= car(tail);
      env= newEnv(env, 1, 0);					GC_PROTECT(env);
      while (is(Pair, args)) {
	define(env, getHead(args), nil);
	args= getTail(args);
      }
      if (nil != args) {
	define(env, args, nil);
      }
      tail= enlist(tail, env);
      tail= newPairFrom(env, tail, expr);			GC_UNPROTECT(env);
    }
    else if (f_define == head) {
      oop var= define(get(globals, Variable,value), car(tail), nil);
      tail= enlist(cdr(tail), env);
      tail= newPairFrom(var, tail, expr);
    }
    else if (f_set == head) {
      oop var= findVariable(env, car(tail));
      if (nil == var) fatal("set: undefined variable: %s", get(car(tail), Symbol,bits));
      tail= enlist(cdr(tail), env);
      tail= newPairFrom(var, tail, expr);
    }
    else if (f_quote != head)
      tail= enlist(tail, env);
    expr= newPairFrom(head, tail, expr);			GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  }
  else if (is(Symbol, expr)) {
    oop val= findVariable(env, expr);
    if (nil == val) fatal("undefined variable: %s", get(expr, Symbol,bits));
    expr= val;
    if (isGlobal(expr)) {
      val= get(expr, Variable,value);
      if (is(Form, val) || is(Fixed, val))
	expr= val;
    }
    else {
      oop venv= get(val, Variable,env);
      if (getLong(get(venv, Env,level)) != getLong(get(env, Env,level)))
	set(venv, Env,stable, s_t);
    }
  }
  else {
    oop fn= arrayAt(get(encoders, Variable,value), getType(expr));
    if (nil != fn) {
      oop args= newPair(env, nil);		GC_PROTECT(args);
      args= newPair(expr, args);
      expr= apply(fn, args, nil);		GC_UNPROTECT(args);
    }
  }
  if (opt_v > 1) { printf("ENCODE => ");  dumpln(expr); }
  return expr;
}

static oop enlist(oop list, oop env)
{
  if (!is(Pair, list)) return encode(list, env);
  oop head= encode(getHead(list), env);			GC_PROTECT(head);
  oop tail= enlist(getTail(list), env);			GC_PROTECT(tail);
  head= newPairFrom(head, tail, list);			GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  return head;
}

static oop evlist(oop obj, oop env);

static oop traceStack= nil;
static int traceDepth= 0;

static void fatal(char *reason, ...)
{
  if (reason) {
    va_list ap;
    va_start(ap, reason);
    fprintf(stderr, "\nerror: ");
    vfprintf(stderr, reason, ap);
    fprintf(stderr, "\n");
    va_end(ap);
  }

  oop tracer= get(backtrace, Variable,value);

  if (nil != tracer) {
    oop args= newLong(traceDepth);		GC_PROTECT(args);
    args= newPair(args, nil);
    args= newPair(traceStack, args);
    apply(tracer, args, nil);			GC_UNPROTECT(args);
  }
  else {
    int i= traceDepth;
    while (i--) {
      printf("%3d: ", i);
      oop exp= arrayAt(traceStack, i);
      oop src= get(exp, Pair,source);
      if (nil != src) {
	oop path= car(src);
	oop line= cdr(src);
	if (is(String, path) && is(Long, line))
	  printf("[7m %s %ld [0m ", get(path, String,bits), getLong(line));
      }
      dumpln(arrayAt(traceStack, i));
    }
  }
  exit(1);
}

static oop eval(oop obj, oop ctx)
{
  if (opt_v > 2) { printf("EVAL ");  dump(obj); printf(" IN ");  dumpln(ctx); }
  switch (getType(obj)) {
    case Undefined:
    case Long:
    case String: {
      return obj;
    }
    case Pair: {
      arrayAtPut(traceStack, traceDepth++, obj);
      oop head= eval(getHead(obj), ctx);		GC_PROTECT(head);
      if (is(Fixed, head))
	head= apply(get(head, Fixed,function), getTail(obj), ctx);
      else  {
	oop args= evlist(getTail(obj), ctx);		GC_PROTECT(args);
	head= apply(head, args, ctx);			GC_UNPROTECT(args);
      }							GC_UNPROTECT(head);
      --traceDepth;
      return head;
    }
    case Variable: {
      if (isGlobal(obj)) return get(obj, Variable,value);
      int delta= getLong(get(get(ctx, Context,env), Env,level)) - getLong(get(get(obj, Variable,env), Env,level));
      oop cx= ctx;
      while (delta--) cx= get(cx, Context,home);
      return arrayAt(get(cx, Context,bindings), getLong(get(obj, Variable,index)));
    }
    default: {
      arrayAtPut(traceStack, traceDepth++, obj);
      oop ev= arrayAt(get(evaluators, Variable,value), getType(obj));
      if (nil != ev) {
	oop args= newPair(obj, nil);			GC_PROTECT(args);
	obj= apply(ev, args, ctx);			GC_UNPROTECT(args);
      }
      --traceDepth;
      return obj;
    }
  }
  return nil;
}

static oop evlist(oop obj, oop ctx)
{
  if (!is(Pair, obj)) return obj;
  oop head= eval(getHead(obj), ctx);		GC_PROTECT(head);
  oop tail= evlist(getTail(obj), ctx);		GC_PROTECT(tail);
  head= newPairFrom(head, tail, obj);		GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  return head;
}

static oop apply(oop fun, oop arguments, oop ctx)
{
  if (opt_v > 2) { printf("APPLY ");  dump(fun);  printf(" TO ");  dump(arguments);  printf(" IN ");  dumpln(ctx); }
  switch (getType(fun)) {
    case Expr: {
      oop args=    arguments;
      oop defn=    get(fun, Expr,defn);				GC_PROTECT(defn);
      oop env=     car(defn);
      oop formals= cadr(defn);
      ctx=         newContext(get(fun, Expr,ctx), ctx, env);	GC_PROTECT(ctx);
      oop locals=  get(ctx, Context,bindings);
      oop tmp=     nil;						GC_PROTECT(tmp);
      while (is(Pair, formals)) {
	if (!is(Pair, args)) {
	  fprintf(stderr, "\nerror: too few arguments applying ");
	  fdump(stderr, fun);
	  fprintf(stderr, " to ");
	  fdumpln(stderr, arguments);
	  fatal(0);
	}
	arrayAtPut(locals, getLong(get(getHead(formals), Variable,index)), getHead(args));
	formals= getTail(formals); // xxx formals should be in env with fixed argument arity in defn
	args= getTail(args); // xxx args should be set up in the callee context
      }
      if (is(Variable, formals)) {
	arrayAtPut(locals, getLong(get(formals, Variable,index)), args);
	args= nil;
      }
      if (nil != args) {
	fprintf(stderr, "\nerror: too many arguments applying ");
	fdump(stderr, fun);
	fprintf(stderr, " to ");
	fdumpln(stderr, arguments);
	fatal(0);
      }
      oop ans= nil;
      oop body= cddr(defn);
      while (is(Pair, body)) {
	ans= eval(getHead(body), ctx);
	body= getTail(body);
      }
      GC_UNPROTECT(tmp);
      GC_UNPROTECT(ctx);
      GC_UNPROTECT(defn);
      if (nil != get(env, Env,stable))	set(ctx, Context,callee, nil);
      return ans;
    }
    case Fixed: {
      return apply(get(fun, Fixed,function), arguments, ctx);
    }
    case Subr: {
      return get(fun, Subr,imp)(arguments, ctx);
    }
    default: {
      oop args= arguments;
      oop ap= arrayAt(get(applicators, Variable,value), getType(fun));
      if (nil != ap) {						GC_PROTECT(args);
	arrayAtPut(traceStack, traceDepth++, fun);
	args= newPair(fun, args);
	args= apply(ap, args, ctx);				GC_UNPROTECT(args);
	--traceDepth;
	return args;
      }
      fprintf(stderr, "\nerror: cannot apply: ");
      fdumpln(stderr, fun);
      fatal(0);
    }
  }
  return nil;
}

static int length(oop list)
{
  if (!is(Pair, list)) return 0;
  return 1 + length(getTail(list));
}

static void arity(oop args, char *name)
{
  fatal("wrong number of arguments (%i) in: %s\n", length(args), name);
}

static void arity1(oop args, char *name)
{
  if (!is(Pair, args) || is(Pair, getTail(args))) arity(args, name);
}

static void arity2(oop args, char *name)
{
  if (!is(Pair, args) || !is(Pair, getTail(args)) || is(Pair, getTail(getTail(args)))) arity(args, name);
}

static void arity3(oop args, char *name)
{
  if (!is(Pair, args) || !is(Pair, getTail(args)) || !is(Pair, getTail(getTail(args))) || is(Pair, getTail(getTail(getTail(args))))) arity(args, name);
}

#define subr(NAME)	oop subr_##NAME(oop args, oop ctx)

static subr(if)
{
  if (nil != eval(car(args), ctx))
    return eval(cadr(args), ctx);
  oop ans= nil;
  args= cddr(args);
  while (is(Pair, args)) {
    ans= eval(getHead(args), ctx);
    args= cdr(args);
  }
  return ans;
}

static subr(and)
{
  oop ans= s_t;
  for (;  is(Pair, args);  args= getTail(args))
    if (nil == (ans= eval(getHead(args), ctx)))
      break;
  return ans;
}

static subr(or)
{
  oop ans= nil;
  for (;  is(Pair, args);  args= getTail(args))
    if (nil != (ans= eval(getHead(args), ctx)))
      break;
  return ans;
}

static subr(set)
{
  oop var= car(args);
  if (!is(Variable, var)) {
    fprintf(stderr, "\nerror: cannot set undefined variable: ");
    fdumpln(stderr, var);
    fatal(0);
  }
  oop val= eval(cadr(args), ctx);
  if (is(Expr, val) && (nil == get(val, Expr,name))) set(val, Expr,name, get(var, Variable,name));
  if (isGlobal(var)) return set(var, Variable,value, val);
  int delta= getLong(get(get(ctx, Context,env), Env,level)) - getLong(get(get(var, Variable,env), Env,level));
  oop cx= ctx;
  while (delta--) cx= get(cx, Context,home);
  return arrayAtPut(get(cx, Context,bindings), getLong(get(var, Variable,index)), val);
}

static subr(let)
{
  oop tmp=  nil;		GC_PROTECT(tmp);
  oop bindings= cadr(args);
  oop body= cddr(args);
  oop locals= get(ctx, Context,bindings);
  while (is(Pair, bindings)) {
    oop binding= getHead(bindings);
    if (is(Pair, binding)) {
      oop var=    getHead(binding);
      oop prog=   getTail(binding);
      while (is(Pair, prog)) {
	oop value= getHead(prog);
	tmp= eval(value, ctx);
	prog= getTail(prog);
      }
      arrayAtPut(locals, getLong(get(var, Variable,index)), tmp);
    }
    bindings= getTail(bindings);
  }
  oop ans= nil;			GC_UNPROTECT(tmp);
  while (is(Pair, body)) {
    ans= eval(getHead(body), ctx);
    body= getTail(body);
  }
  return ans;
}

static subr(while)
{
  oop tst= car(args);
  while (nil != eval(tst, ctx)) {
    oop body= cdr(args);
    while (is(Pair, body)) {
      eval(getHead(body), ctx);
      body= getTail(body);
    }
  }
  return nil;
}

static subr(quote)
{
  return car(args);
}

static subr(lambda)
{
  return newExpr(args, ctx);
}

static subr(define)
{
  oop var= car(args);
  if (!is(Variable, var)) {
    fprintf(stderr, "\nerror: non-variable in define: ");
    fdumpln(stderr, var);
    fatal(0);
  }
  oop value= eval(cadr(args), ctx);
  if (is(Expr, value) && (nil == get(value, Expr,name))) set(value, Expr,name, get(var, Variable,name));
  set(var, Variable,value, value);
  return value;
}

static subr(definedP)
{
  oop symbol= car(args);
  oop theenv= cadr(args);
  if (nil == theenv) theenv= get(globals, Variable,value);
  return findVariable(theenv, symbol);
}

#define _do_unary()				\
  _do(com, ~)

#define _do(NAME, OP)								\
  static subr(NAME)								\
  {										\
    arity1(args, #OP);								\
    oop rhs= getHead(args);							\
    if isLong(rhs) return newLong(OP getLong(rhs));				\
    fprintf(stderr, "%s: non-numeric argument: ", #OP);				\
    fdumpln(stderr, rhs);							\
    fatal(0);									\
    return nil;									\
  }

_do_unary()

#undef _do

#define _do_binary()									\
  _do(add,     +)  _do(mul,     *)  _do(div,     /)  _do(mod,  %)			\
  _do(bitand,  &)  _do(bitor,   |)  _do(bitxor,  ^)  _do(shl, <<)  _do(shr, >>)

#define _do(NAME, OP)								\
  static subr(NAME)								\
  {										\
    arity2(args, #OP);								\
    oop lhs= getHead(args);							\
    oop rhs= getHead(getTail(args));						\
    if (isLong(lhs) && isLong(rhs))						\
      return newLong(getLong(lhs) OP getLong(rhs));				\
    fprintf(stderr, "%s: non-numeric argument: ", #OP);				\
    if (!isLong(lhs))	fdumpln(stderr, lhs);					\
    else		fdumpln(stderr, rhs);					\
    fatal(0);									\
    return nil;									\
    }

_do_binary()

#undef _do

static subr(sub)
{
  if (!is(Pair, args)) arity(args, "-");
  oop lhs= getHead(args);  args= getTail(args);
  if (!is(Pair, args)) return newLong(- getLong(lhs));
  oop rhs= getHead(args);  args= getTail(args);
  if (is(Pair, args)) arity(args, "-");
  return newLong(getLong(lhs) - getLong(rhs));
}

#define _do_relation()									\
  _do(lt,   <)  _do(le,  <=)  _do(ge,  >=)  _do(gt,   >)

#define _do(NAME, OP)								\
  static subr(NAME)								\
  {										\
    arity2(args, #OP);								\
    oop lhs= getHead(args);							\
    oop rhs= getHead(getTail(args));						\
    if (isLong(lhs) && isLong(rhs))						\
      return newBool(getLong(lhs) OP getLong(rhs));				\
    fprintf(stderr, "%s: non-numeric argument: ", #OP);				\
    if (!isLong(lhs))	fdumpln(stderr, lhs);					\
    else		fdumpln(stderr, rhs);					\
    fatal(0);									\
    return nil;									\
  }

_do_relation()

#undef _do

static subr(eq)
{
  arity2(args, "=");
  oop lhs= getHead(args);							\
  oop rhs= getHead(getTail(args));						\
  int ans= 0;
  switch (getType(lhs)) {
    case Long:		ans= (isLong(rhs)	&& (getLong(lhs) == getLong(rhs)));				break;
    case String:	ans= (is(String, rhs) 	&& !strcmp(get(lhs, String,bits), get(rhs, String,bits)));	break;
    default:		ans= (lhs == rhs);									break;
  }
  return newBool(ans);
}

static subr(ne)
{
  arity2(args, "!=");
  oop lhs= getHead(args);							\
  oop rhs= getHead(getTail(args));						\
  int ans= 0;
  switch (getType(lhs)) {
    case Long:		ans= (isLong(rhs)	&& (getLong(lhs) == getLong(rhs)));				break;
    case String:	ans= (is(String, rhs) 	&& !strcmp(get(lhs, String,bits), get(rhs, String,bits)));	break;
    default:		ans= (lhs == rhs);									break;
  }
  return newBool(!ans);
}

static subr(exit)
{
  oop n= car(args);
  exit(isLong(n) ? getLong(n) : 0);
}

static subr(abort)
{
  fatal("aborted");
  return nil;
}

static subr(open)
{
  oop arg= car(args);
  if (!is(String, arg)) { fprintf(stderr, "open: non-string argument: ");  fdumpln(stderr, arg);  fatal(0); }
  FILE *stream= (FILE *)fopen(get(arg, String,bits), "rb");
  return stream ? newLong((long)stream) : nil;
}

static subr(close)
{
  oop arg= car(args);
  if (!isLong(arg)) { fprintf(stderr, "close: non-integer argument: ");  fdumpln(stderr, arg);  fatal(0); }
  fclose((FILE *)getLong(arg));
  return arg;
}

static subr(getc)
{
  oop arg= car(args);
  if (nil == arg) arg= get(input, Variable,value);
  if (!isLong(arg)) { fprintf(stderr, "getc: non-integer argument: ");  fdumpln(stderr, arg);  fatal(0); }
  FILE *stream= (FILE *)getLong(arg);
  int c= getc(stream);
  return (EOF == c) ? nil : newLong(c & 255);
}

static subr(read)
{
  FILE *stream= stdin;
  if (nil == args) {
    oop obj= read(stdin);
    if (obj == DONE) obj= nil;
    return obj;
  }
  oop arg= car(args);			if (!is(String, arg)) { fprintf(stderr, "read: non-String argument: ");  fdumpln(stderr, arg);  fatal(0); }
  char *path= get(arg, String,bits);
  stream= fopen(path, "r");
  if (!stream) return nil;
  beginSource(path);
  oop head= newPairFrom(nil, nil, currentSource), tail= head;	GC_PROTECT(head);
  oop obj= nil;							GC_PROTECT(obj);
  for (;;) {
    obj= read(stream);
    if (obj == DONE) break;
    tail= setTail(tail, newPairFrom(obj, nil, currentSource));
    if (stdin == stream) break;
  }
  head= getTail(head);				GC_UNPROTECT(obj);
  fclose(stream);				GC_UNPROTECT(head);
  endSource();
  return head;
}

static subr(expand)
{
  oop x= car(args);  args= cdr(args);		GC_PROTECT(x);
  oop e= car(args);
  if (nil == e) e= get(ctx, Context,env);
  x= expand(x, e);				GC_UNPROTECT(x);
  return x;
}

static subr(encode)
{
  oop x= car(args);  args= cdr(args);		GC_PROTECT(x);
  oop e= car(args);
  if (nil == e) e= get(ctx, Context,env);
  x= encode(x, e);				GC_UNPROTECT(x);
  return x;
}

static subr(eval)
{
  oop x= car(args);  args= cdr(args);				GC_PROTECT(x);
  oop e= car(args);
  if (nil == e) e= newEnv(get(globals, Variable,value), 1, 0);	GC_PROTECT(e);
  x= expand(x, e);
  x= encode(x, e);
  oop c= newBaseContext(nil, nil, e);				GC_PROTECT(c);
  x= eval  (x, c);						GC_UNPROTECT(c);  GC_UNPROTECT(e);  GC_UNPROTECT(x);
  return x;
}

static subr(apply)
{
  oop f= car(args);  args= cdr(args);
  oop a= car(args);  args= cdr(args);
  return apply(f, a, ctx);
}

static subr(type_of)
{
  arity1(args, "type-of");
  return newLong(getType(getHead(args)));
}

static subr(warn)
{
  while (is(Pair, args)) {
    doprint(stderr, getHead(args), 0);
    args= getTail(args);
  }
  return nil;
}

static subr(print)
{
  while (is(Pair, args)) {
    print(getHead(args));
    args= getTail(args);
  }
  return nil;
}

static subr(dump)
{
  while (is(Pair, args)) {
    dump(getHead(args));
    args= getTail(args);
  }
  return nil;
}

static subr(format)
{
  arity2(args, "format");
  oop ofmt= car(args);		if (!is(String, ofmt)) fatal("format is not a string");
  oop oarg= cadr(args);
  char *fmt= get(ofmt, String,bits);
  void *arg= 0;
  switch (getType(oarg)) {
    case Undefined:						break;
    case Long:		arg= (void *)getLong(oarg);		break;
    case String:	arg= (void *)get(oarg, String,bits);	break;
    case Symbol:	arg= (void *)get(oarg, Symbol,bits);	break;
    default:		arg= (void *)oarg;			break;
  }
  size_t size= 100;
  char *p, *np;
  oop ans= nil;
  if (!(p= malloc(size))) return nil;
  for (;;) {
    int n= snprintf (p, size, fmt, arg);
    if (0 <= n && n < size) {
      ans= newString(p);
      free(p);
      break;
    }
    if (n >= 0)	size= n + 1;
    else	size *= 2;
    if (!(np= realloc (p, size))) {
      free(p);
      break;
    }
    p= np;
  }
  return ans;
}

static subr(form)
{
  return newForm(car(args), cadr(args));
}

static subr(fixedP)
{
  arity1(args, "fixed?");
  return newBool(is(Fixed, getHead(args)));
}

static subr(cons)
{
  oop lhs= car(args);
  oop rhs= cadr(args);
  return is(Pair, args) ? newPairFrom(lhs, rhs, args) : newPair(lhs, rhs);
}

static subr(pairP)
{
  arity1(args, "pair?");
  return newBool(is(Pair, getHead(args)));
}

static subr(car)
{
  arity1(args, "car");
  return car(getHead(args));
}

static subr(set_car)
{
  arity2(args, "set-car");
  oop arg= getHead(args);				if (!is(Pair, arg)) return nil;
  return setHead(arg, getHead(getTail(args)));
}

static subr(cdr)
{
  arity1(args, "cdr");
  return cdr(getHead(args));
}

static subr(set_cdr)
{
  arity2(args, "set-cdr");
  oop arg= getHead(args);				if (!is(Pair, arg)) return nil;
  return setTail(arg, getHead(getTail(args)));
}

static subr(formP)
{
  arity1(args, "form?");
  return newBool(is(Form, getHead(args)));
}

static subr(symbolP)
{
  arity1(args, "symbol?");
  return newBool(is(Symbol, getHead(args)));
}

static subr(stringP)
{
  arity1(args, "string?");
  return newBool(is(String, getHead(args)));
}

static subr(string)
{
  oop arg= car(args);
  int num= isLong(arg) ? getLong(arg) : 0;
  return _newString(num);
}

static subr(string_length)
{
  arity1(args, "string-length");
  oop arg= getHead(args);		if (!is(String, arg)) { fprintf(stderr, "string-length: non-String argument: ");  fdumpln(stderr, arg);  fatal(0); }
  return newLong(stringLength(arg));
}

static subr(string_at)
{
  arity2(args, "string-at");
  oop arr= getHead(args);		if (!is(String, arr)) { fprintf(stderr, "string-at: non-String argument: ");  fdumpln(stderr, arr);  fatal(0); }
  oop arg= getHead(getTail(args));	if (!isLong(arg)) return nil;
  int idx= getLong(arg);
  if (0 <= idx && idx < stringLength(arr)) return newLong(255 & get(arr, String,bits)[idx]);
  return nil;
}

static subr(set_string_at)
{
  arity3(args, "set-string-at");
  oop arr= getHead(args);			if (!is(String, arr)) { fprintf(stderr, "set-string-at: non-string argument: ");  fdumpln(stderr, arr);  fatal(0); }
  oop arg= getHead(getTail(args));		if (!isLong(arg)) { fprintf(stderr, "set-string-at: non-integer index: ");  fdumpln(stderr, arg);  fatal(0); }
  oop val= getHead(getTail(getTail(args)));	if (!isLong(val)) { fprintf(stderr, "set-string-at: non-integer value: ");  fdumpln(stderr, val);  fatal(0); }
  int idx= getLong(arg);
  if (0 <= idx && idx < stringLength(arr)) {
    get(arr, String,bits)[idx]= getLong(val);
    return val;
  }
  return nil;
}

static subr(string_symbol)
{
  oop arg= car(args);				if (is(Symbol, arg)) return arg;  if (!is(String, arg)) return nil;
  return intern(get(arg, String,bits));
}

static subr(symbol_string)
{
  oop arg= car(args);				if (is(String, arg)) return arg;  if (!is(Symbol, arg)) return nil;
  return newString(get(arg, Symbol,bits));
}

static subr(long_string)
{
  oop arg= car(args);				if (is(String, arg)) return arg;  if (!isLong(arg)) return nil;
  char buf[32];
  sprintf(buf, "%ld", getLong(arg));
  return newString(buf);
}

static subr(array)
{
  oop arg= car(args);
  int num= isLong(arg) ? getLong(arg) : 0;
  return newArray(num);
}

static subr(arrayP)
{
  return is(Array, car(args)) ? s_t : nil;
}

static subr(array_length)
{
  arity1(args, "array-length");
  oop arg= getHead(args);		if (!is(Array, arg)) { fprintf(stderr, "array-length: non-Array argument: ");  fdumpln(stderr, arg);  fatal(0); }
  return newLong(arrayLength(arg));
}

static subr(array_at)
{
  arity2(args, "array-at");
  oop arr= getHead(args);
  oop arg= getHead(getTail(args));	if (!isLong(arg)) return nil;
  return arrayAt(arr, getLong(arg));
}

static subr(set_array_at)
{
  arity3(args, "set-array-at");
  oop arr= getHead(args);
  oop arg= getHead(getTail(args));		if (!isLong(arg)) return nil;
  oop val= getHead(getTail(getTail(args)));
  return arrayAtPut(arr, getLong(arg), val);
}

static subr(allocate)
{
  arity2(args, "allocate");
  oop type= getHead(args);			if (!isLong(type)) return nil;
  oop size= getHead(getTail(args));		if (!isLong(size)) return nil;
  return _newOops(getLong(type), sizeof(oop) * getLong(size));
}

static subr(oop_at)
{
  arity2(args, "oop-at");
  oop obj= getHead(args);
  oop arg= getHead(getTail(args));	if (!isLong(arg)) return nil;
  return oopAt(obj, getLong(arg));
}

static subr(set_oop_at)
{
  arity3(args, "set-oop-at");
  oop obj= getHead(args);
  oop arg= getHead(getTail(args));		if (!isLong(arg)) return nil;
  oop val= getHead(getTail(getTail(args)));
  return oopAtPut(obj, getLong(arg), val);
}

static subr(not)
{
  arity1(args, "not");
  oop obj= getHead(args);
  return (nil == obj) ? s_t : nil;
}

static subr(verbose)
{
  oop obj= getHead(args);
  if (isLong(obj)) opt_v= getLong(obj);
  return obj;
}

#undef subr

static void replFile(FILE *stream, char *path)
{
  set(input, Variable,value, newLong((long)stream));
  beginSource(path);
  for (;;) {
    if (stream == stdin) {
      printf(".");
      fflush(stdout);
    }
    oop obj= read(stream);
    if (obj == DONE) break;
    GC_PROTECT(obj);
    if (opt_v) {
      dumpln(obj);
      fflush(stdout);
    }
    oop env= newEnv(get(globals, Variable,value), 1, 0);	GC_PROTECT(env);
    obj= expand(obj, env);
    obj= encode(obj, env);
    oop ctx= newBaseContext(nil, nil, env);			GC_PROTECT(ctx);
    obj= eval  (obj, ctx);					GC_UNPROTECT(ctx);  GC_UNPROTECT(env);
    if ((stream == stdin) || (opt_v > 0)) {
      printf(" => ");
      fflush(stdout);
      dumpln(obj);
      fflush(stdout);
    }
    GC_UNPROTECT(obj);
    if (opt_v) {
      GC_gcollect();
      printf("%ld collections, %ld objects, %ld bytes, %4.1f%% fragmentation\n",
	     (long)GC_collections, (long)GC_count_objects(), (long)GC_count_bytes(),
	     GC_count_fragments() * 100.0);
    }
  }
  int c= getc(stream);
  if (EOF != c)				fatal("unexpected character 0x%02x '%c'\n", c, c);
  endSource();
}

static void replPath(char *path)
{
  FILE *stream= fopen(path, "r");
  if (!stream) {
    fprintf(stderr, "\nerror: ");
    perror(path);
    fatal(0);
  }
  fscanf(stream, "#!%*[^\012\015]");
  replFile(stream, path);
  fclose(stream);
}

static void sigint(int signo)
{
  fatal("\nInterrupt");
}

int main(int argc, char **argv)
{
  GC_add_root(&symbols);
  GC_add_root(&globals);
  GC_add_root(&expanders);
  GC_add_root(&encoders);
  GC_add_root(&evaluators);
  GC_add_root(&applicators);
  GC_add_root(&backtrace);

  symbols= newArray(0);

  s_set			= intern("set");
  s_define		= intern("define");
  s_let			= intern("let");
  s_lambda		= intern("lambda");
  s_quote		= intern("quote");
  s_quasiquote		= intern("quasiquote");
  s_unquote		= intern("unquote");
  s_unquote_splicing	= intern("unquote-splicing");
  s_t			= intern("t");
  s_dot			= intern(".");
//s_in			= intern("in");

  oop tmp= nil;		GC_PROTECT(tmp);

  globals= newEnv(nil, 0, 0);
  globals= define(globals, intern("*globals*"), globals);

  expanders=	define(get(globals, Variable,value), intern("*expanders*"),   nil);
  encoders=	define(get(globals, Variable,value), intern("*encoders*"),    nil);
  evaluators=	define(get(globals, Variable,value), intern("*evaluators*"),  nil);
  applicators=	define(get(globals, Variable,value), intern("*applicators*"), nil);

  traceStack=	newArray(32);					GC_add_root(&traceStack);

  backtrace=	define(get(globals, Variable,value), intern("*backtrace*"), nil);
  input=	define(get(globals, Variable,value), intern("*input*"), nil);

  currentPath= nil;			GC_add_root(&currentPath);
  currentLine= nil;			GC_add_root(&currentLine);
  currentSource= newPair(nil, nil);	GC_add_root(&currentSource);

#define _do(NAME, OP)	tmp= newSubr(subr_##NAME, #OP);  define(get(globals, Variable,value), intern(#OP), tmp);
  _do_unary();  _do_binary();  _do(sub, -);  _do_relation();  _do(eq, =);  _do(ne, !=);
#undef _do

  {
    struct { char *name;  imp_t imp; } *ptr, subrs[]= {
      { ".if",		   subr_if },
      { ".and",		   subr_and },
      { ".or",		   subr_or },
      { ".set",		   subr_set },
      { ".let",		   subr_let },
      { ".while",	   subr_while },
      { ".quote",	   subr_quote },
      { ".lambda",	   subr_lambda },
      { ".define",	   subr_define },
      { " defined?",	   subr_definedP },
      { " exit",	   subr_exit },
      { " abort",	   subr_abort },
//    { " current-environment",	   subr_current_environment },
      { " open",	   subr_open },
      { " close",	   subr_close },
      { " getc",	   subr_getc },
      { " read",	   subr_read },
      { " expand",	   subr_expand },
      { " encode",	   subr_encode },
      { " eval",	   subr_eval },
      { " apply",	   subr_apply },
      { " type-of",	   subr_type_of },
      { " warn",	   subr_warn },
      { " print",	   subr_print },
      { " dump",	   subr_dump },
      { " format",	   subr_format },
      { " form",	   subr_form },
      { " fixed?",	   subr_fixedP },
      { " cons",	   subr_cons },
      { " pair?",	   subr_pairP },
      { " car",		   subr_car },
      { " set-car",	   subr_set_car },
      { " cdr",		   subr_cdr },
      { " set-cdr",	   subr_set_cdr },
      { " form?",	   subr_formP },
      { " symbol?",	   subr_symbolP },
      { " string?",	   subr_stringP },
      { " string", 	   subr_string },
      { " string-length",  subr_string_length },
      { " string-at",	   subr_string_at },
      { " set-string-at",  subr_set_string_at },
      { " symbol->string", subr_symbol_string },
      { " string->symbol", subr_string_symbol },
      { " long->string",   subr_long_string },
      { " array",	   subr_array },
      { " array?",	   subr_arrayP },
      { " array-length",   subr_array_length },
      { " array-at",	   subr_array_at },
      { " set-array-at",   subr_set_array_at },
      { " allocate",	   subr_allocate },
      { " oop-at",	   subr_oop_at },
      { " set-oop-at",	   subr_set_oop_at },
      { " not",		   subr_not },
      { " verbose",	   subr_verbose },
      { 0,		   0 }
    };
    for (ptr= subrs;  ptr->name;  ++ptr) {
      tmp= newSubr(ptr->imp, ptr->name + 1);
      if ('.' == ptr->name[0]) tmp= newFixed(tmp);
      define(get(globals, Variable,value), intern(ptr->name + 1), tmp);
    }
  }

  tmp= nil;
  while (--argc) {
    tmp= newPair(nil, tmp);
    setHead(tmp, newString(argv[argc]));
  }	    
  arguments= define(get(globals, Variable,value), intern("*arguments*"), tmp);

  tmp= nil;		GC_UNPROTECT(tmp);

  f_set=    lookup(get(globals, Variable,value), s_set   );		GC_add_root(&f_set);
  f_quote=  lookup(get(globals, Variable,value), s_quote );		GC_add_root(&f_quote);
  f_lambda= lookup(get(globals, Variable,value), s_lambda);		GC_add_root(&f_lambda);
  f_let=    lookup(get(globals, Variable,value), s_let   );		GC_add_root(&f_let);
  f_define= lookup(get(globals, Variable,value), s_define);		GC_add_root(&f_let);

  int repled= 0;

  signal(SIGINT, sigint);

  while (is(Pair, get(arguments, Variable,value))) {
    oop argl= get(arguments, Variable,value);
    oop args= getHead(argl);				GC_PROTECT(args);
    set(arguments, Variable,value, getTail(argl));
    char *arg= get(args, String,bits);
    if 	    (!strcmp(arg, "-v"))	++opt_v;
    else if (!strcmp(arg, "-b"))	++opt_b;
    else {
      if (!opt_b) {
	replPath("boot.l");
	opt_b= 1;
      }
      replPath(arg);
      repled= 1;
    }							GC_UNPROTECT(args);
  }

  if (opt_v) {
    GC_gcollect();
    printf("%ld collections, %ld objects, %ld bytes, %4.1f%% fragmentation\n",
	   (long)GC_collections, (long)GC_count_objects(), (long)GC_count_bytes(),
	   GC_count_fragments() * 100.0);
  }

  if (!repled) {
    if (!opt_b) replPath("boot.l");
    replFile(stdin, "<stdin>");
    printf("\nmorituri te salutant\n");
  }

  return 0;
}
