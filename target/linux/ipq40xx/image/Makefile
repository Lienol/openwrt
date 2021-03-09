include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

define Device/Default
	PROFILES := Default
	KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
	KERNEL_LOADADDR := 0x80208000
	DEVICE_DTS = $$(SOC)-$(lastword $(subst _, ,$(1)))
	DEVICE_DTS_CONFIG := config@1
	IMAGES := sysupgrade.bin
	IMAGE/sysupgrade.bin = sysupgrade-tar | append-metadata
	IMAGE/sysupgrade.bin/squashfs :=
endef

define Device/century_wr142ac
	$(call Device/FitzImage)
	DEVICE_VENDOR := Century
	DEVICE_MODEL := WR142AC
	SOC := qcom-ipq4019
	KERNEL_SIZE := 4096k
	IMAGE_SIZE := 31232k
	IMAGES += factory.bin
	IMAGE/sysupgrade.bin := append-kernel | append-rootfs | pad-rootfs | append-metadata
	IMAGE/factory.bin := qsdk-ipq-factory-nor | check-size
	DEVICE_PACKAGES := ipq-wifi-century_wr142ac kmod-usb-ledtrig-usbport
endef
TARGET_DEVICES += century_wr142ac

define Device/century_wr142ac-nand
	$(call Device/FitzImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Century
	DEVICE_MODEL := WR142AC
	DEVICE_VARIANT := NAND
	SOC := qcom-ipq4019
	DEVICE_DTS_CONFIG := config@10
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_PACKAGES := ipq-wifi-century_wr142ac kmod-usb-ledtrig-usbport
endef
TARGET_DEVICES += century_wr142ac-nand

include $(SUBTARGET).mk

$(eval $(call BuildImage))
