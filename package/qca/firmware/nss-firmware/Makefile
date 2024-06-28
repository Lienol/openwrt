#
# Copyright (C) 2022 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=nss-firmware
PKG_SOURCE_DATE:=2022-07-12
PKG_SOURCE_VERSION:=ade6bff5
PKG_MIRROR_HASH:=6652eea8941a0db28f983fa450b28ffaae332e4494c21cb9dbfe4648568db28d
PKG_RELEASE:=3

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/quic/qca-sdk-nss-fw.git

PKG_LICENSE_FILES:=LICENSE.md

PKG_MAINTAINER:=Sean K <datapronix@protonmail.com>

PKG_CONFIG_DEPENDS:= \
	CONFIG_NSS_FIRMWARE_VERSION_11_4 \
	CONFIG_NSS_FIRMWARE_VERSION_12_1

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:
STRIP:=:

NSS_PROFILE:=R

define Package/nss-firmware-default
	TITLE:=NSS firmware
	SECTION:=firmware
	CATEGORY:=Firmware
	URL:=$(PKG_SOURCE_URL)
	DEPENDS:=@TARGET_qualcommax
endef

define Package/nss-firmware-ipq8074
$(Package/nss-firmware-default)
	IPQ_PLATFORM=IPQ8074
	DEPENDS+= @TARGET_qualcommax_ipq807x +nss-firmware-default
	NSS_SOC:=HK
endef

define Package/nss-firmware-ipq6018
$(Package/nss-firmware-default)
	IPQ_PLATFORM=IPQ6018
	DEPENDS+= @TARGET_qualcommax_ipq60xx +nss-firmware-default
	NSS_SOC:=CP
endef

define Package/nss-firmware-ipq5018
$(Package/nss-firmware-default)
	IPQ_PLATFORM=IPQ5018
	DEPENDS+= @TARGET_qualcommax_ipq50xx +nss-firmware-default
	NSS_SOC:=MP
endef


define Package/nss-firmware-default/config
  menu "NSS Firmware Version"

  comment "Select NSS firmware version"

  choice
    prompt "Version"
    default NSS_FIRMWARE_VERSION_12_1

    config NSS_FIRMWARE_VERSION_12_1
          bool "NSS Firmware 12.1 Release 022"
          help
               This version does not work with NSS MESH

    config NSS_FIRMWARE_VERSION_11_4
          bool "NSS Firmware 11.4.0.5 Release 5"
          help
               This version works with NSS MESH
  endchoice
  endmenu
endef

ifneq ($(CONFIG_NSS_FIRMWARE_VERSION_11_4),)
   NSS_MAJOR:=11.4
   NSS_MINOR:=11.4.0.5
   NSS_REL:=5
   VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2021.SPF_$(NSS_MAJOR)/CS
else
   NSS_MAJOR:=12.0.0
   NSS_MINOR:=12.1
   NSS_REL:=022
   VERSION_PATH=$(PKG_BUILD_DIR)/QCA_Networking_2022.SPF_$(NSS_MAJOR)/ED1
endif

define Build/Compile
endef

define Package/nss-firmware/install
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/$(IPQ_PLATFORM)
	$(TAR) --strip-components=1 -C $(PKG_BUILD_DIR)/$(IPQ_PLATFORM) -xf \
		$(VERSION_PATH)/$(IPQ_PLATFORM).ATH.$(NSS_MAJOR)/BIN-NSS*.$(NSS_MINOR)-$(NSS_REL)*$(NSS_PROFILE).tar.bz2
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

define Package/nss-firmware-ipq8074/install
	$(call Package/nss-firmware/install,$(1))
endef

define Package/nss-firmware-ipq6018/install
	$(call Package/nss-firmware/install,$(1))
endef

define Package/nss-firmware-ipq5018/install
	$(call Package/nss-firmware/install,$(1))
endef

define Package/nss-firmware-default/install
	true
endef

$(eval $(call BuildPackage,nss-firmware-ipq8074))
$(eval $(call BuildPackage,nss-firmware-ipq6018))
$(eval $(call BuildPackage,nss-firmware-ipq5018))
$(eval $(call BuildPackage,nss-firmware-default))
