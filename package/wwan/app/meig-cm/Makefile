include $(TOPDIR)/rules.mk

PKG_NAME:= meig-cm
PKG_VERSION:=1.2.1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/meig-cm
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=meig-cm app
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C "$(PKG_BUILD_DIR)" \
		EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		ARCH="$(LINUX_KARCH)" \
		M="$(PKG_BUILD_DIR)" \
		CC="$(TARGET_CC)"
endef

define Package/meig-cm/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/meig-cm $(1)/usr/bin
endef

$(eval $(call BuildPackage,meig-cm))
