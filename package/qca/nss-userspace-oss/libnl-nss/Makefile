include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=libnl-nss
PKG_RELEASE:=1
PKG_BUILD_DEPENDS:=libnl

include $(INCLUDE_DIR)/package.mk

define Package/libnl-nss
  SECTION:=Libs
  CATEGORY:=Libraries
  TITLE:=Framework to communicate between userspace applications and the kernel.
  DEPENDS:=+libpthread +libnl +@NSS_DRV_CRYPTO_ENABLE +kmod-qca-nss-drv-netlink
endef

define Package/libnl-nss/description
 A framework in the userspace that establishes communication between userspace applications and the kernel.
endef

TOOL_CFLAGS:= -I$(STAGING_DIR)/usr/include/qca-nss-clients \
		  	  -I$(STAGING_DIR)/usr/include/qca-nss-drv \
		  	  -I$(STAGING_DIR)/usr/include/libnl3

TOOL_LDFLAGS:= -L$(STAGING_DIR)/lib

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		AR="$(TARGET_AR) " \
		CFLAGS="$(TOOL_CFLAGS)" \
		LD_LIBRARY_PATH="$(TOOL_LDFLAGS)"
endef

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR)/usr/include/libnl-nss
	$(CP) $(PKG_BUILD_DIR)/obj/libnl-nss.so $(STAGING_DIR)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/include/* $(STAGING_DIR)/usr/include/libnl-nss
endef

define Package/libnl-nss/install
	$(INSTALL_DIR) $(1)/lib
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/obj/libnl-nss.so $(1)/lib
endef

# $(eval $(call BuildPackage,libnl-nss))
