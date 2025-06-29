DIRS = pdu_lib

#CROSS_COMPILE=mips-openwrt-linux-
#CC = $(CROSS_COMPILE)gcc
#STRIP = $(CROSS_COMPILE)strip
#CFLAGS = -O2
EXE = sms_tool

OBJS = pdu_lib/pdu.o pdu_lib/ucs2_to_utf8.o

all: $(EXE)

$(EXE): sms_main.o pdu_lib
	$(CC) $(CFLAGS) sms_main.o $(OBJS) -lm -o $(EXE)

sms_main.o:
	$(CC) $(CFLAGS) sms_main.c -c

pdu_lib: force_look
	cd pdu_lib; CROSS_COMPILE=$(CROSS_COMPILE) $(MAKE) $(MFLAGS)

clean:
	rm -rf *.o sms_tool
	for d in $(DIRS); do (cd $$d; $(MAKE) clean); done

strip:
	$(STRIP) -s sms_tool

force_look:
	true

