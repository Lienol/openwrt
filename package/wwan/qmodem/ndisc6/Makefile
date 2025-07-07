#
# Copyright (C) 2007-2021 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ndisc6
PKG_VERSION:=1.0.8
PKG_RELEASE:=1

PKG_SOURCE:=ndisc6-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6/
PKG_HASH:=1f2fb2dc1172770aa5a09d39738a44d8b753cc5e2e25e306ca78682f9fea0b4f

PKG_INSTALL:=1
PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk

define Package/ndisc6
  URL:=https://www.remlab.net/ndisc6/
  SECTION:=network
  CATEGORY:=Network
  TITLE:=NDisc6
endef

define Package/ndisc6/description
  NDisc6 is a small collection of useful tools for IPv6 networking
endef

define Package/ndisc6/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/ndisc6 $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/rdisc6 $(1)/usr/bin
endef

$(eval $(call BuildPackage,ndisc6))