include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-qmi-wwan-nss
PKG_VERSION:=1.2.9
PKG_RELEASE:=2

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

PKG_BUILD_PARALLEL:=1

define KernelPackage/usb-net-qmi-wwan-quectel-nss
  SUBMENU:=USB Support
  TITLE:=QMI WWAN driver for Quectel modules
  DEPENDS:=+kmod-usb-net +kmod-usb-wdm
  DEPENDS:=@(TARGET_qualcommax_ipq807x||TARGET_qualcommax_ipq50xx) \
	    +kmod-usb-net \
	    +kmod-usb-wdm \
	    +kmod-rmnet-nss
  FILES:=$(PKG_BUILD_DIR)/qmi_wwan_q.ko
  AUTOLOAD:=$(call AutoLoad,81,qmi_wwan_q)
endef

EXTRA_CFLAGS+= \
	-Wno-unused-function \
	-Wno-missing-prototypes \
	-Wno-missing-declarations

ifneq ($(CONFIG_PACKAGE_kmod-rmnet-nss),)
EXTRA_CFLAGS += -I$(STAGING_DIR)/usr/include/qca-nss-rmnet
EXTRA_CFLAGS += -DCONFIG_QCA_NSS_DRV
endif

define Build/Compile
	+$(KERNEL_MAKE) EXTRA_CFLAGS="$(EXTRA_CFLAGS)" M="$(PKG_BUILD_DIR)" \
		modules
endef

$(eval $(call KernelPackage,usb-net-qmi-wwan-quectel-nss))
