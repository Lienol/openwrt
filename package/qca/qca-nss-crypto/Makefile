include $(TOPDIR)/rules.mk

PKG_NAME:=qca-nss-crypto
PKG_RELEASE:=3

PKG_SOURCE_URL:=https://git.codelinaro.org/clo/qsdk/oss/lklm/nss-crypto.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2022-12-15
PKG_SOURCE_VERSION:=3c5a574
PKG_MIRROR_HASH:=085db1cf51170b0bb64b8bf5c086778aac7fcc2e3379497592c0855db6a25e5f
QSDK_VERSION:=12.5
PKG_VERSION:=$(QSDK_VERSION).$(subst -,.,$(PKG_SOURCE_DATE))~$(PKG_SOURCE_VERSION)

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/qca-nss-crypto
	SECTION:=kernel
	CATEGORY:=Kernel modules
	SUBMENU:=Cryptographic API modules
	DEPENDS:=@(TARGET_qualcommax||TARGET_ipq806x) \
		+kmod-qca-nss-drv \
		+@NSS_DRV_CRYPTO_ENABLE \
		+TARGET_qualcommax_ipq807x:nss-eip-firmware \
		+TARGET_qualcommax_ipq60xx:nss-eip-firmware
	TITLE:=Kernel driver for NSS crypto driver
ifneq ($(CONFIG_PACKAGE_kmod-qca-nss-crypto),)
	FILES:=$(PKG_BUILD_DIR)/$(NSS_CRYPTO_DIR)/src/qca-nss-crypto.ko \
	$(PKG_BUILD_DIR)/$(NSS_CRYPTO_DIR)/tool/qca-nss-crypto-tool.ko
	AUTOLOAD:=$(call AutoProbe,qca-nss-crypto)
endif
endef

define KernelPackage/qca-nss-crypto/Description
This package contains a NSS crypto driver for QCA chipset
endef

ifneq ($(CONFIG_PACKAGE_kmod-qca-nss-crypto),)
# v1.0 is for Akronite
# v2.0 is for Hawkeye/Cypress/Maple
ifneq (, $(findstring $(CONFIG_TARGET_SUBTARGET), "ipq807x" "ipq60xx" "ipq50xx"))
NSS_CRYPTO_DIR:=v2.0
else
NSS_CRYPTO_DIR:=v1.0
endif

EXTRA_CFLAGS+= \
	-DCONFIG_NSS_DEBUG_LEVEL=4 \
	-I$(STAGING_DIR)/usr/include/qca-nss-crypto \
	-I$(STAGING_DIR)/usr/include/qca-nss-drv \
	-I$(PKG_BUILD_DIR)/$(NSS_CRYPTO_DIR)/include \
	-I$(PKG_BUILD_DIR)/$(NSS_CRYPTO_DIR)/src

ifeq ($(CONFIG_TARGET_BOARD), "qualcommax")
	SOC:=$(CONFIG_TARGET_SUBTARGET)
endif

MAKE_OPTS+= \
	NSS_CRYPTO_DIR=$(NSS_CRYPTO_DIR) \
	SoC=$(SOC) \

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/qca-nss-crypto
	$(CP) $(PKG_BUILD_DIR)/$(NSS_CRYPTO_DIR)/include/* $(1)/usr/include/qca-nss-crypto
endef

define Build/Compile
	+$(KERNEL_MAKE) \
		M="$(PKG_BUILD_DIR)" \
		EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
		$(strip $(MAKE_OPTS)) \
		$(PKG_JOBS) \
		modules
endef

else

define Build/Compile
	:
endef

define Build/Install
	:
endef

endif

$(eval $(call KernelPackage,qca-nss-crypto))
