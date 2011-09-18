#include <stdio.h>
#include <string.h>

#define GC_APP_HEADER	int type;

#include "gc.c"
#include "buffer.c"

union Object;

typedef union Object *oop;

typedef oop (*imp_t)(oop args, oop env);

#define nil ((oop)0)

enum { Undefined, Long, String, Symbol, Pair, _Array, Array, Expr, Form, Fixed, Subr, NumTypes };

struct Long	{ long  bits; };
struct String	{ char *bits; };
struct Symbol	{ char *bits; };
struct Pair	{ oop 	head, tail; };
struct Array	{ oop  _array; };
struct Expr	{ oop 	defn, env; };
struct Form	{ oop 	function; };
struct Fixed	{ oop   function; };
struct Subr	{ imp_t imp; };

union Object {
  struct Long	Long;
  struct String	String;
  struct Symbol	Symbol;
  struct Pair	Pair;
  struct Array	Array;
  struct Expr	Expr;
  struct Form	Form;
  struct Fixed	Fixed;
  struct Subr	Subr;
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
    if (obj && !ptr2hdr(obj)->used) {
      fprintf(stderr, "%s:%i: attempt to access dead object %s\n", file, line, name);
      exit(1);
    }
    if (!is(type, obj)) {
      fprintf(stderr, "%s:%i: typecheck failed for %s (%i != %i)\n", file, line, name, type, getType(obj));
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

static oop symbols= nil;
static oop s_quote= nil, s_quasiquote= nil, s_unquote= nil, s_unquote_splicing= nil, s_t= nil, s_dot= nil;
static oop globals= nil, expanders= nil, encoders= nil, applicators= nil;

static int opt_v= 0;

static oop newLong(long bits)		{ oop obj= newBits(Long);	set(obj, Long,bits, bits);				return obj; }

static oop newString(char *cstr)
{
  size_t len= strlen(cstr) + 1;
  char *gstr= GC_malloc_atomic(len);
  memcpy(gstr, cstr, len);			GC_PROTECT(gstr);
  oop obj= newOops(String);
  set(obj, String,bits, gstr);			GC_UNPROTECT(gstr);
  return obj;
}

static oop newSymbol(char *cstr)	{ oop obj= newBits(Symbol);	set(obj, Symbol,bits, strdup(cstr));			return obj; }
static oop newPair(oop head, oop tail)	{ oop obj= newOops(Pair);	set(obj, Pair,head, head);  set(obj, Pair,tail, tail);	return obj; }

static oop newArray(int tally)
{
  oop elts= _newOops(_Array, sizeof(oop) * tally);	GC_PROTECT(elts);
  oop obj=   newOops( Array);				GC_UNPROTECT(elts);
  set(obj, Array,_array, elts);
  return obj;
}

static int arrayLength(oop obj)
{
  if (is(Array, obj))
    return GC_size(get(obj, Array,_array)) / sizeof(oop);
  return 0;
}

static oop arrayAt(oop array, int index)
{
  if (is(Array, array)) {
    oop elts= get(array, Array,_array);
    int size= GC_size(elts) / sizeof(oop);
    if ((unsigned)index < (unsigned)size)
      return ((oop *)elts)[index];
  }
  return nil;
}

static oop arrayAtPut(oop array, int index, oop val)
{
  if (is(Array, array)) {
    oop elts= get(array, Array,_array);
    int size= GC_size(elts) / sizeof(oop);
    if ((unsigned)index >= (unsigned)size) {
      oop oops= _newOops(_Array, sizeof(oop) * (index + 1));
      memcpy((oop *)oops, (oop *)elts, size * sizeof(oop));
      elts= set(array, Array,_array, oops);
    }
    return ((oop *)elts)[index]= val;
  }
  return nil;
}

static oop newExpr(oop defn, oop env)	{ oop obj= newOops(Expr);	set(obj, Expr,defn, defn);  set(obj, Expr,env, env);	return obj; }
static oop newForm(oop function)	{ oop obj= newOops(Form);	set(obj, Form,function, function);			return obj; }
static oop newFixed(oop function)	{ oop obj= newOops(Fixed);	set(obj, Fixed,function, function);			return obj; }
static oop newSubr(imp_t imp)		{ oop obj= newBits(Subr);	set(obj, Subr,imp, imp);				return obj; }

static oop newBool(int b)		{ return b ? s_t : nil; }

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

static int isPrint(int c)	{ return 0 <= c && c <= 127 && (CHAR_PRINT  & chartab[c]); }
static int isDigit(int c)	{ return 0 <= c && c <= 127 && (CHAR_DIGIT  & chartab[c]); }
static int isLetter(int c)	{ return 0 <= c && c <= 127 && (CHAR_LETTER & chartab[c]); }

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
    if (obj == s_dot) {
      obj= read(fp);
      if (obj == (oop)EOF) {
	printf("missing item after .");
	exit(1);
      }
      tail= set(tail, Pair,tail, obj);
      obj= read(fp);
      if (obj != (oop)EOF) {
	printf("extra item after .");
	exit(1);
      }
      goto eof;
    }
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
	oop obj= newString(buffer_contents(&buf));
	//buffer_free(&buf);
	return obj;
      }
      case '\'': {
	oop obj= read(fp);
	GC_PROTECT(obj);
	obj= newPair(obj, nil);
	obj= newPair(s_quote, obj);
	GC_UNPROTECT(obj);
	return obj;
      }
      case '`': {
	oop obj= read(fp);
	GC_PROTECT(obj);
	obj= newPair(obj, nil);
	obj= newPair(s_quasiquote, obj);
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
	obj= newPair(obj, nil);
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
	oop obj= newLong(strtoul(buffer_contents(&buf), 0, 0));
	//buffer_free(&buf);
	return obj;
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
	  oop obj= intern(buffer_contents(&buf));
	  //buffer_free(&buf);
	  return obj;
	}
	fprintf(stderr, "illegal character: 0x%02x", c);
	if (isPrint(c)) fprintf(stderr, " '%c'", c);
	fprintf(stderr, "\n");
	exit(1);
      }
    }
  }
}
    
