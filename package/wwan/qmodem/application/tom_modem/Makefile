include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

# Include unified version
include ../../version.mk

PKG_NAME:=tom_modem
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Fujr Modem Communite Tool
  DEPENDS:=+libubus +libubox +libjson-c +libblobmsg-json
endef

define Package/$(PKG_NAME)/config
	config PACKAGE_$(PKG_NAME)_EARLY_RETURN
		bool "Early return"
		default y
	config PACKAGE_$(PKG_NAME)_ENABLE_UBUS_DAEMON
		bool "Enable UBUS daemon support"
		default y
		help
		  Enable UBUS daemon support for tom_modem.
		  When disabled, compiles tom_modem_v1 (TTY-only mode).
		  When enabled, allows switching between TTY and UBUS with -u flag.
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
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(TARGET_CFLAGS) $(if $(CONFIG_PACKAGE_$(PKG_NAME)_ENABLE_UBUS_DAEMON),-DENABLE_UBUS_DAEMON)" \
		ENABLE_UBUS_DAEMON=$(if $(CONFIG_PACKAGE_$(PKG_NAME)_ENABLE_UBUS_DAEMON),y,n)
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tom_modem $(1)/usr/bin/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
