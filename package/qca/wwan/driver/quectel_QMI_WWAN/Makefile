#
# Copyright (C) 2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=qmi_wwan_q
PKG_VERSION:=3.0
PKG_RELEASE:=4

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto

define KernelPackage/qmi_wwan_q
  SUBMENU:=WWAN Support
  TITLE:=Quectel Linux USB QMI WWAN Driver
  DEPENDS:=+kmod-usb-net +kmod-usb-wdm +kmod-qca-nss-drv +@NSS_DRV_RMNET_ENABLE
  FILES:=$(PKG_BUILD_DIR)/qmi_wwan_q.ko \
  			 $(PKG_BUILD_DIR)/rmnet_nss.ko
  AUTOLOAD:=$(call AutoLoad,42,rmnet_nss) \
  					$(call AutoLoad,81,qmi_wwan_q)
endef

define KernelPackage/qmi_wwan_q/description
  Quectel Linux USB QMI WWAN Driver
endef

EXTRA_CFLAGS+= \
	-I$(STAGING_DIR)/usr/include/qca-nss-drv

MAKE_OPTS:= \
	ARCH="$(LINUX_KARCH)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
	CXXFLAGS="$(TARGET_CXXFLAGS)" \
	M="$(PKG_BUILD_DIR)" \
	$(EXTRA_KCONFIG)

define Build/Compile
	+$(MAKE) -C "$(LINUX_DIR)" $(strip $(MAKE_OPTS)) \
		$(KERNEL_MAKE_FLAGS) \
		$(PKG_JOBS) \
		modules
endef

$(eval $(call KernelPackage,qmi_wwan_q))