static void print(oop obj)
{
  if (!obj) {
    printf("nil");
    return;
  }
  if (obj == globals) {
    printf("<globals>");
    return;
  }
  switch (getType(obj)) {
    case Undefined:	printf("UNDEFINED");			break;
    case Long:		printf("%ld", get(obj, Long,bits));	break;
    case String:	printf("%s", get(obj, String,bits));	break;
    case Symbol:	printf("%s", get(obj, Symbol,bits));	break;
    case Pair: {
      printf("(");
      for (;;) {
	if (obj == globals) {
	  printf("<globals>");
	  break;
	}
	print(getHead(obj));
	obj= getTail(obj);
	if (!is(Pair, obj)) break;
	printf(" ");
      }
      if (nil != obj) {
	printf(" . ");
	print(obj);
      }
      printf(")");
      break;
    }
    case Array: {
      int i, len= arrayLength(obj);
      printf("Array(");
      for (i= 0;  i < len;  ++i) {
	if (i) printf(" ");
	print(arrayAt(obj, i));
      }
      printf(")");
      break;
    }
    case Expr: {
      printf("Expr(");
      print(getHead(get(obj, Expr,defn)));
      printf(")");
      break;
    }
    case Form: {
      printf("Form(");
      print(get(obj, Form,function));
      printf(")");
      break;
    }
    case Fixed: {
      printf("Fixed<");
      print(get(obj, Fixed,function));
      printf(">");
      break;
    }
    case Subr: {
      printf("Subr<%p>", get(obj, Subr,imp));
      break;
    }
    default: {
      printf("<type=%i>", getType(obj));
      break;
    }
  }
}

static void dump(oop obj)
{
  if (!obj) {
    printf("nil");
    return;
  }
  if (obj == globals) {
    printf("<globals>");
    return;
  }
  switch (getType(obj)) {
    case Undefined:	printf("UNDEFINED");				break;
    case Long:		printf("%ld", get(obj, Long,bits));		break;
    case String: {
      char *p= get(obj, String,bits);
      int c;
      putchar('"');
      while ((c= *p++)) {
	if (c >= ' ' && c < 127)
	  putchar(c);
	else printf("\\%03o", c);
      }
      putchar('"');
      break;
    }
    case Symbol:	printf("%s", get(obj, Symbol,bits));		break;
    case Pair: {
      printf("(");
      for (;;) {
	if (obj == globals) {
	  printf("<globals>");
	  break;
	}
	dump(getHead(obj));
	obj= getTail(obj);
	if (!is(Pair, obj)) break;
	printf(" ");
      }
      if (nil != obj) {
	printf(" . ");
	dump(obj);
      }
      printf(")");
      break;
    }
    case Array: {
      int i, len= arrayLength(obj);
      printf("Array(");
      for (i= 0;  i < len;  ++i) {
	if (i) printf(" ");
	dump(arrayAt(obj, i));
      }
      printf(")");
      break;
    }
    case Expr: {
      printf("Expr(");
      dump(getHead(get(obj, Expr,defn)));
      printf(")");
      break;
    }
    case Form: {
      printf("Form(");
      dump(get(obj, Form,function));
      printf(")");
      break;
    }
    case Fixed: {
      printf("Fixed<");
      dump(get(obj, Fixed,function));
      printf(">");
      break;
    }
    case Subr: {
      printf("Subr<%p>", get(obj, Subr,imp));
      break;
    }
    default: {
      printf("<type=%i>", getType(obj));
      break;
    }
  }
}

