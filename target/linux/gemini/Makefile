# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2009-2018 OpenWrt.org

include $(TOPDIR)/rules.mk

ARCH:=arm
BOARD:=gemini
BOARDNAME:=Cortina Systems CS351x
FEATURES:=squashfs pci rtc usb usbgadget dt gpio display ext4 rootfs-part boot-part
CPU_TYPE:=fa526
SUBTARGETS:=generic

KERNEL_PATCHVER:=6.6
KERNEL_TESTING_PATCHVER:=6.12

define Target/Description
	Build firmware images for the StorLink/Cortina Gemini CS351x ARM FA526 CPU
endef

KERNELNAME:=zImage dtbs

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += \
	kmod-usb-fotg210 \
	kmod-usb-ledtrig-usbport \
	kmod-leds-gpio \
	kmod-gpio-button-hotplug

$(eval $(call BuildTarget))
