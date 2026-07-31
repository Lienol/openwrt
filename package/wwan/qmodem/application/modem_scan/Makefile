include $(TOPDIR)/rules.mk

# Include unified version
include ../../version.mk

PKG_NAME:=modem_scan
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=QModem scan daemon and client
  DEPENDS:=+libjson-c +tom_modem +sms-tool_q +ubus-at-daemon
endef

define Package/$(PKG_NAME)/description
  C daemon and client for QModem device scan event scheduling.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(TARGET_CFLAGS) -Wall -Wextra -std=c99 -D_GNU_SOURCE -I$(STAGING_DIR)/usr/include -I$(STAGING_DIR)/usr/include/json-c" \
		LDFLAGS="$(TARGET_LDFLAGS) -ljson-c -lpthread"
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/modem_scand $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/modem_scanc $(1)/usr/bin/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
