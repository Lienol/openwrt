# Copyright (C) 2023 Siriling <siriling@qq.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-sms-tool
LUCI_TITLE:=LuCI Support for sms_tool
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.0
PKG_LICENSE:=GPLv3
PKG_LINCESE_FILES:=LICENSE
PKF_MAINTAINER:=siriling <siriling@qq.com>
LUCI_DEPENDS:=+sms-tool +luci-compat +kmod-usb-serial +kmod-usb-serial-option

define Package/luci-app-sms-tool/postinst
#!/bin/sh
rm -rf /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/
/sbin/set_sms_ports.sh
exit 0
endef

define Package/$(PKG_NAME)/config
# shown in make menuconfig <Help>
help
	$(LUCI_TITLE)
	Version: $(PKG_VERSION)
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
