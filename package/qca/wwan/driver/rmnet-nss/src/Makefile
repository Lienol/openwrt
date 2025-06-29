obj-m += rmnet_nss.o

KDIR ?= /lib/modules/$(shell uname -r)/build

KERNEL_MAKE_OPTS := -C $(KDIR) M=$(CURDIR)
ifneq ($(ARCH),)
KERNEL_MAKE_OPTS += ARCH=$(ARCH)
endif
ifneq ($(CROSS_COMPILE),)
KERNEL_MAKE_OPTS += CROSS_COMPILE=$(CROSS_COMPILE)
endif
ifneq ($(INSTALL_MOD_PATH),)
KERNEL_MAKE_OPTS += INSTALL_MOD_PATH=$(INSTALL_MOD_PATH)
endif

PWD := $(shell pwd)

default:
	$(MAKE) $(KERNEL_MAKE_OPTS) modules

install: modules_install

modules_install:
	$(MAKE) $(KERNEL_MAKE_OPTS) modules_install

install: default
	install -m 644 $(PWD)/*.ko /lib/modules/$(shell uname -r)/kernel/drivers/net/usb/
	depmod

clean:
	rm -rf *~ .tmp_versions modules.order Module.symvers
	find . -type f -name "*~" -o -name "*.o" -o -name "*.ko" -o -name "*.cmd" -o -name "*.mod.c" |  xargs rm -rf
