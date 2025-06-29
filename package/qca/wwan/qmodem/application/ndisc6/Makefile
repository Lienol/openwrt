#
# Copyright (C) 2006-2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ndisc6
PKG_VERSION:=1.0.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=http://www.remlab.net/files/ndisc6
PKG_MD5SUM:=50cb4c19606cf6ff2b7388e71832f579

PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/ndisc
  SECTION:=ipv6
  CATEGORY:=IPv6
  SUBMENU:=IPv6 discovery tools
  TITLE:=IPv6 discovery tools
  URL:=http://www.remlab.net/ndisc6/
  DEPENDS:=+libpthread +librt
endef

define Package/ndisc/description
IPv6 discovery tools
endef

define Package/ndisc6
  $(call Package/ndisc)
  TITLE:=An ICMPv6 neighbour discovery tool
endef

define Package/ndisc6/description
An ICMPv6 neighbour discovery tools
endef

define Package/rdisc6
  $(call Package/ndisc)
  TITLE:=An ICMPv6 router discovery tool
endef

define Package/rdisc6/description
An ICMPv6 router discovery tool
endef

define Package/traceroute6
  $(call Package/ndisc)
  TITLE:=An IPv6-based traceroute implementation
endef

define Package/traceroute6/description
An IPv6-based traceroute implementation
endef

define Package/rdnssd
  $(call Package/ndisc)
  TITLE:=DNS server discovery daemon
endef

define Package/rdnssd/description
A recursive DNS server discovery daemon gathering
information through stateless IPv6 autoconfiguration (RFC5006)
endef

TARGET_CFLAGS += -std=c99

define Package/ndisc6/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/ndisc6 $(1)/usr/bin/
endef

define Package/rdisc6/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/rdisc6 $(1)/usr/bin/
endef

define Package/traceroute6/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/{rl,tcp}traceroute6 $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/tracert6 $(1)/usr/bin/
endef

define Package/rdnssd/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/rdnssd $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,ndisc6))
$(eval $(call BuildPackage,rdisc6))
$(eval $(call BuildPackage,traceroute6))
$(eval $(call BuildPackage,rdnssd))