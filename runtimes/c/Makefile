CFLAGS := -Wall -Werror -fstrict-aliasing -O2

libnile.a: nile.o
	ar rcs $@ $^

%.o: %.c *.h $(MAKEFILE_LIST)
	$(CC) -c $(CFLAGS) $<

clean:
	/bin/rm -rf *.o *.a *.gch
