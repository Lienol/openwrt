include $(TOPDIR)/rules.mk

PKG_NAME:=fibocom-qmi-wwan
PKG_VERSION:=1.0.5
PKG_RELEASE:=4

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/usb-net-qmi-wwan-fibocom
  SUBMENU:=USB Support
  TITLE:=QMI WWAN driver for Fibocom modules
  DEPENDS:=+kmod-usb-net +kmod-usb-wdm
  FILES:=$(PKG_BUILD_DIR)/qmi_wwan_f.ko
  AUTOLOAD:=$(call AutoLoad,82,qmi_wwan_f)
endef

define Build/Compile
	+$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,usb-net-qmi-wwan-fibocom))
