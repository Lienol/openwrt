#
# Copyright (C) 2022 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=nss-firmware
PKG_SOURCE_DATE:=2024-08-04
PKG_SOURCE_VERSION:=794fe3732fca4ef9b74e7be6f621d160d831b636
PKG_MIRROR_HASH:=a3bb68bd729469470cbccd538d7fc529acabad46a2c9aa2ad6bb19fb05f01b45
PKG_RELEASE:=2

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
          depends on !TARGET_qualcommax_ipq50xx
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

ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_11_4),)
   NSS_MAJOR=11
   NSS_MINOR=4
   NSS_REL=6
   VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2021.SPF_$(NSS_MAJOR).$(NSS_MINOR)/CS
else ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_12_1),)
   NSS_MAJOR=12
   NSS_MINOR=1
   NSS_REL=003
   VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2022.SPF_$(NSS_MAJOR).$(NSS_MINOR)/ED1
else ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_12_2),)
   NSS_MAJOR=12
   NSS_MINOR=2
   NSS_REL=161
   VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2022.SPF_$(NSS_MAJOR).$(NSS_MINOR)/ED1
else
   NSS_MAJOR=12
   NSS_MINOR=5
   NSS_REL=210
   VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2024.SPF_$(NSS_MAJOR).$(NSS_MINOR)/ED1
endif

define Build/Compile
endef

define Package/nss-firmware-common/install
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
