#
# Copyright (C) 2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=PCI Modem Server
LUCI_DEPENDS:=+kmod-pcie_mhi +kmod-pcie_mhi_fb +pciutils +quectel-cm

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
