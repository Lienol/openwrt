# # Cross-compile setup for ImmortalWrt
# STAGING_DIR ?= $(HOME)/qwrt_works/immortalwrt/staging_dir
# TARGET_DIR ?= $(STAGING_DIR)/target-aarch64_generic_musl
# TOOLCHAIN_DIR ?= $(STAGING_DIR)/toolchain-aarch64_generic_gcc-13.3.0_musl

# # Cross-compiler and tools
# CROSS_COMPILE ?= aarch64-openwrt-linux-musl-
# CC = $(TOOLCHAIN_DIR)/bin/$(CROSS_COMPILE)gcc
# AR = $(TOOLCHAIN_DIR)/bin/$(CROSS_COMPILE)ar
# STRIP = $(TOOLCHAIN_DIR)/bin/$(CROSS_COMPILE)strip

# Include and library paths
CFLAGS = -Wall -Wextra -std=c99 -D_GNU_SOURCE
CFLAGS += -I$(TARGET_DIR)/usr/include
CFLAGS += -I$(TARGET_DIR)/usr/include/libubox
CFLAGS += -I$(TARGET_DIR)/usr/include/json-c

LDFLAGS = -L$(TARGET_DIR)/usr/lib
LDFLAGS += -L$(TARGET_DIR)/lib
LDFLAGS += -lubus -lubox -lblobmsg_json -ljson-c -lpthread

TARGET = ubus-at-daemon
SOURCES = main.c port_manager.c at_handler.c event_callback.c config_loader.c
OBJECTS = $(SOURCES:.c=.o)

.PHONY: all clean install debug

all: $(TARGET)

debug:
	@echo "Cross-compile Environment:"
	@echo "  STAGING_DIR: $(STAGING_DIR)"
	@echo "  TARGET_DIR: $(TARGET_DIR)"
	@echo "  TOOLCHAIN_DIR: $(TOOLCHAIN_DIR)"
	@echo "  CC: $(CC)"
	@echo "  CFLAGS: $(CFLAGS)"
	@echo "  LDFLAGS: $(LDFLAGS)"

$(TARGET): $(OBJECTS)
	@echo "Linking $(TARGET)..."
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)
	$(STRIP) $@

%.o: %.c
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(TARGET)

install: $(TARGET)
	install -D $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)

# Test cross-compilation environment
test-env:
	@echo "Testing cross-compilation environment..."
	@if [ ! -d "$(STAGING_DIR)" ]; then \
		echo "ERROR: STAGING_DIR not found: $(STAGING_DIR)"; \
		exit 1; \
	fi
	@if [ ! -d "$(TARGET_DIR)" ]; then \
		echo "ERROR: TARGET_DIR not found: $(TARGET_DIR)"; \
		exit 1; \
	fi
	@if [ ! -d "$(TOOLCHAIN_DIR)" ]; then \
		echo "ERROR: TOOLCHAIN_DIR not found: $(TOOLCHAIN_DIR)"; \
		exit 1; \
	fi
	@if [ ! -f "$(CC)" ]; then \
		echo "ERROR: Cross compiler not found: $(CC)"; \
		exit 1; \
	fi
	@echo "Cross-compilation environment OK!"

# Check available libraries
check-libs:
	@echo "Checking available libraries in target system..."
	@find $(TARGET_DIR)/usr/lib -name "*ubus*" -o -name "*ubox*" -o -name "*json*" | head -10
	@echo "Checking headers..."
	@find $(TARGET_DIR)/usr/include -name "libubus.h" -o -name "libubox.h" -o -name "json.h" | head -10
