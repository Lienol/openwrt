include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=sms-forwarder-next
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=SMS Forward Service
  DEPENDS:=+tom_modem +jq +curl +ucode +ucode-mod-ubus +ucode-mod-uci
endef

define Package/$(PKG_NAME)/description
  SMS forward service for QModem that supports multiple forwarding methods:
  - Telegram Bot
  - ServerChan
  - Generic Webhook
  - Custom Script
endef


define Build/Compile
endef


define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/sms_forwarder_next $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/sms_forwarder
	$(INSTALL_BIN) ./files/scripts/sms_forward_*.sh $(1)/usr/share/sms_forwarder/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/sms_forwarder.init $(1)/etc/init.d/sms_forwarder
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/sms_forwarder.example $(1)/etc/config/sms_forwarder
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/sms_forwarder
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
