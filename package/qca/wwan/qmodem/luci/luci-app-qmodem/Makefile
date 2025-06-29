# Copyright (C) 2024 Tom <fjrcn@outlook.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=luci-app-qmodem
LUCI_TITLE:=LuCI support for QWRT Modem
LUCI_PKGARCH:=all
PKG_VERSION:=$(QMODEM_VERSION)
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_LICENSE:=GPLv3
PKG_LINCESE_FILES:=LICENSE
PKG_MAINTAINER:=Tom <fjrcn@outlook.com>
LUCI_DEPENDS:=+luci-compat \
		+qmodem 


define Package/luci-app-qmodem/conffiles
/etc/config/qmodem
endef

define Package/luci-app-qmodem/config

choice
  prompt "IPv6 Neighbor Discovery Selection"
  default PACKAGE_luci-app-qmodem_INCLUDE_ndisc6

  config PACKAGE_luci-app-qmodem_INCLUDE_ndisc6
  bool "Include ndisc6 for IPv6 Neighbor Discovery"

  config PACKAGE_luci-app-qmodem_INCLUDE_rdisc6
  bool "Include rdisc6 for IPv6 Router Discovery"

  config PACKAGE_luci-app-qmodem_INCLUDE_no_ndisc_rdisc6
  bool "Do not include any IPv6 Neighbor/Router Discovery tool"
endchoice

choice
  prompt "Qualcomm QMI WWAN Driver Selection"
  default PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan

  config PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan
  bool "Vendor QMI driver"

  config PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan
  bool "Generic QMI driver"
endchoice

choice 
	prompt "MHI PCIe Modem Driver Selection"
	depends on PACKAGE_luci-app-qmodem_INCLUDE_ADD_PCI_SUPPORT
	
	config PACKAGE_luci-app-qmodem_VENDOR_MHI_PCIe_DRIVER
	bool "Use Vendor MHI PCIe Driver"

	config  PACKAGE_luci-app-qmodem_GENERIC_MHI_PCIe_DRIVER
	bool "Use Generic MHI PCIe Driver"
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
