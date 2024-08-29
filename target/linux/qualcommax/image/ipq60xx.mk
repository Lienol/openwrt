define Device/EmmcImage
	IMAGES += factory.bin sysupgrade.bin
	IMAGE/factory.bin := append-rootfs | pad-rootfs | pad-to 64k
	IMAGE/sysupgrade.bin/squashfs := append-rootfs | pad-to 64k | sysupgrade-tar rootfs=$$$$@ | append-metadata
endef

define Device/8devices_mango-dvk
	$(call Device/FitImageLzma)
	DEVICE_VENDOR := 8devices
	DEVICE_MODEL := Mango-DVK
	IMAGE_SIZE := 27776k
	BLOCKSIZE := 64k
	SOC := ipq6010
	SUPPORTED_DEVICES += 8devices,mango
	IMAGE/sysupgrade.bin := append-kernel | pad-to 64k | append-rootfs | pad-rootfs | check-size | append-metadata
	DEVICE_PACKAGES := ipq-wifi-8devices_mango
endef
TARGET_DEVICES += 8devices_mango-dvk

define Device/cambiumnetworks_xe3-4
       $(call Device/FitImage)
       $(call Device/UbiFit)
       DEVICE_VENDOR := Cambium Networks
       DEVICE_MODEL := XE3-4
       BLOCKSIZE := 128k
       PAGESIZE := 2048
       DEVICE_DTS_CONFIG := config@cp01-c3-xv3-4
       SOC := ipq6010
       DEVICE_PACKAGES := ipq-wifi-cambiumnetworks_xe34 ath11k-firmware-qcn9074 kmod-ath11k-pci
endef
TARGET_DEVICES += cambiumnetworks_xe3-4

define Device/cmiot_ax18
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := CMIOT
	DEVICE_MODEL := AX18
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_DTS := ipq6000-ax18
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-cmiot_ax18 kmod-fs-ext4 mkf2fs f2fsck kmod-fs-f2fs
endef
TARGET_DEVICES += cmiot_ax18

define Device/glinet_gl-ax1800
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := GL-iNet
	DEVICE_MODEL := GL-AX1800
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_DTS := ipq6000-gl-ax1800
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-glinet_gl-ax1800 e2fsprogs dosfstools kmod-fs-ext4 kmod-fs-ntfs kmod-fs-vfat \
		kmod-fs-exfat block-mount kmod-usb-storage kmod-usb2 fdisk
endef
TARGET_DEVICES += glinet_gl-ax1800

define Device/glinet_gl-axt1800
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := GL-iNet
	DEVICE_MODEL := GL-AXT1800
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_DTS := ipq6000-gl-axt1800
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-glinet_gl-axt1800 kmod-hwmon-core e2fsprogs dosfstools kmod-fs-ext4 kmod-fs-ntfs kmod-fs-vfat \
		kmod-fs-exfat kmod-hwmon-pwmfan block-mount kmod-usb-storage kmod-usb2 fdisk
endef
TARGET_DEVICES += glinet_gl-axt1800

define Device/jdcloud_re-cs-02
	$(call Device/FitImage)
	$(call Device/EmmcImage)
	DEVICE_VENDOR := JDCloud
	DEVICE_MODEL := RE-CS-02 (AX6600)
	DEVICE_DTS_CONFIG := config@cp03-c3
	DEVICE_DTS := ipq6010-jdcloud-re-cs-02
	SOC := ipq6010
	DEVICE_PACKAGES := ipq-wifi-jdcloud_re-cs-02 kmod-ath11k-pci ath11k-firmware-qcn9074 kmod-fs-ext4 mkf2fs f2fsck kmod-fs-f2fs luci-app-athena-led
	BLOCKSIZE := 64k
	KERNEL_SIZE := 6144k
	IMAGE/factory.bin := append-kernel | pad-to $${KERNEL_SIZE}  |  append-rootfs | append-metadata
endef
TARGET_DEVICES += jdcloud_re-cs-02

