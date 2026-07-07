CFLAGS ?= -Wall -Wextra -std=c99 -D_GNU_SOURCE
CFLAGS += -I$(STAGING_DIR)/usr/include
CFLAGS += -I$(STAGING_DIR)/usr/include/json-c
LDFLAGS ?=
LDFLAGS += -ljson-c -lpthread

TARGETS = modem_scand modem_scanc

.PHONY: all clean install

all: $(TARGETS)

modem_scand: modem_scand.o
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)
	$(STRIP) $@

modem_scanc: modem_scanc.o
	$(CC) $(CFLAGS) $^ -o $@
	$(STRIP) $@

%.o: %.c modem_scan_common.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o $(TARGETS)

install: all
	install -D modem_scand $(DESTDIR)/usr/bin/modem_scand
	install -D modem_scanc $(DESTDIR)/usr/bin/modem_scanc
