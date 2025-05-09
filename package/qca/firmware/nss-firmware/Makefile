#
# Copyright (C) 2022 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=nss-firmware
PKG_SOURCE_DATE:=2025-05-01
PKG_SOURCE_VERSION:=e4726900138b3e77fbbeaa32e58aa40a66d6b01a
PKG_MIRROR_HASH:=b0e42d6723fc903146c6745b0e7f2b20d8a6492a0e7c2f6b69c1f0e656d0d865
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/qosmio/qca-sdk-nss-fw.git

PKG_LICENSE_FILES:=LICENSE.md

PKG_MAINTAINER:=Sean K <datapronix@protonmail.com>

PKG_CONFIG_DEPENDS:= \
	CONFIG_NSS_FIRMWARE_VERSION_11_4 \
	CONFIG_NSS_FIRMWARE_VERSION_12_1 \
	CONFIG_NSS_FIRMWARE_VERSION_12_2 \
	CONFIG_NSS_FIRMWARE_VERSION_12_5

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:
STRIP:=:

NSS_PROFILE:=R

define Package/nss-firmware-common
	TITLE:=NSS firmware
	SECTION:=firmware
	CATEGORY:=Firmware
	URL:=$(PKG_SOURCE_URL)
	DEPENDS:=@TARGET_qualcommax
endef

define Package/nss-firmware
$(call Package/nss-firmware-common,$(1))
	DEPENDS+= +TARGET_qualcommax_ipq807x:nss-firmware-ipq807x \
		  +TARGET_qualcommax_ipq60xx:nss-firmware-ipq60xx \
		  +TARGET_qualcommax_ipq50xx:nss-firmware-ipq50xx
endef

define Package/nss-firmware-ipq807x
$(call Package/nss-firmware-common,$(1))
	IPQ_PLATFORM=IPQ8074
	NSS_SOC:=HK
endef

define Package/nss-firmware-ipq60xx
$(call Package/nss-firmware-common,$(1))
	IPQ_PLATFORM=IPQ6018
	CONFLICTS=nss-firmware-ipq807x
	NSS_SOC:=CP
endef

define Package/nss-firmware-ipq50xx
$(call Package/nss-firmware-common,$(1))
	IPQ_PLATFORM=IPQ5018
	CONFLICTS=nss-firmware-ipq807x nss-firmware-ipq60xx
	NSS_SOC:=MP
endef

define Package/nss-firmware/config
  menu "NSS Firmware Version"

  comment "Select NSS firmware version"

  choice
    prompt "Version"
    default NSS_FIRMWARE_VERSION_11_4

    config NSS_FIRMWARE_VERSION_12_5
          bool "NSS Firmware 12.5 Release 210"
          help
               This version does NOT work with NSS MESH (802.11s)

    config NSS_FIRMWARE_VERSION_12_2
          bool "NSS Firmware 12.2 Release 161"
          help
               This version does NOT work with NSS MESH (802.11s)

    config NSS_FIRMWARE_VERSION_12_1
          bool "NSS Firmware 12.1 Release 003"
          help
               This version does NOT work with NSS MESH (802.11s)

    config NSS_FIRMWARE_VERSION_11_4
          bool "NSS Firmware 11.4.0.5 Release 6"
          help
               This version WORKS with NSS MESH (802.11s)
  endchoice
  endmenu
endef

define nss-firmware-version
ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_11_4),)
   override NSS_MAJOR=11
   override NSS_MINOR=4
   override NSS_REL=6
   override VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2021.SPF_11.4/CS
else ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_12_1),)
   override NSS_MAJOR=12
   override NSS_MINOR=1
   override NSS_REL=003
   override VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2022.SPF_12.1/ED1
else ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_12_2),)
   override NSS_MAJOR=12
   override NSS_MINOR=2
   ifeq ($(1),IPQ5018)
      override NSS_REL=156
   else
      override NSS_REL=161
   endif
   override VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2022.SPF_12.2/ED1
else
   override NSS_MAJOR=12
   override NSS_MINOR=5
   override NSS_REL=210
   override VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2024.SPF_12.5/ED1
endif
endef

define Build/Compile
endef

define Package/nss-firmware-common/install
	$(eval $(call nss-firmware-version,$(IPQ_PLATFORM)))
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/$(IPQ_PLATFORM)
	$(TAR) --strip-components=1 -C $(PKG_BUILD_DIR)/$(IPQ_PLATFORM) -xf \
		$(VERSION_PATH)/$(IPQ_PLATFORM).ATH.$(NSS_MAJOR).$(NSS_MINOR)/BIN-NSS*.$(NSS_MAJOR).$(NSS_MINOR)*-$(NSS_REL)*$(NSS_PROFILE).tar.bz2
	$(INSTALL_DIR) $(1)/lib/firmware/
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/$(IPQ_PLATFORM)/retail_router0.bin \
		$(1)/lib/firmware/qca-nss0-retail.bin
ifeq ($(NSS_SOC),HK)
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/$(IPQ_PLATFORM)/retail_router1.bin \
		$(1)/lib/firmware/qca-nss1-retail.bin
endif
endef

define Package/nss-firmware-ipq807x/install
	$(call Package/nss-firmware-common/install,$(1))
endef

define Package/nss-firmware-ipq60xx/install
	$(call Package/nss-firmware-common/install,$(1))
endef

define Package/nss-firmware-ipq50xx/install
	$(call Package/nss-firmware-common/install,$(1))
endef

define Package/nss-firmware/install
	true
endef

$(eval $(call BuildPackage,nss-firmware-ipq807x))
$(eval $(call BuildPackage,nss-firmware-ipq60xx))
$(eval $(call BuildPackage,nss-firmware-ipq50xx))
$(eval $(call BuildPackage,nss-firmware))