static void dumpln(oop obj)
{
  dump(obj);
  printf("\n");
}

static oop assq(oop key, oop alist)
{
  while (is(Pair, alist)) {
    oop head= getHead(alist);
    if (is(Pair, head) && getHead(head) == key)
      return head;
    alist= getTail(alist);
  }
  return nil;
}

static oop car(oop obj)			{ return is(Pair, obj) ? getHead(obj) : nil; }
static oop cdr(oop obj)			{ return is(Pair, obj) ? getTail(obj) : nil; }

static oop caar(oop obj)		{ return car(car(obj)); }
static oop cadr(oop obj)		{ return car(cdr(obj)); }
static oop cddr(oop obj)		{ return cdr(cdr(obj)); }
static oop cadar(oop obj)		{ return car(cdr(car(obj))); }
static oop caddr(oop obj)		{ return car(cdr(cdr(obj))); }
static oop cadddr(oop obj)		{ return car(cdr(cdr(cdr(obj)))); }

#define setHead(OBJ, VAL)	set(OBJ, Pair,head, VAL)
#define setTail(OBJ, VAL)	set(OBJ, Pair,tail, VAL)

static oop define(oop name, oop value, oop env)
{
  oop ass= assq(name, env);
  if (nil != ass)
    setTail(ass, value);
  else {
    ass= newPair(name, value);			GC_PROTECT(ass);
    oop ent= newPair(ass, getTail(env));	GC_UNPROTECT(ass);
    setTail(env, ent);
  }
  return ass;
}

#define getLong(X)	get((X), Long,bits)

static oop expand(oop expr, oop env);
static oop encode(oop expr, oop env);
static oop eval(oop expr, oop env);
static oop apply(oop fun, oop args, oop env);

static oop expand(oop expr, oop env)
{
  if (opt_v > 1) { printf("EXPAND  ");  dumpln(expr); }
  oop fn= arrayAt(getTail(expanders), getType(expr));
  if (nil != fn) expr= apply(fn, expr, env);
  if (opt_v > 1) { printf("EXPAND= ");  dumpln(expr); }
  return expr;
}

static oop x_literal;

static oop subr_x_literal(oop expr, oop env)
{
  return expr;
}

static oop x_lookup;

static oop subr_x_lookup(oop expr, oop env)
{
  oop value= assq(expr, env);
  if (nil == expr) { printf("undefined: ");  dumpln(getTail(expr));  exit(1); }
  return getTail(value);
}

static oop x_apply;

static oop evlist(oop list, oop env)
{
  if (!is(Pair, list)) return list;
  oop head= eval(getHead(list), env);		GC_PROTECT(head);
  oop tail= evlist(getTail(list), env);		GC_PROTECT(tail);
  head= newPair(head, tail);			GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  return head;
}

static oop subr_x_apply(oop expr, oop env)
{
  oop head= eval(getHead(expr), env);				GC_PROTECT(head);
  if (!is(Fixed, head)) expr= evlist(getTail(expr), env);	GC_PROTECT(expr);
  expr= apply(head, expr, env);					GC_UNPROTECT(expr);
								GC_UNPROTECT(head);
  return expr;
}

static oop subr_encode_literal(oop expr, oop env)
{
  return newPair(x_literal, expr);
}

static oop subr_encode_symbol(oop expr, oop env)
{
  return newPair(x_lookup, expr);
}

