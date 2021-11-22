
# ----------------------------------------------------------------------
# adjust the following to the location of your Lua directory
# or include files and executable

LUADIR= ../lua
LUAINC= -I$(LUADIR)/include
LUAEXE= $(LUADIR)/bin/lua


# ----------------------------------------------------------------------

CC= gcc
AR= ar

CFLAGS= -Os -fPIC $(LUAINC) 
LDFLAGS= -fPIC

OBJS= lualinux.o

lualinux.so:  lualinux.c
	$(CC) -c $(CFLAGS) lualinux.c
	$(CC) -shared $(LDFLAGS) -o lualinux.so $(OBJS)
	strip lualinux.so

test: lualinux.so
	$(LUAEXE) ./test.lua

clean:
	rm -f *.o *.a *.so

.PHONY: clean test


