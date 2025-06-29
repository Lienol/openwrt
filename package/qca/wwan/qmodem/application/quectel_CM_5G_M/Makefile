include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

# Include unified version
include ../../version.mk

PKG_NAME:= quectel-CM-5G-M
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=quectel-CM-5G app building test with metric option ( -M )
  DEPENDS:=+libjson-c
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
		$(INSTALL_DIR) $(1)/usr/share/qmodem
		$(INSTALL_DATA) ./files/apns.json $(1)/usr/share/qmodem/apns.json
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
