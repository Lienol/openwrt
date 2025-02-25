obj-m := qmi_wwan_m.o
GobiNet-objs := qmi_wwan_m.o

PWD := $(shell pwd)
OUTPUTDIR=/lib/modules/`uname -r`/kernel/drivers/net/usb/

ifeq ($(ARCH),)
ARCH := $(shell uname -m)
endif
ifeq ($(CROSS_COMPILE),)
CROSS_COMPILE :=
endif
ifeq ($(KDIR),)
KDIR := /lib/modules/$(shell uname -r)/build
ifeq ($(ARCH),i686)
ifeq ($(wildcard $KDIR/arch/$ARCH),)
ARCH=i386
endif
endif
endif

default:
	ln -sf makefile Makefile
	$(MAKE) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}  -C $(KDIR) M=$(PWD) modules

install: default
	mkdir -p $(OUTPUTDIR)
	cp -f qmi_wwan_m.ko $(OUTPUTDIR)
	depmod
	modprobe -r qmi_wwan_m
	modprobe qmi_wwan_m

clean:
	rm -rf Makefile
	rm -rf *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions Module.* modules.order
