include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=sms-tool_q
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

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
