#include <stdio.h>
#include <string.h>

union Object;

typedef union Object *oop;

typedef oop (*imp_t)(oop args, oop env);

#define GC_APP_HEADER	int type;  imp_t eval;

#include "gc.c"
#include "buffer.c"

#define nil ((oop)0)

enum { Undefined, Long, String, Symbol, Pair, Array, Expr, Form, Subr };

struct Long	{ long bits; };
struct String	{ char *bits; };
struct Symbol	{ char *bits; };
struct Pair	{ oop 	head, tail; };
struct Expr	{ oop 	defn, env; };
struct Form	{ oop 	function; };
struct Subr	{ imp_t imp; };

union Object {
  struct Long	Long;
  struct String	String;
  struct Symbol	Symbol;
  struct Pair	Pair;
  struct Expr	Expr;
  struct Form	Form;
  struct Subr	Subr;
};

static oop eval_init(oop expr, oop env);
static oop eval_self(oop expr, oop env);

#define setType(OBJ, TYPE)		(ptr2hdr(OBJ)->type= (TYPE))
#define setEval(OBJ, EVAL)		(ptr2hdr(OBJ)->eval= (EVAL))

static inline int   getType(oop obj)	{ return obj ? ptr2hdr(obj)->type : Undefined; }
static inline imp_t getEval(oop obj)	{ return obj ? ptr2hdr(obj)->eval : eval_self; }

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

static oop _newBits(int type, size_t size)	{ oop obj= GC_malloc_atomic(size);  setType(obj, type);  setEval(obj, eval_init);  return obj; }
static oop _newOops(int type, size_t size)	{ oop obj= GC_malloc(size);	    setType(obj, type);  setEval(obj, eval_init);  return obj; }

static oop symbols= nil, s_if= nil, s_and= nil, s_or= nil, s_set= nil, s_let= nil, s_while= nil, s_lambda= nil, s_form= nil, s_define= nil;
static oop s_quote= nil, s_quasiquote= nil, s_unquote= nil, s_unquote_splicing= nil, s_t= nil, s_dot= nil;
static oop globals= nil;

static oop l_zero= nil;

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
static oop newArray(int tally)		{ return _newOops(Array, sizeof(oop) * tally); }
static oop newExpr(oop defn, oop env)	{ oop obj= newOops(Expr);	set(obj, Expr,defn, defn);  set(obj, Expr,env, env);	return obj; }
static oop newForm(oop function)	{ oop obj= newOops(Form);	set(obj, Form,function, function);			return obj; }
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
    case Subr: {
      printf("Subr<%p>", get(obj, Subr,imp));
      break;
    }
    default: {
      fprintf(stderr, "illegal type: %i in print\n", getType(obj));
      exit(1);
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
    case Subr: {
      printf("Subr<%p>", get(obj, Subr,imp));
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
    ass= newPair(name, value);		GC_PROTECT(ass);
    ass= newPair(ass, getTail(env));	GC_UNPROTECT(ass);
    setTail(env, ass);
  }
  return value;
}

#define getLong(X)	get((X), Long,bits)

static oop eval(oop obj, oop env);

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
    case Subr: {
      return get(fun, Subr,imp)(args, env);
    }
    default: {
      printf("cannot apply: ");
      dumpln(fun);
      exit(1);
    }
  }
  return nil;
}

static oop evlist(oop obj, oop env)
{
  if (!is(Pair, obj)) return obj;
  oop head= eval(getHead(obj), env);		GC_PROTECT(head);
  oop tail= evlist(getTail(obj), env);		GC_PROTECT(tail);
  head= newPair(head, tail);			GC_UNPROTECT(tail);  GC_UNPROTECT(head);
  return head;
}

static oop eval_self(oop expr, oop env)		{ return expr; }

static oop eval_symbol(oop expr, oop env)
{
  oop val= assq(expr, env);
  if (!is(Pair, val)) { printf("undefined variable: %s\n", get(expr, Symbol,bits));  exit(1); }
  return getTail(val);
}

static oop eval_if(oop expr, oop env)		// (if tst seq alt)
{
  return eval(((nil == eval(cadr(expr), env)) ? cadddr(expr) : caddr(expr)), env);
}

static oop eval_and(oop expr, oop env)		// (and t1 t2 ...)
{
  oop ans= s_t;
  for (expr= getTail(expr);  is(Pair, expr);  expr= getTail(expr))
    if (nil == (ans= eval(getHead(expr), env))) break;
  return ans;
}

static oop eval_or(oop expr, oop env)		// (or t1 t2 ...)
{
  oop ans= nil;
  for (expr= getTail(expr);  is(Pair, expr);  expr= getTail(expr))
    if (nil != (ans= eval(getHead(expr), env))) break;
  return ans;
}

static oop eval_set(oop expr, oop env)		// (set var val)
{
  oop var= assq(cadr(expr), env);
  if (!is(Pair,var)) {
    printf("cannot set undefined variable: ");
    dumpln(cadr(expr));
    exit(1);
  }
  return setTail(var, eval(caddr(expr), env));
}

