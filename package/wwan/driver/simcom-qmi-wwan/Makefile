include $(TOPDIR)/rules.mk

PKG_NAME:=simcom-qmi-wwan
PKG_VERSION:=1.0
PKG_RELEASE:=2

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/usb-net-qmi-wwan-simcom
  SUBMENU:=USB Support
  TITLE:=QMI WWAN driver for Simcom modules
  DEPENDS:=+kmod-usb-net +kmod-usb-wdm
  FILES:=$(PKG_BUILD_DIR)/qmi_wwan_s.ko
  AUTOLOAD:=$(call AutoLoad,82,qmi_wwan_s)
endef

define KernelPackage/usb-net-qmi-wwan-simcom/description
  Simcom Linux USB QMI WWAN Driver
endef

MAKE_OPTS:= \
	ARCH="$(LINUX_KARCH)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	CXXFLAGS="$(TARGET_CXXFLAGS)" \
	M="$(PKG_BUILD_DIR)" \
	$(EXTRA_KCONFIG)

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C "$(LINUX_DIR)" \
		$(MAKE_OPTS) \
		modules
endef

$(eval $(call KernelPackage,usb-net-qmi-wwan-simcom))
