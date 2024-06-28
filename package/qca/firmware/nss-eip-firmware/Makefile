include $(TOPDIR)/rules.mk

PKG_NAME:=nss-eip-firmware
PKG_VERSION=2.5.7
PKG_RELEASE:=$(AUTORELEASE)

PKG_MAINTAINER:=Robert Marko <robimarko@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/nss-eip-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=NSS EIP-197 firmware
  DEPENDS:=@(TARGET_qualcommax||TARGET_ipq60xx)
endef

define Build/Compile

endef

define Package/nss-eip-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/ifpp.bin $(1)/lib/firmware/ifpp.bin
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/ipue.bin $(1)/lib/firmware/ipue.bin
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/ofpp.bin $(1)/lib/firmware/ofpp.bin
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/opue.bin $(1)/lib/firmware/opue.bin
endef

$(eval $(call BuildPackage,nss-eip-firmware))
