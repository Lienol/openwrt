# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#
# Copyright (C) 2019, KFERMercer <iMercer@yeah.net>
# 

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for tcpdump
LUCI_DEPENDS:=+tcpdump
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-tcpdump
PKG_VERSION:=1.0
PKG_RELEASE:=2
PKG_MAINTAINER:=<https://github.com/KFERMercer/luci-app-tcpdump>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
