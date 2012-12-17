NOW = $(shell date '+%Y%m%d.%H%M')
SYS = $(shell uname)

OFLAGS = -O3 -fomit-frame-pointer -DNDEBUG
CFLAGS = -Wall -g $(OFLAGS)
CC32 = $(CC) -m32

ifeq ($(findstring MINGW32,$(SYS)),MINGW32)
LIBS = -lm -lffi libw32dl.a
TIME =
else
LIBS = -lm -lffi -ldl
TIME = time
endif

ifeq ($(findstring Darwin,$(SYS)),Darwin)
SO = dylib
SOCFLAGS = -dynamiclib -Wl,-headerpad_max_install_names,-undefined,dynamic_lookup,-flat_namespace
else
SO = so
SOCFLAGS = -shared -msse -msse2
endif

.SUFFIXES :

all : eval2 eval eval32 osdefs.k

run : all
	rlwrap ./eval

status : .force
	@echo "SYS is $(SYS)"

eval : eval.c gc.c gc.h buffer.c chartab.h wcs.c
	$(CC) -g $(CFLAGS) -o eval eval.c $(LIBS)
	@-test ! -x /usr/sbin/execstack || /usr/sbin/execstack -s $@

eval2 : eval2.c gc.c gc.h buffer.c chartab.h wcs.c osdefs.k
	$(CC) -g $(CFLAGS) -o eval2 eval2.c $(LIBS)
	@-test ! -x /usr/sbin/execstack || /usr/sbin/execstack -s $@

check-maru : eval2
	./eval2 ir-gen-c.k maru.k maru-nfibs.k
	./eval2 ir-gen-c.k maru.k maru-gc.k
	./eval2 ir-gen-c.k maru.k maru-test.k

check-marux : eval2
	./eval2 ir-gen-x86.k maru.k maru-nfibs.k
	./eval2 ir-gen-x86.k maru.k maru-gc.k
	./eval2 ir-gen-x86.k maru.k maru-test.k

test-maru : eval2
	./eval2 ir-gen-c.k maru.k maru-nfibs.k	> test.c && cc -fno-builtin -g -o test test.c -ldl && ./test 32
	./eval2 ir-gen-c.k maru.k maru-gc.k	> test.c && cc -fno-builtin -g -o test test.c -ldl && ./test 32
	./eval2 ir-gen-c.k maru.k maru-test.k	> test.c && cc -fno-builtin -g -o test test.c -ldl && ./test 32

test2-maru : eval2
	./eval2 ir-gen-x86.k maru.k maru-test2.k > test.s && cc -fno-builtin -g -o test2 test2.c test.s && ./test2 15

test3-maru : eval2
	./eval2 ir-gen-x86.k maru.k maru-test3.k > test.s && cc -m32 -fno-builtin -g -o test3 test.s && ./test3

maru-check : eval2 .force
	./eval2 ir-gen-x86.k maru.k maru-check.k > maru-check.s
	cc -m32 -o maru-check maru-check.s
	./maru-check

maru-check-c : eval2 .force
	./eval2 ir-gen-c.k maru.k maru-check.k > maru-check.c
	cc -o maru-check maru-check.c
	./maru-check

maru-bench : eval2 .force
	cc -O2 -fomit-frame-pointer -mdynamic-no-pic -o nfibs nfibs.c
	./eval2 ir-gen-x86.k maru.k maru-nfibs.k > maru-nfibs.s
	cc -O2 -fomit-frame-pointer -mdynamic-no-pic -o maru-nfibs maru-nfibs.s
	time ./nfibs 38
	time ./nfibs 38
	time ./maru-nfibs 38
	time ./maru-nfibs 38

eval32 : eval.c gc.c gc.h buffer.c chartab.h wcs.c
	$(CC32) -g $(CFLAGS) -o eval32 eval.c $(LIBS)
	@-test ! -x /usr/sbin/execstack || /usr/sbin/execstack -s $@

gceval : eval.c libgc.c buffer.c chartab.h wcs.c
	$(CC) -g $(CFLAGS) -DLIB_GC=1 -o gceval eval.c $(LIBS) -lgc
	@-test ! -x /usr/sbin/execstack || /usr/sbin/execstack -s $@

debug : .force
	$(MAKE) OFLAGS="-O0"