static oop subr_encode_pair(oop expr, oop env)
{
  oop head= getHead(expr);			GC_PROTECT(head);
  oop tail;
  if (is(Symbol, head)) {
    oop value= cdr(assq(head, env));
    if (is(Fixed, value))
      head= tail= newPair(value, nil);
    else {
      head= encode(head, env);
      head= tail= newPair(head, nil);
      head= newPair(x_apply, head);
    }
  }
  oop tmp=  nil;				GC_PROTECT(tmp);
  for (expr= getTail(expr);  is(Pair, expr);  expr= getTail(expr), tail= getTail(tail)) {
    tmp= encode(getHead(expr), env);
    setTail(tail, newPair(tmp, nil));
  }						GC_UNPROTECT(tmp);
						GC_UNPROTECT(head);
  return head;
}

static oop encode(oop expr, oop env)
{
  if (opt_v > 1) { printf("ENCODE  ");  dumpln(expr); }
  dumpln(getTail(encoders));
  oop fn= arrayAt(getTail(encoders), getType(expr));
  if (nil == fn) fn= arrayAt(getTail(encoders), 0);
  if (nil == fn) { printf("cannot encode literals -- giving up\n");  exit(1); };
  expr= apply(fn, expr, env);
  if (opt_v > 1) { printf("ENCODE= ");  dumpln(expr); }
  return expr;
}

static oop eval(oop expr, oop env)
{
  if (opt_v > 1) { printf("EVAL  ");  dumpln(expr); }
  expr= apply(getHead(expr), getTail(expr), env);
  if (opt_v > 1) { printf("EVAL= ");  dumpln(expr); }
  return expr;
}

