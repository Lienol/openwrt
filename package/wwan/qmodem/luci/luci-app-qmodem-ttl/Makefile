# Copyright (C) 2023 Siriling <siriling@qq.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=luci-app-qmodem-ttl
LUCI_TITLE:=Luci qwrt modem ttl support
LUCI_PKGARCH:=all
PKG_VERSION:=$(QMODEM_VERSION)
PKG_LICENSE:=GPLv3
PKG_LINCESE_FILES:=LICENSE
PKG_MAINTAINER:=Tom <fjrcn@outlook.com>
LUCI_DEPENDS:=+luci-app-qmodem
PKG_CONFLICTS:=luci-app-qmodem-ttlfw4
		

define Package/luci-app-qmodem-ttl/conffiles
/etc/config/qmodem_ttl
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
