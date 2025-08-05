include $(TOPDIR)/rules.mk

PKG_NAME:=sms-tool_q
PKG_RELEASE:=1
PKG_SOURCE_URL:=https://github.com/obsy/sms_tool
PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2025-4-15
PKG_SOURCE_VERSION:=ee229370eed5f2907cdfba95f17bc913a238b17e

include $(INCLUDE_DIR)/package.mk

define Package/sms-tool_q
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=sms tool
  URL:=https://github.com/obsy/sms_tool
endef

define Package/sms-tool_q/description
	SMS Tool for 3G/4G/5G modem
endef

define Package/sms-tool_q/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sms_tool $(1)/usr/bin/sms_tool_q
endef

$(eval $(call BuildPackage,sms-tool_q))
