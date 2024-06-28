include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=nssinfo
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/nssinfo
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Userspace utility for fetching stats from NSS
  DEPENDS:=+libncurses +libnl-nss
endef

define Package/nssinfo/description
 A userspace utility for fetching stats from NSS.
endef

TOOL_CFLAGS:= -I$(STAGING_DIR)/usr/include/qca-nss-clients \
	      -I$(STAGING_DIR)/usr/include/qca-nss-drv \
	      -I$(STAGING_DIR)/usr/include/libnl3 \
	      -I$(STAGING_DIR)/usr/include/libnl-nss

TOOL_LDFLAGS:= -L$(STAGING_DIR)/lib

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TOOL_CFLAGS)" \
		LD_LIBRARY_PATH="$(TOOL_LDFLAGS)"
endef

define Package/nssinfo/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/obj/nssinfo $(1)/usr/sbin/
endef

# $(eval $(call BuildPackage,nssinfo))
