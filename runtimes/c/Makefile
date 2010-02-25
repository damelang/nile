CFLAGS := -Wall -Werror -Wno-unused -fstrict-aliasing -O2

libnile.a: nile.o
	ar rcs $@ $^

clean:
	$(RM) *.o *.a
