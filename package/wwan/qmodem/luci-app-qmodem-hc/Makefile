# Copyright (C) 2024 Tom <fjrcn@outlook.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-qmodem-hc
LUCI_TITLE:=Luci qwrt modem sim switch
LUCI_PKGARCH:=all
PKG_VERSION:=2.7.0
PKG_LICENSE:=GPLv3
PKG_LINCESE_FILES:=LICENSE
PKG_MAINTAINER:=Tom <fjrcn@outlook.com>
LUCI_DEPENDS:=+luci-app-qmodem
		

define Package/luci-app-qmodem-hc/conffiles
/etc/config/qmodem_hc_sim
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
