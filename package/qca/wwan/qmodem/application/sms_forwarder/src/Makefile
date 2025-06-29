CC ?= gcc
CFLAGS += -Wall -std=c99
LDFLAGS += -ljson-c

TARGET = sms_forwarder
SOURCES = main.c
LDFLAGS = -L$(TARGET_DIR)/usr/lib
LDFLAGS += -L$(TARGET_DIR)/lib
LDFLAGS += -ljson-c

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

debug_test: debug_test.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(TARGET) debug_test

.PHONY: all clean
