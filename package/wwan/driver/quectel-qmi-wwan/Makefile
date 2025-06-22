include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-qmi-wwan
PKG_VERSION:=1.2.9
PKG_RELEASE:=2

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/usb-net-qmi-wwan-quectel
  SUBMENU:=USB Support
  TITLE:=QMI WWAN driver for Quectel modules
  DEPENDS:=+kmod-usb-net +kmod-usb-wdm
  FILES:=$(PKG_BUILD_DIR)/qmi_wwan_q.ko
  AUTOLOAD:=$(call AutoLoad,81,qmi_wwan_q)
endef

define Build/Compile
	+$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,usb-net-qmi-wwan-quectel))