debuggc : .force
	$(MAKE) CFLAGS="$(CFLAGS) -DDEBUGGC=1"

profile : .force
	$(MAKE) clean eval CFLAGS="$(CFLAGS) -O3 -fno-inline-functions -DNDEBUG"
#	shark -q -1 -i ./eval emit.l eval.l eval.l eval.l eval.l eval.l eval.l eval.l eval.l eval.l eval.l > test.s
	shark -q -1 -i ./eval repl.l test-pepsi.l

osdefs.k : mkosdefs
	./mkosdefs > $@

mkosdefs : mkosdefs.c
	$(CC) -o $@ $<

cg : eval .force
	./eval codegen5.l | tee test.s
	as test.s
	ld  --build-id --eh-frame-hdr -m elf_i386 --hash-style=both -dynamic-linker /lib/ld-linux.so.2 -o test /usr/lib/gcc/i486-linux-gnu/4.4.5/../../../../lib/crt1.o /usr/lib/gcc/i486-linux-gnu/4.4.5/../../../../lib/crti.o /usr/lib/gcc/i486-linux-gnu/4.4.5/crtbegin.o -L/usr/lib/gcc/i486-linux-gnu/4.4.5 -L/usr/lib/gcc/i486-linux-gnu/4.4.5 -L/usr/lib/gcc/i486-linux-gnu/4.4.5/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/i486-linux-gnu/4.4.5/../../.. a.out -lgcc --as-needed -lgcc_s --no-as-needed -lc -lgcc --as-needed -lgcc_s --no-as-needed /usr/lib/gcc/i486-linux-gnu/4.4.5/crtend.o /usr/lib/gcc/i486-linux-gnu/4.4.5/../../../../lib/crtn.o
	./test

test : emit.l eval.l eval
	$(TIME) ./eval -O emit.l eval.l > test.s && $(CC32) -c -o test.o test.s && size test.o && $(CC32) -o test test.o

time : .force
	$(TIME) ./eval -O emit.l eval.l eval.l eval.l eval.l eval.l > /dev/null

test2 : test .force
	$(TIME) ./test -O boot.l emit.l eval.l > test2.s
	diff test.s test2.s

time2 : .force
	$(TIME) ./test boot.l emit.l eval.l eval.l eval.l eval.l eval.l > /dev/null

test-eval : test .force
	$(TIME) ./test test-eval.l

test-boot : test .force
	$(TIME) ./test boot-emit.l

test-emit : eval .force
	./emit.l test-emit.l | tee test.s && $(CC32) -c -o test.o test.s && size test.o && $(CC32) -o test test.o && ./test

peg.l : eval parser.l peg-compile.l peg-boot.l peg.g
	-rm peg.l.new
	./eval parser.l peg-compile.l peg-boot.l > peg.l.new
	-mv peg.l peg.l.$(shell date '+%Y%m%d.%H%M%S')
	mv peg.l.new peg.l

test-repl : eval peg.l .force
	./eval repl.l test-repl.l

test-peg : eval peg.l .force
	$(TIME) ./eval parser.l peg.l test-peg.l > peg.n
	$(TIME) ./eval parser.l peg.n test-peg.l > peg.m
	diff peg.n peg.m

test-compile-grammar :
	./eval compile-grammar.l test-dc.g > test-dc.g.l
	./eval compile-dc.l test.dc

test-compile-irgol : eval32 irgol.g.l .force
	./eval compile-irgol.l test.irgol > test.c
	$(CC32) -fno-builtin -g -o test test.c
	@echo
	./test

irgol.g.l : tpeg.l irgol.g
	./eval compile-tpeg.l irgol.g > irgol.g.l

test-irgol : eval .force
	./eval irgol.k |tee test.c
	$(CC32) -fno-builtin -g -o test test.c
	@echo
	./test

test-compile-irl : eval32 irl.g.l .force
	./eval compile-irl.l test.irl > test.c
	$(CC32) -fno-builtin -g -o test test.c
	@echo
	./test

irl.g.l : tpeg.l irl.g
	./eval compile-tpeg.l irl.g > irl.g.l

test-ir : eval .force
	./eval test-ir.k > test.c
	$(CC32) -fno-builtin -g -o test test.c
	@echo
	./test

