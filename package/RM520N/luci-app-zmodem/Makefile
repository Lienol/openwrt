# Copyright (C) Zy143L

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zmodem
PKG_VERSION:=1.8
PKG_RELEASE:=1

LUCI_TITLE:=LuCI for zmodem
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+kmod-usb-net +kmod-usb-core +kmod-usb-ohci +kmod-usb-serial +kmod-usb-serial-option +kmod-usb-uhci +kmod-usb2 +usb-modeswitch +usbutils +sendat +coreutils-timeout



include $(TOPDIR)/feeds/luci/luci.mk

# $(eval $(call BuildPackage,luci-app-zmodem))
