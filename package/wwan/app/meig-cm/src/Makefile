ifneq ($(CROSS_COMPILE),)
CROSS-COMPILE:=$(CROSS_COMPILE)
endif
#CROSS-COMPILE:=/workspace/buildroot/buildroot-qemu_mips_malta_defconfig/output/host/usr/bin/mips-buildroot-linux-uclibc-
#CROSS-COMPILE:=/workspace/buildroot/buildroot-qemu_arm_vexpress_defconfig/output/host/usr/bin/arm-buildroot-linux-uclibcgnueabi-
#CROSS-COMPILE:=/workspace/buildroot-git/qemu_mips64_malta/output/host/usr/bin/mips-gnu-linux-
ifeq ($(CC),cc)
CC:=$(CROSS-COMPILE)gcc
endif
LD:=$(CROSS-COMPILE)ld

MEIG_CM_SRC=QmiWwanCM.c GobiNetCM.c main.c MPQMUX.c QMIThread.c util.c udhcpc.c qmap_bridge_mode.c mbim-cm.c device.c

release: clean qmi-proxy
	$(CC) -Wall -s ${MEIG_CM_SRC} -o meig-cm -lpthread -ldl

debug: clean
	$(CC) -Wall -g -DCM_DEBUG ${MEIG_CM_SRC} -o meig-cm -lpthread -ldl

qmi-proxy:
	$(CC) -Wall -s meig-qmi-proxy.c  -o meig-qmi-proxy -lpthread -ldl

clean:
	rm -rf meig-cm *~
	rm -rf meig-qmi-proxy