define Device/jdcloud_re-ss-01
	$(call Device/FitImage)
	$(call Device/EmmcImage)
	DEVICE_VENDOR := JDCloud
	DEVICE_MODEL := RE-SS-01 (AX1800 Pro)
	DEVICE_DTS_CONFIG := config@cp03-c2
	DEVICE_DTS := ipq6000-jdcloud-re-ss-01
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-jdcloud_re-ss-01 kmod-fs-ext4 mkf2fs f2fsck kmod-fs-f2fs
	BLOCKSIZE := 64k
	KERNEL_SIZE := 6144k
	IMAGE/factory.bin := append-kernel | pad-to $${KERNEL_SIZE}  |  append-rootfs | append-metadata
endef
TARGET_DEVICES += jdcloud_re-ss-01

define Device/netgear_wax214
       $(call Device/FitImage)
       $(call Device/UbiFit)
       DEVICE_VENDOR := Netgear
       DEVICE_MODEL := WAX214
       BLOCKSIZE := 128k
       PAGESIZE := 2048
       DEVICE_DTS_CONFIG := config@cp03-c1
       SOC := ipq6010
       DEVICE_PACKAGES := ipq-wifi-netgear_wax214
endef
TARGET_DEVICES += netgear_wax214

define Device/qihoo_360v6
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Qihoo
	DEVICE_MODEL := 360V6
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq6000
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_PACKAGES := ipq-wifi-qihoo_360v6
endef
TARGET_DEVICES += qihoo_360v6

define Device/tplink_eap610-outdoor
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := TP-Link
	DEVICE_MODEL := EAP610-Outdoor
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq6018
	DEVICE_PACKAGES := ipq-wifi-tplink_eap610-outdoor
	IMAGES += web-ui-factory.bin
	IMAGE/web-ui-factory.bin := append-ubi | tplink-image-2022
	TPLINK_SUPPORT_STRING := SupportList: \
		EAP610-Outdoor(TP-Link|UN|AX1800-D):1.0 \
		EAP610-Outdoor(TP-Link|JP|AX1800-D):1.0 \
		EAP610-Outdoor(TP-Link|CA|AX1800-D):1.0
endef
TARGET_DEVICES += tplink_eap610-outdoor

define Device/redmi_ax5
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Redmi
	DEVICE_MODEL := AX5
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_DTS := ipq6000-xiaomi-redmi-ax5
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-redmi_ax5
endef
TARGET_DEVICES += redmi_ax5

define Device/redmi_ax5-jdcloud
	$(call Device/FitImage)
	$(call Device/EmmcImage)
	DEVICE_VENDOR := Redmi
	DEVICE_MODEL := AX5 JDCloud
	#BLOCKSIZE := 64k
	KERNEL_SIZE := 6144k
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_DTS := ipq6000-xiaomi-redmi-ax5-jdcloud
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-redmi_ax5-jdcloud
	IMAGE/factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | append-rootfs | append-metadata
endef
TARGET_DEVICES += redmi_ax5-jdcloud

define Device/xiaomi_ax1800
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Xiaomi
	DEVICE_MODEL := AX1800
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@cp03-c1
	DEVICE_DTS := ipq6000-xiaomi-ax1800
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-xiaomi_ax1800
endef
TARGET_DEVICES += xiaomi_ax1800

define Device/yuncore_fap650
    $(call Device/FitImage)
    $(call Device/UbiFit)
    DEVICE_VENDOR := Yuncore
    DEVICE_MODEL := FAP650
    BLOCKSIZE := 128k
    PAGESIZE := 2048
    DEVICE_DTS_CONFIG := config@cp03-c1
    SOC := ipq6018
    DEVICE_PACKAGES := ipq-wifi-yuncore_fap650
    IMAGES := factory.ubi factory.ubin sysupgrade.bin
    IMAGE/factory.ubin := append-ubi | qsdk-ipq-factory-nand
endef
TARGET_DEVICES += yuncore_fap650

