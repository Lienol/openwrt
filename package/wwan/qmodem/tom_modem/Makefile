include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:= tom_modem
PKG_RELEASE:=1
PKG_VERSION:=1.0.3

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Fujr Modem Communite Tool
endef

define Package/$(PKG_NAME)/config
	config PACKAGE_$(PKG_NAME)_EARLY_RETURN
		bool "Early return"
		default y
endef

define Package/$(PKG_NAME)/description
  Modem Communite Tool for 5G modem (By Fujr)
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
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tom_modem $(1)/usr/bin/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
