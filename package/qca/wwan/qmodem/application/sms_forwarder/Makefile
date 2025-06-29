include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=sms-forwarder
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=SMS Forward Service
  DEPENDS:=+tom_modem +jq +curl +libjson-c
endef

define Package/$(PKG_NAME)/description
  SMS forward service for QModem that supports multiple forwarding methods:
  - Telegram Bot
  - ServerChan
  - Generic Webhook
  - Custom Script
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
		LDFLAGS="$(TARGET_LDFLAGS) -ljson-c"
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sms_forwarder $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/bin/sms_forward_*.sh $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/sms_forwarder $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/sms_daemon $(1)/etc/config/
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/sms_daemon
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
