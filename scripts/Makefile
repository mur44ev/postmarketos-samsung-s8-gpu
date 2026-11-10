CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra
PREFIX ?= /usr/local
DESTDIR ?=

all: s8-frame-pump

s8-frame-pump: s8-frame-pump.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

install: s8-frame-pump
	install -D -m 0755 s8-frame-pump $(DESTDIR)$(PREFIX)/bin/s8-frame-pump
	install -D -m 0755 s8-mali-run $(DESTDIR)$(PREFIX)/bin/s8-mali-run
	install -D -m 0755 verify-stock-inputs.sh $(DESTDIR)$(PREFIX)/bin/s8-verify-stock-inputs
	install -D -m 0755 s8-frame-pump.initd $(DESTDIR)/etc/init.d/s8-frame-pump

clean:
	rm -f s8-frame-pump

.PHONY: all install clean
