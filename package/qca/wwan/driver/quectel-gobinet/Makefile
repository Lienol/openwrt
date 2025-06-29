include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-gobinet
PKG_VERSION:=1.6.3
PKG_RELEASE:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/usb-net-gobinet
  SUBMENU:=USB Support
  TITLE:=Gobinet driver for Quectel modules
  DEPENDS:=+kmod-usb-net
  FILES:=$(PKG_BUILD_DIR)/GobiNet.ko
  AUTOLOAD:=$(call AutoLoad,81,GobiNet)
endef

define Build/Compile
	+$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,usb-net-gobinet))