tpeg.l : tpeg.g compile-peg.l compile-tpeg.l
	$(TIME) ./eval compile-peg.l  tpeg.g > tpeg.l.new
	-test -f tpeg.l && cp tpeg.l tpeg.l.$(NOW)
	mv tpeg.l.new tpeg.l
	$(TIME) ./eval compile-tpeg.l tpeg.g > tpeg.ll
	sort tpeg.l > tpeg.ls
	sort tpeg.ll > tpeg.lls
	diff tpeg.ls tpeg.lls
	rm tpeg.ls tpeg.ll tpeg.lls

test-mach-o : eval32 .force
	./eval32 test-mach-o.l
	@echo
	size a.out
	chmod +x a.out
	@echo
	./a.out

test-elf : eval32 .force
	./eval32 test-elf.l
	@echo
	size a.out
	chmod +x a.out
	@echo
	./a.out

test-assembler : eval32 .force
	./eval32 assembler.k

test-recursion2 :
	./eval compile-grammar.l test-recursion2.g > test-recursion2.g.l
	./eval compile-recursion2.l test-recursion2.txt

test-main : eval32 .force
	$(TIME) ./eval32 test-main.k
	chmod +x test-main
	$(TIME) ./test-main hello world

test-main2 : eval32 .force
	$(TIME) ./eval32 test-pegen.k save.k test-pegen
	chmod +x test-pegen
	$(TIME) ./test-pegen

cpp.g.l : cpp.g tpeg.l
	./eval compile-tpeg.l $< > $@.new
	mv $@.new $@

test-cpp : eval cpp.g.l .force
	./eval compile-cpp.l cpp-small-test.c

osdefs.g.l : osdefs.g tpeg.l
	./eval compile-tpeg.l $< > $@.new
	mv $@.new $@

%.osdefs.k : %.osdefs osdefs.g.l
	./eval compile-osdefs.l $< > $<.c
	cc -o $<.exe $<.c
	./$<.exe > $@.new
	mv $@.new $@
	rm -f $<.exe $<.c

OSDEFS = $(wildcard *.osdefs) $(wildcard net/*.osdefs)
OSKEFS = $(OSDEFS:.osdefs=.osdefs.k)

osdefs : osdefs.g.l $(OSKEFS) .force

profile-peg : .force
	$(MAKE) clean eval CFLAGS="-O3 -fno-inline-functions -g -DNDEBUG"
	shark -q -1 -i ./eval parser.l peg.n test-peg.l > peg.m

NILE = ../nile
GEZIRA = ../gezira

libs : libnile.$(SO) libgezira.$(SO)

libnile.$(SO) : .force
	$(CC) -I$(NILE)/runtimes/c -O3 -ffast-math -fPIC -fno-common $(SOCFLAGS) -o $@ $(NILE)/runtimes/c/nile.c

libgezira.$(SO) : .force
	$(CC) -I$(NILE)/runtimes/c -O3 -ffast-math -fPIC -fno-common $(SOCFLAGS) -o $@ $(GEZIRA)/c/gezira.c $(GEZIRA)/c/gezira-image.c

stats : .force
	cat boot.l emit.l | sed 's/.*debug.*//;s/;.*//' | sort -u | wc -l
	cat eval.l | sed 's/.*debug.*//;s/;.*//' | sort -u | wc -l
	cat boot.l emit.l eval.l | sed 's/.*debug.*//;s/;.*//' | sort -u | wc -l

clean : .force
	rm -f irl.g.l irgol.g.l osdefs.k test.c tpeg.l a.out
	rm -f *~ *.o main eval eval32 eval2 gceval test *.s mkosdefs *.exe *.$(SO)
	rm -f test-main test-pegen
	rm -rf *.dSYM *.mshark
	rm -rf osdefs.g.l *.osdefs.k

#----------------------------------------------------------------

FILES = Makefile \
	wcs.c buffer.c chartab.h eval.c gc.c gc.h \
	boot.l emit.l eval.l test-emit.l \
	parser.l peg-compile.l peg-compile-2.l peg-boot.l peg.l test-peg.l test-repl.l \
	repl.l repl-2.l mpl.l sim.l \
	peg.g

DIST = maru-$(NOW)
DEST = ckpt/$(DIST)

dist : .force
	mkdir -p $(DEST)
	cp -p $(FILES) $(DEST)/.
	$(SHELL) -ec "cd ckpt; tar cvfz $(DIST).tar.gz $(DIST)"

.force :
