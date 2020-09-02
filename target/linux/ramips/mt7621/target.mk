#
# Copyright (C) 2009 OpenWrt.org
#

SUBTARGET:=mt7621
BOARDNAME:=MT7621 based boards
FEATURES+=nand ramdisk rtc usb minor
CPU_TYPE:=24kc

DEFAULT_PACKAGES += wpad-basic-wolfssl

define Target/Description
	Build firmware images for Ralink MT7621 based boards.
endef