static oop apply(oop fun, oop args, oop env)
{
  if (opt_v > 1) { printf("APPLY ");  dump(fun);  printf(" TO ");  dump(args);  printf(" IN ");  dumpln(env); }
  switch (getType(fun)) {
    case Expr: {
      oop defn= get(fun, Expr,defn);	GC_PROTECT(defn);
      oop formals= car(defn);
      env= get(fun, Expr,env);		GC_PROTECT(env);
      oop tmp= nil;			GC_PROTECT(tmp);
      while (is(Pair, formals)) {
	if (!is(Pair, args)) { printf("too few arguments applying ");  dump(fun);  printf(" to ");  dumpln(args);  exit(1); }
	tmp= newPair(getHead(formals), getHead(args));
	env= newPair(tmp, env);
	formals= getTail(formals);
	args= getTail(args);
      }
      if (is(Symbol, formals)) {
	tmp= newPair(formals, args);
	env= newPair(tmp, env);
	args= nil;
      }
      if (nil != args) { printf("too many arguments applying ");  dump(fun);  printf(" to ");  dumpln(args);  exit(1); }
      oop ans= nil;
      oop body= getTail(defn);
      while (is(Pair, body)) {
	ans= eval(getHead(body), env);
	body= getTail(body);
      }
      GC_UNPROTECT(tmp);
      GC_UNPROTECT(env);
      GC_UNPROTECT(defn);
      return ans;
    }
    case Fixed:
      return apply(get(fun, Fixed,function), args, env);
    case Subr:
      return get(fun, Subr,imp)(args, env);
    default: {
      oop ap= arrayAt(getTail(applicators), getType(fun));
      if (nil != ap) {
	GC_PROTECT(args);
	args= newPair(fun, args);
	args= apply(ap, args, env);
	GC_UNPROTECT(args);
	return args;
      }
      printf("cannot apply: ");
      dumpln(fun);
      exit(1);
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
  fprintf(stderr, "wrong number of arguments (%i) in: %s\n", length(args), name);
  exit(1);
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

#define subr(NAME)	oop subr_##NAME(oop args, oop env)

static subr(if)
{
  oop ans= car(args);
  if (nil != ans) ans= eval(ans, env);
  if (nil != ans) {
    args= cadr(args);
    if (nil != args) ans= eval(args, env);
  }
  else {
    for (args= cddr(args);  is(Pair, args);  args= getTail(args))
      ans= eval(getHead(args), env);
  }
  return ans;
}

static subr(and)
{
  oop ans= s_t;
  for (;  is(Pair, args);  args= getTail(args))
    if (nil == (ans= eval(getHead(args), env)))
      break;
  return ans;
}

static subr(or)
{
  oop ans= nil;
  for (;  is(Pair, args);  args= getTail(args))
    if (nil != (ans= eval(getHead(args), env)))
      break;
  return ans;
}

static subr(set)
{
  oop var= assq(car(args), env);
  if (!is(Pair,var)) {
    printf("cannot set undefined variable: ");
    dumpln(car(args));
    exit(1);
  }
  return setTail(var, eval(cadr(args), env));
}

static subr(let)
{
  oop env2= env;		GC_PROTECT(env2);
  oop tmp=  nil;		GC_PROTECT(tmp);
  oop bindings= car(args);
  oop body= cdr(args);
  while (is(Pair, bindings)) {
    oop binding= getHead(bindings);
    if (is(Pair, binding)) {
      oop symbol= getHead(binding);
      oop value=  car(getTail(binding));
      tmp= eval(value, env);
      tmp= newPair(symbol, tmp);
      env2= newPair(tmp, env2);
    }
    bindings= getTail(bindings);
  }
  oop ans= nil;			GC_UNPROTECT(tmp);
  while (is(Pair, body)) {
    ans= eval(getHead(body), env2);
    body= getTail(body);
  }				GC_UNPROTECT(env2);
  return ans;
}

static subr(while)
{
  oop tst= car(args);
  while (nil != eval(tst, env)) {
    oop body= cdr(args);
    while (is(Pair, body)) {
      eval(getHead(body), env);
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
  return newExpr(args, env);
}

static subr(define)
{
  oop symbol= car(args);
  if (!is(Symbol, symbol)) {
    printf("non-symbol identifier in define: ");
    dumpln(symbol);
    exit(1);
  }
  oop value= eval(cadr(args), env);		GC_PROTECT(value);
  define(symbol, value, globals);		GC_UNPROTECT(value);
  return value;
}

#define _do_unary()				\
  _do(com, ~)  _do(not, !)

#define _do(NAME, OP)								\
  static subr(NAME)								\
  {										\
    arity1(args, #OP);								\
    oop rhs= getHead(args);							\
    return newLong(OP getLong(rhs));						\
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
    return newLong(getLong(lhs) OP getLong(rhs));				\
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
    return newBool(getLong(lhs) OP getLong(rhs));				\
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
    case Long:		ans= (is(Long, rhs)	&& (getLong(lhs) == getLong(rhs)));				break;
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
    case Long:		ans= (is(Long, rhs)	&& (getLong(lhs) == getLong(rhs)));				break;
    case String:	ans= (is(String, rhs) 	&& !strcmp(get(lhs, String,bits), get(rhs, String,bits)));	break;
    default:		ans= (lhs == rhs);									break;
  }
  return newBool(!ans);
}

static subr(exit)
{
  oop n= car(args);
  exit(is(Long, n) ? getLong(n) : 0);
}

static subr(apply)
{
  oop f= car(args);  args= cdr(args);
  oop a= car(args);  args= cdr(args);
  oop e= car(args);  if (nil == e) e= env;
  return apply(f, a, e);
}

static subr(type_of)
{
  arity1(args, "type-of");
  return newLong(getType(getHead(args)));
}

static subr(print)
{
  while (is(Pair, args)) {
    print(getHead(args));
    args= getTail(args);
  }
  return nil;
}

static subr(form)
{
  arity1(args, "form");
  return newForm(getHead(args));
}

static subr(cons)
{
  arity2(args, "cons");
  oop lhs= getHead(args);
  oop rhs= getHead(getTail(args));
  return newPair(lhs, rhs);
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

static subr(cdr)
{
  arity1(args, "cdr");
  return cdr(getHead(args));
}

static subr(array)
{
  arity1(args, "array");
  oop arg= getHead(args);		if (!is(Long, arg)) { fprintf(stderr, "array: non-integer argument: ");  dumpln(arg);  exit(1); }
  return newArray(getLong(arg));
}

static subr(array_at)
{
  arity2(args, "array-at");
  oop arr= getHead(args);
  oop arg= getHead(getTail(args));	if (!is(Long, arg)) return nil;
  return arrayAt(arr, getLong(arg));
}

static subr(set_array_at)
{
  arity3(args, "set-array-at");
  oop arr= getHead(args);
  oop arg= getHead(getTail(args));		if (!is(Long, arg)) return nil;
  oop val= getHead(getTail(getTail(args)));
  return arrayAtPut(arr, getLong(arg), val);
}

#undef subr

static void replFile(FILE *stream)
{
  for (;;) {
    if (stream == stdin) {
      printf(".");
      fflush(stdout);
    }
    oop obj= read(stream);
    if (obj == (oop)EOF) break;
    GC_PROTECT(obj);
    if (opt_v) {
      dumpln(obj);
      fflush(stdout);
    }
    obj= expand(obj, globals);
    obj= encode(obj, globals);
    obj= eval(obj, globals);
    if (stream == stdin) {
      printf(" => ");
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
  if (EOF != c) {
    fprintf(stderr, "unexpected character 0x%02x '%c'\n", c, c);
    exit(1);
  }
}

static void replPath(char *path)
{
  FILE *stream= fopen(path, "r");
  if (!stream) {
    perror(path);
    exit(1);
  }
  replFile(stream);
  fclose(stream);
}

int main(int argc, char **argv)
{
  GC_add_root(&symbols);
  GC_add_root(&globals);
  GC_add_root(&expanders);
  GC_add_root(&encoders);
  GC_add_root(&applicators);

  s_quote		= intern("quote");
  s_quasiquote		= intern("quasiquote");
  s_unquote		= intern("unquote");
  s_unquote_splicing	= intern("unquote-splicing");
  s_t			= intern("t");
  s_dot			= intern(".");

  oop tmp= nil;		GC_PROTECT(tmp);

  tmp= newPair(intern("*globals*"), globals);
  globals= newPair(tmp, globals);
  set(tmp, Pair,tail, globals);

  x_literal= newSubr(subr_x_literal);		GC_add_root(&x_literal);
  x_lookup=  newSubr(subr_x_lookup);		GC_add_root(&x_lookup);
  x_apply=   newSubr(subr_x_apply);		GC_add_root(&x_apply);

  expanders=   define(intern("*expanders*"),   newArray(NumTypes), globals);

  encoders=    define(intern("*encoders*"),    newArray(NumTypes), globals);

  arrayAtPut(getTail(encoders), Undefined, newSubr(subr_encode_literal));
  arrayAtPut(getTail(encoders), Symbol,    newSubr(subr_encode_symbol));
  arrayAtPut(getTail(encoders), Pair,      newSubr(subr_encode_pair));

  applicators= define(intern("*applicators*"), newArray(NumTypes), globals);

#define _do(NAME, OP)	tmp= newSubr(subr_##NAME);  define(intern(#OP), tmp, globals);
  _do_unary();  _do_binary();  _do(sub, -);  _do_relation();
#undef _do

  {
    struct { char *name;  imp_t imp; } *ptr, subrs[]= {
      { ".if",		 subr_if },
      { ".and",		 subr_and },
      { ".or",		 subr_or },
      { ".set",		 subr_set },
      { ".let",		 subr_let },
      { ".while",	 subr_while },
      { ".quote",	 subr_quote },
      { ".lambda",	 subr_lambda },
      { ".define",	 subr_define },
      { " exit",	 subr_exit },
      { " apply",	 subr_apply },
      { " type-of",	 subr_type_of },
      { " print",	 subr_print },
      { " form",	 subr_form },
      { " cons",	 subr_cons },
      { " pair?",	 subr_pairP },
      { " car",		 subr_car },
      { " cdr",		 subr_cdr },
      { " array",	 subr_array },
      { " array-at",	 subr_array_at },
      { " set-array-at", subr_set_array_at },
      { " ~",		 subr_com },
      { " !",		 subr_not },
      { " +",		 subr_add },
      { " -",		 subr_sub },
      { " *",		 subr_mul },
      { " /",		 subr_div },
      { " %",		 subr_mod },
      { " &",		 subr_bitand },
      { " |",		 subr_bitor },
      { " ^",		 subr_bitxor },
      { " <<",		 subr_shl },
      { " >>",		 subr_shr },
      { " <",		 subr_lt },
      { " <=",		 subr_le },
      { " =",		 subr_eq },
      { " !=",		 subr_ne },
      { " >=",		 subr_ge },
      { " >",		 subr_gt },
      { 0,		0 }
    };
    for (ptr= subrs;  ptr->name;  ++ptr) {
      tmp= newSubr(ptr->imp);
      if ('.' == ptr->name[0]) tmp= newFixed(tmp);
      define(intern(ptr->name + 1), tmp, globals);
    }
  }

  tmp= nil;		GC_UNPROTECT(tmp);

  int repled= 0;

  while (argc-- > 1) {
    ++argv;
    if (!strcmp(*argv, "-v"))	++opt_v;
    else {
      replPath(*argv);
      repled= 1;
    }
  }

  if (opt_v) {
    GC_gcollect();
    printf("%ld collections, %ld objects, %ld bytes, %4.1f%% fragmentation\n",
	   (long)GC_collections, (long)GC_count_objects(), (long)GC_count_bytes(),
	   GC_count_fragments() * 100.0);
  }

  if (!repled) {
    replFile(stdin);
    printf("\nmorituri te salutant\n");
  }

  return 0;
}
