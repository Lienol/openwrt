MKDIR = @mkdir -p $(@D)
SRCPATH = ./
OBJPATH = obj

BINARY = $(OBJPATH)/libnl-nss.so
SOURCES = $(wildcard $(SRCPATH)/*.c)
OBJECTS = $(SOURCES:$(SRCPATH)/%.c=$(OBJPATH)/%.o)
HEADERS = $(wildcard $(SRCPATH)/*.h)

INCLUDE += -I./include
LDFLAGS = -lnl-3 -lnl-genl-3
EXTRA_CFLAGS = -Wall -Werror -fPIC -Wl,-z,relro -Wl,-z,now
EXTRA_LDFLAGS = -pie -Wl,-z,relro -Wl,-z,now

all: release

release: $(BINARY)

$(OBJPATH)/%.o: $(SRCPATH)/%.c $(HEADERS)
	$(MKDIR)
	@echo [CC] $@
	@$(CC) -c $(CFLAGS) $(INCLUDE) $(EXTRA_CFLAGS) -o $@ $<

$(BINARY): $(OBJECTS)
	@echo $(BINARY)
	@echo [LD] $@
	@$(CC) -shared -o $@ $^ $(LDFLAGS) $(LDLIBS)

clean:
	@echo [Clean]
	@rm -f $(OBJECTS)
	@rm -f $(BINARY)
	@rm -rf $(OBJPATH)

.PHONY: clean
