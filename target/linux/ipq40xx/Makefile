include $(TOPDIR)/rules.mk

ARCH:=arm
BOARD:=ipq40xx
BOARDNAME:=Qualcomm Atheros IPQ40XX
FEATURES:=squashfs fpu ramdisk nand
CPU_TYPE:=cortex-a7
CPU_SUBTYPE:=neon-vfpv4
MAINTAINER:=John Crispin <john@phrozen.org>
#SUBTARGETS:=generic

# TODO: drop kmod-usb-dwc3-of-simple when migrating to 4.19
KERNEL_PATCHVER:=4.19

KERNELNAME:=zImage Image dtbs

include $(INCLUDE_DIR)/target.mk
DEFAULT_PACKAGES += \
#	kmod-usb-dwc3-of-simple \
#	kmod-leds-gpio kmod-gpio-button-hotplug swconfig \
#	kmod-ath10k-ct wpad-basic \
#	kmod-usb3 kmod-usb-dwc3 ath10k-firmware-qca4019-ct \
#	automount autosamba \
#	ca-certificates htop fdisk e2fsprogs
	kmod-usb-dwc3-of-simple kmod-usb-dwc3-qcom \
	kmod-leds-gpio kmod-gpio-button-hotplug swconfig \
	kmod-ath10k-ct wpad-openssl \
	kmod-usb3 kmod-usb-dwc3 ath10k-firmware-qca4019-ct \
	automount autosamba \
	ca-certificates htop fdisk e2fsprogs
#	luci-app-ipsec-vpnd v2ray shadowsocks-libev-ss-redir shadowsocksr-libev-server luci-app-music-remote-center \
#	luci-app-unblockmusic luci-app-cpufreq luci-app-zerotier luci-app-xlnetacc  kmod-fs-cifs kmod-nls-utf8 \
	

$(eval $(call BuildTarget))
