include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-mhi-pcie
PKG_VERSION:=1.3.8
PKG_RELEASE:=2

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/pcie_mhi
  SUBMENU:=WWAN Support
  TITLE:=Kernel pcie driver for MHI device
  FILES:=$(PKG_BUILD_DIR)/pcie_mhi.ko
# AUTOLOAD:=$(call AutoLoad,90,pcie_mhi)
endef

define KernelPackage/pcie_mhi/description
  Kernel module for register a custom pciemhi platform device.
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

define KernelPackage/pcie_mhi/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/pcie_mhi $(1)/etc/init.d/pcie_mhi
endef

$(eval $(call KernelPackage,pcie_mhi))
