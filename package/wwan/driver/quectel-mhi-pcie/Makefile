include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-mhi-pcie
PKG_VERSION:=1.3.8
PKG_RELEASE:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/mhi-pcie
  SUBMENU:=Network Devices
  TITLE:=Kernel PCIe driver for MHI device
  DEPENDS:=@PCI_SUPPORT
  FILES:=$(PKG_BUILD_DIR)/pcie_mhi.ko
  AUTOLOAD:=$(call AutoLoad,90,pcie_mhi)
endef

define KernelPackage/mhi-pcie/description
  Kernel module for register a custom pciemhi platform device.
endef

define Build/Compile
	+$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,mhi-pcie))
