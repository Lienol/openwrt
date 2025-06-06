include $(TOPDIR)/rules.mk

PKG_NAME:=qca-mcs
PKG_RELEASE:=2

PKG_SOURCE_URL:=https://git.codelinaro.org/clo/qsdk/oss/lklm/qca-mcs.git
PKG_SOURCE_DATE:=2024-09-04
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=e1c59f7
PKG_MIRROR_HASH:=2570ab6c101ded40549b32f795516896ae2fc6c7919ecc2fbf0b059b266a246d
QSDK_VERSION:=12.5
PKG_VERSION:=$(QSDK_VERSION).$(subst -,.,$(PKG_SOURCE_DATE))~$(PKG_SOURCE_VERSION)

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/qca-mcs
  SECTION:=kernel
  CATEGORY:=Kernel modules
  SUBMENU:=Network Support
  URL:=http://www.qca.qualcomm.com
  MAINTAINER:=Qualcomm Atheros, Inc.
  TITLE:=QCA Multicast Snooping Support
  DEPENDS:=+@KERNEL_IPV6_MROUTE +@KERNEL_IP_MROUTE
  KCONFIG:=CONFIG_NETFILTER=y
  FILES:=$(PKG_BUILD_DIR)/qca-mcs.ko
  AUTOLOAD:=$(call AutoLoad,41,qca-mcs)
endef

define KernelPackage/qca-mcs/Description
  This package installs the IGMP/MLD Snooping Module
endef

QCA_MC_SNOOPING_HEADERS= \
            $(PKG_BUILD_DIR)/mc_api.h \
            $(PKG_BUILD_DIR)/mc_ecm.h \

define Build/InstallDev
  mkdir -p $(1)/usr/include/qca-mcs
	$(foreach header_file,$(QCA_MC_SNOOPING_HEADERS), $(CP) $(header_file) $(1)/usr/include/qca-mcs;)
	$(foreach header_file,$(QCA_MC_SNOOPING_HEADERS), $(CP) $(header_file) $(1)/usr/include/;)
endef

EXTRA_CFLAGS+=-Wno-implicit-fallthrough

QCA_MC_SNOOPING_MAKE_OPTS:= \
        $(KERNEL_MAKE_FLAGS) \
        CONFIG_SUPPORT_MLD=y \
        MDIR=$(PKG_BUILD_DIR) \
        KBUILDPATH=$(LINUX_DIR) \
        KERNELPATH=$(LINUX_SRC_DIR) \
        KERNELRELEASE=$(LINUX_RELEASE)

define Build/Compile
	+$(MAKE) -C $(LINUX_DIR) \
      $(KERNEL_MAKE_FLAGS) \
      $(PKG_JOBS) \
      KBUILDPATH=$(LINUX_DIR) \
      $(PKG_MAKE_FLAGS) \
      M=$(PKG_BUILD_DIR) \
      EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
      $(strip $(QCA_MC_SNOOPING_MAKE_OPTS)) \
      modules
endef

$(eval $(call KernelPackage,qca-mcs))
