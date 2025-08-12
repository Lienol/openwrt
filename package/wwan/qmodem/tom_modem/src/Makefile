TARGET = tom_modem
ENABLE_UBUS_DAEMON ?= n

CFLAGS += -I$(TARGET_DIR)/usr/include
CFLAGS += -I$(TARGET_DIR)/usr/include/libubox
CFLAGS += -I$(TARGET_DIR)/usr/include/json-c

# Check for UBUS daemon support
ifeq ($(ENABLE_UBUS_DAEMON),y)
    LDFLAGS += -L$(TARGET_DIR)/usr/lib
    LDFLAGS += -L$(TARGET_DIR)/lib
    LDFLAGS += -lubus -lubox -ljson-c -lblobmsg_json
    SRCS = main.c utils.c operations.c transport.c ttydevice.c ubus_client.c extlib/pdu.c extlib/ucs2_to_utf8.c
else
    # TTY-only mode (tom_modem_v1 compatibility)
    SRCS = main.c utils.c operations.c transport.c ttydevice.c extlib/pdu.c extlib/ucs2_to_utf8.c
endif

OBJS = $(SRCS:.c=.o)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

.PHONY: clean
clean:
	rm -rf *.o *.*~ *~ *.swap
	rm -rf $(TARGET)
	rm -rf extlib/*.o
depend:
	$(CC) $(CFLAGS) -MM $(SRCS) > .depend

# 包含依赖文件
ifneq "$(wildcard .depend)" ""
include .depend
endif
