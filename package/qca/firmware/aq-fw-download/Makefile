include $(TOPDIR)/rules.mk

PKG_NAME:=aq-fw-download
PKG_RELEASE:=$(AUTORELEASE)

PKG_FLAGS:=nonshared

include $(INCLUDE_DIR)/package.mk

define Package/aq-fw-download
	SECTION:=firmware
	CATEGORY:=Firmware
	DEPENDS:=@TARGET_qualcommax
	TITLE:=Aquantia FW downloader utitlity
endef

define Package/aq-fw-download/description
	Aquantia FW downloader utitlity
endef

define Package/aq-fw-download/install
	$(INSTALL_DIR) $(1)/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aq-fw-download $(1)/sbin/aq-fw-download
endef

$(eval $(call BuildPackage,aq-fw-download))
