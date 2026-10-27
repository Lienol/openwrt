# Copyright (C) 2024 Tom <fjrcn@outlook.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=luci-app-qmodem-ttlfw4
LUCI_TITLE:=LuCI App for QModem TTL Configuration (JS LuCI / fw4 Only)
LUCI_DEPENDS:=+luci-base
PKG_CONFLICTS:=luci-app-qmodem-ttl
LUCI_PKGARCH:=all
PKG_VERSION:=$(QMODEM_VERSION)
PKG_RELEASE:=1
PKG_LICENSE:=GPLv3
PKG_MAINTAINER:=Tom <fjrcn@outlook.com>

define Package/luci-app-qmodem-ttlfw4/conffiles
/etc/config/qmodem_ttl
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
