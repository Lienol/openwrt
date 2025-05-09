#
# Copyright (C) 2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=pcie_mhi
PKG_VERSION:=1.3.6
PKG_RELEASE:=2

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto

define KernelPackage/pcie_mhi
  SUBMENU:=WWAN Support
  TITLE:=Kernel pcie driver for MHI device
  DEPENDS:=@(TARGET_qualcommax_ipq807x||TARGET_qualcommax_ipq50xx) \
	    +pciids +pciutils +quectel-cm +kmod-qmi_wwan_q
  FILES:=$(PKG_BUILD_DIR)/pcie_mhi.ko
  AUTOLOAD:=$(call AutoLoad,90,pcie_mhi)
endef

define KernelPackage/pcie_mhi/description
  Kernel module for register a custom pciemhi platform device.
endef

EXTRA_CFLAGS+= \
	-I$(STAGING_DIR)/usr/include/qca-nss-drv \
	-Wno-unused-function \
	-Wno-missing-prototypes \
	-Wno-missing-declarations

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

$(eval $(call KernelPackage,pcie_mhi))
