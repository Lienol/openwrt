# Copyright (C) 2024 Tom <fjrcn@outlook.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-qmodem
LUCI_TITLE:=LuCI support for QWRT Modem
LUCI_PKGARCH:=all
PKG_VERSION:=2.8.1
PKG_LICENSE:=GPLv3
PKG_LINCESE_FILES:=LICENSE
PKG_MAINTAINER:=Tom <fjrcn@outlook.com>
LUCI_DEPENDS:=+luci-compat \
		+kmod-usb2 +kmod-usb3 \
		+kmod-usb-serial +kmod-usb-serial-option +kmod-usb-serial-qualcomm \
		+kmod-usb-net +kmod-usb-acm \
		+kmod-usb-wdm \
		+kmod-usb-net-cdc-ether \
		+kmod-usb-net-cdc-mbim \
		+kmod-usb-net-rndis \
		+kmod-usb-net-cdc-ncm +kmod-usb-net-huawei-cdc-ncm \
		+PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan:kmod-usb-net-qmi-wwan \
		+PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan:kmod-usb-net-qmi-wwan-quectel \
		+PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan:kmod-usb-net-qmi-wwan-fibocom \
		+PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan:kmod-usb-net-qmi-wwan-simcom \
		+usbutils \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_PCI_SUPPORT:kmod-pcie_mhi \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_PCI_SUPPORT:pciutils \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_MTK_T7XX_SUPPORT:umbim \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_MTK_T7XX_SUPPORT:kmod-mtk-t7xx \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_QFIREHOSE_SUPPORT:qfirehose \
		+PACKAGE_luci-app-qmodem_USE_TOM_CUSTOMIZED_QUECTEL_CM:quectel-CM-5G-M \
		+PACKAGE_luci-app-qmodem_USING_NORMAL_QUECTEL_CM:quectel-cm \
		+tom_modem +terminfo \
		+jq +bc\
		+coreutils +coreutils-stat \
		+ndisc6

define Package/luci-app-qmodem/conffiles
/etc/config/qmodem
endef

define Package/luci-app-qmodem/config
choice
  prompt "Qualcomm QMI WWAN Driver Selection"
  default PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan

  config PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan
  bool "Vendor QMI driver"

  config PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan
  bool "Generic QMI driver"
endchoice

choice
  prompt "Quectel Connect Manager Selection"
  default PACKAGE_luci-app-qmodem_USE_TOM_CUSTOMIZED_QUECTEL_CM

	config PACKAGE_luci-app-qmodem_USE_TOM_CUSTOMIZED_QUECTEL_CM
	bool "Tom customized Quectel CM"

	config PACKAGE_luci-app-qmodem_USING_NORMAL_QUECTEL_CM
	bool "NORMAL Quectel-CM"
endchoice

	config PACKAGE_luci-app-qmodem_INCLUDE_ADD_PCI_SUPPORT
		bool "Add PCIe Modem SUPPORT"
		default n

	config PACKAGE_luci-app-qmodem_INCLUDE_ADD_MTK_T7XX_SUPPORT
		bool "Add MTK-T7XX Modem PCI SUPPORT"
		default n

	config PACKAGE_luci-app-qmodem_INCLUDE_ADD_QFIREHOSE_SUPPORT
		bool "Add Qfirehose SUPPORT"
		default n
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
