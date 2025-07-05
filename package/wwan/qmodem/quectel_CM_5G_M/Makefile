include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:= quectel-CM-5G-M
PKG_RELEASE:=6
PKG_VERSION:=1.6

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=quectel-CM-5G app building test with metric option ( -M )
endef

define Package/$(PKG_NAME)/description
	quectel-CM-5G app building test
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(TARGET_CONFIGURE_OPTS) CFLAGS="$(TARGET_CFLAGS)"
endef

define Package/$(PKG_NAME)/install
		$(INSTALL_DIR) $(1)/usr/bin $(1)/lib/netifd/proto $(1)/lib/netifd
		$(INSTALL_BIN) $(PKG_BUILD_DIR)/quectel-CM $(1)/usr/bin/quectel-CM-M
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
