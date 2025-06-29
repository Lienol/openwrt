ccflags-y += -g -Wno-incompatible-pointer-types -Wno-unused-variable
#ccflags-y += -DCONFIG_MHI_NETDEV_MBIM
#obj-${CONFIG_PCIE_MHI} := fibo_mhi.o
obj-m := fibo_mhi.o
fibo_mhi-objs := core/mhi_init.o core/mhi_main.o core/mhi_pm.o core/mhi_boot.o core/mhi_dtr.o devices/mhi_netdev.o devices/mhi_uci.o controllers/mhi_qcom.o

PWD := $(shell pwd)
ifeq ($(ARCH),)
ARCH := $(shell uname -m)
endif
ifeq ($(CROSS_COMPILE),)
CROSS_COMPILE :=
endif
ifeq ($(KDIR),)
KDIR := /lib/modules/$(shell uname -r)/build
endif


fibo_mhi: clean
ifeq ($(findstring 86,$(ARCH)), 86)
	cp -f $(PWD)/controllers/mhi_qcom_x86.h $(PWD)/controllers/mhi_qcom.h
else
	cp -f $(PWD)/controllers/mhi_qcom_arm.h $(PWD)/controllers/mhi_qcom.h
endif
	#ln -sf makefile Makefile
	$(MAKE) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -C $(KDIR) M=$(PWD) clean
