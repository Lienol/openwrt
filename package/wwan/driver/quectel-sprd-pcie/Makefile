include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-sprd-pcie
PKG_VERSION:=1.6
PKG_RELEASE:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/sprd-pcie
  SUBMENU:=Network Devices
  TITLE:=Kernel PCIe driver for SPRD device
  DEPENDS:=@PCI_SUPPORT @BROKEN
  FILES:=$(PKG_BUILD_DIR)/sprd_pcie.ko
  AUTOLOAD:=$(call AutoLoad,41,sprd_pcie)
endef

define KernelPackage/sprd-pcie/description
  Kernel module for register a custom pcispd platform device.
endef

define Build/Compile
	+$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,sprd-pcie))
