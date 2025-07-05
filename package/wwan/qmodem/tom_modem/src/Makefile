TARGET = tom_modem

CFLAGS ?= -Wall  -Iextlib

SRCS = main.c utils.c operations.c ttydevice.c extlib/pdu.c extlib/ucs2_to_utf8.c

OBJS = $(SRCS:.c=.o)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(OBJS) $(TARGET)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@


.PHONY:clean
clean:
	rm -rf *.o *.*~ *~ *.swap $(all)
	rm -rf $(TARGET)
	rm -rf extlib/*.o
depend:
	$(CC) $(CFLAGS) -MM $(SRCS) > .depend

# 包含依赖文件
ifneq "$(wildcard .depend)" ""
include .depend
endif
