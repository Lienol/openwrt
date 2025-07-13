include $(TOPDIR)/rules.mk

PKG_NAME:=qca-nss-cfi
PKG_RELEASE:=3

PKG_SOURCE_URL:=https://git.codelinaro.org/clo/qsdk/oss/lklm/nss-cfi.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2025-04-04
PKG_SOURCE_VERSION:=ff11dae
PKG_MIRROR_HASH:=64459080b7f6dcb0a70530a239dbee1a11377f3bb0373505d9b2b2f99ed3d1a4
QSDK_VERSION:=12.5
PKG_VERSION:=$(QSDK_VERSION).$(subst -,.,$(PKG_SOURCE_DATE))~$(PKG_SOURCE_VERSION)

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

ifneq (, $(findstring $(CONFIG_TARGET_SUBTARGET), "ipq807x" "ipq60xx" "ipq50xx"))
# 4.4/5.4 + ipq807x/ipq60xx/ipq50xx
  CFI_OCF_DIR:=ocf/v2.0
  CFI_CRYPTOAPI_DIR:=cryptoapi/v2.0
else
# 4.4 Kernel + ipq806x
  CFI_CRYPTOAPI_DIR:=cryptoapi/v1.1
  CFI_OCF_DIR:=ocf/v1.0
  CFI_IPSEC_DIR:=ipsec/v1.0
endif

define KernelPackage/qca-nss-cfi-cryptoapi
  SECTION:=kernel
  CATEGORY:=Kernel modules
  SUBMENU:=Cryptographic API modules
  DEPENDS:=@TARGET_qualcommax +kmod-qca-nss-crypto +kmod-crypto-authenc @BROKEN
  TITLE:=Kernel driver for NSS cfi
ifneq ($(CONFIG_PACKAGE_kmod-qca-nss-cfi-cryptoapi),)
  FILES:=$(PKG_BUILD_DIR)/$(CFI_CRYPTOAPI_DIR)/qca-nss-cfi-cryptoapi.ko
  AUTOLOAD:=$(call AutoLoad,59,qca-nss-cfi-cryptoapi)
endif
endef

define KernelPackage/qca-nss-cfi-cryptoapi/Description
This package contains a NSS cfi driver for QCA chipset
endef

ifneq ($(CONFIG_PACKAGE_kmod-qca-nss-cfi-cryptoapi),)

ifeq ($(CONFIG_TARGET_BOARD), "qualcommax")
  SOC:=$(CONFIG_TARGET_SUBTARGET)
endif

EXTRA_CFLAGS+= \
  -DCONFIG_NSS_DEBUG_LEVEL=4 \
  -I$(LINUX_DIR)/crypto/ocf \
  -I$(STAGING_DIR)/usr/include/qca-nss-crypto \
  -I$(STAGING_DIR)/usr/include/crypto \
  -I$(STAGING_DIR)/usr/include/qca-nss-drv

ifneq (, $(findstring $(CONFIG_TARGET_SUBTARGET), "ipq807x" "ipq60xx" "ipq50xx"))
EXTRA_CFLAGS+= -I$(STAGING_DIR)/usr/include/qca-nss-clients
endif

MAKE_OPTS+= \
	cryptoapi=y \
	NSS_CRYPTOAPI_ABLK=n \
	NSS_CRYPTOAPI_SKCIPHER=y

MAKE_OPTS+= \
	CFI_CRYPTOAPI_DIR=$(CFI_CRYPTOAPI_DIR) \
	CFI_IPSEC_DIR=$(CFI_IPSEC_DIR) \
	SoC=$(SOC)

define Build/Compile
	+$(KERNEL_MAKE) \
		M="$(PKG_BUILD_DIR)" \
		EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
		$(strip $(MAKE_OPTS)) \
		$(PKG_JOBS) \
		modules
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/qca-nss-cfi
	$(CP) $(PKG_BUILD_DIR)/$(CFI_CRYPTOAPI_DIR)/../exports/* $(1)/usr/include/qca-nss-cfi
	$(CP) $(PKG_BUILD_DIR)/include/* $(1)/usr/include/qca-nss-cfi
endef

else

define Build/Compile
	:
endef

define Build/Install
	:
endef

endif

$(eval $(call KernelPackage,qca-nss-cfi-cryptoapi))