static oop eval_let(oop expr, oop env)
{
  oop env2= env;		GC_PROTECT(env2);
  oop tmp=  nil;		GC_PROTECT(tmp);
  oop bindings= cadr(expr);
  oop body= cddr(expr);
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

static oop eval_while(oop expr, oop env)
{
  oop tst=  car(getTail(expr));
  while (nil != eval(tst, env)) {
    oop body= cdr(getTail(expr));
    while (is(Pair, body)) {
      eval(getHead(body), env);
      body= getTail(body);
    }
  }
  return nil;
}

static oop eval_quote(oop expr, oop env)
{
  return car(getTail(expr));
}

static oop eval_lambda(oop expr, oop env)
{
  return newExpr(getTail(expr), env);
}

static oop eval_define(oop expr, oop env)
{
  oop symbol= cadr(expr);
  if (!is(Symbol, symbol)) {
    printf("non-symbol identifier in define: ");
    dumpln(symbol);
    exit(1);
  }
  oop value= eval(caddr(expr), env);		GC_PROTECT(value);
  define(symbol, value, globals);		GC_UNPROTECT(value);
  return value;
}

static oop eval_form(oop expr, oop env)
{
  return eval(getHead(expr), env);
}

static oop eval_pair(oop expr, oop env)
{
  oop head= getHead(expr);
  head= eval(head, env);			GC_PROTECT(head);
  if (is(Form, head)) {
    head= get(head, Form,function);
    head= apply(head, getTail(expr), env);
    setHead(expr, head);
    setEval(expr, eval_form);			GC_UNPROTECT(head);
    return eval(expr, env);
  }
  oop args= evlist(getTail(expr), env);		GC_PROTECT(args);
  head= apply(head, args, env);			GC_UNPROTECT(args);	GC_UNPROTECT(head);
  return head;
}

static oop eval_init(oop expr, oop env)
{
  switch (getType(expr)) {
    case Undefined:
      fprintf(stderr, "eval_init called with nil argument; this cannot happen.\n");
      exit(1);
    case Long:
    case String:
      setEval(expr, eval_self);
      break;
    case Symbol:
      setEval(expr, eval_symbol);
      break;
    case Pair: {
      oop head= getHead(expr);
      if (is(Symbol, head)) {
	if (s_if	== head) { setEval(expr, eval_if);	break; }
	if (s_and	== head) { setEval(expr, eval_and);	break; }
	if (s_or	== head) { setEval(expr, eval_or);	break; }
	if (s_set	== head) { setEval(expr, eval_set);	break; }
	if (s_let	== head) { setEval(expr, eval_let);	break; }
	if (s_while	== head) { setEval(expr, eval_while);	break; }
	if (s_quote	== head) { setEval(expr, eval_quote);	break; }
	if (s_lambda	== head) { setEval(expr, eval_lambda);	break; }
	if (s_define	== head) { setEval(expr, eval_define);	break; }
      }
      setEval(expr, eval_pair);
      break;
    }
    default:
      fprintf(stderr, "EVAL INIT type %i not implemented\n", getType(expr));
      exit(1);
  }
  assert(getEval(expr) != eval_init);
  return getEval(expr)(expr, env);
}

static oop eval(oop expr, oop env)
{
  if (opt_v > 1) { printf("EVAL ");  dumpln(expr); }
  return getEval(expr)(expr, env);
}

static oop do_eval(oop obj, oop env)
{
  switch (getType(obj)) {
    case Undefined:
    case Long:
    case String:
      return obj;
    case Symbol: {
      oop val= assq(obj, env);
      if (!is(Pair, val)) { printf("undefined variable: %s\n", get(obj, Symbol,bits));  exit(1); }
      return getTail(val);
    }
    case Pair: {
    }
    case Expr:
    case Form:
    case Subr: {
      printf("cannot eval: ");
      dumpln(obj);
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

#define subr(NAME)	oop subr_##NAME(oop args, oop env)

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
  _do(add,  +)  _do(mul,  *)  _do(div,  /)  _do(mod,  %)				\
  _do(and,  &)  _do(or,   |)  _do(xor,  ^)  _do(shl, <<)  _do(shr, >>)

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

  s_if			= intern("if");
  s_and			= intern("and");
  s_or			= intern("or");
  s_set			= intern("set");
  s_let			= intern("let");
  s_while		= intern("while");
  s_lambda		= intern("lambda");
  s_form		= intern("form");
  s_define		= intern("define");
  s_quote		= intern("quote");
  s_quasiquote		= intern("quasiquote");
  s_unquote		= intern("unquote");
  s_unquote_splicing	= intern("unquote-splicing");
  s_t			= intern("t");
  s_dot			= intern(".");

  l_zero		= newLong(0);

  oop tmp= nil;		GC_PROTECT(tmp);

  tmp= newPair(intern("*globals*"), globals);
  globals= newPair(tmp, globals);
  set(tmp, Pair,tail, globals);

#define _do(NAME, OP)	tmp= newSubr(subr_##NAME);  define(intern(#OP), tmp, globals);
  _do_unary();  _do_binary();  _do(sub, -);  _do_relation();
#undef _do

  tmp= newSubr(subr_print);	define(intern("print"), tmp, globals);
  tmp= newSubr(subr_form);	define(intern("form"), 	tmp, globals);
  tmp= newSubr(subr_cons);	define(intern("cons"),	tmp, globals);
  tmp= newSubr(subr_pairP);	define(intern("pair?"),	tmp, globals);
  tmp= newSubr(subr_car);	define(intern("car"),	tmp, globals);
  tmp= newSubr(subr_cdr);	define(intern("cdr"),	tmp, globals);
  tmp= newSubr(subr_eq);	define(intern("="),	tmp, globals);
  tmp= newSubr(subr_ne);	define(intern("!="),	tmp, globals);

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
