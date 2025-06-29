
include $(TOPDIR)/rules.mk
 
PKG_NAME:=sendat
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ouyangzq/sendat.git
PKG_SOURCE_DATE:=2023-10-26
PKG_SOURCE_VERSION:=c830885db5bb8ae2dcb10b1bfeab481f14935dd1
PKG_MIRROR_HASH:=ec7a8e42a27c75122b19fdb3ca994223ba46d6089bb3a70f916b56322d922c1f

include $(INCLUDE_DIR)/package.mk
 
define Package/sendat
  SECTION:=utils
  CATEGORY:=Utilities
  SUBMENU :=CPE
  TITLE:=Sendat AT
  DEPENDS:=+libpthread
endef
 
define Package/sendat/description
  AT Commnad for sendat test
endef

MAKE_PATH:=src

define Package/sendat/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/sendat $(1)/usr/bin/
endef

$(eval $(call BuildPackage,sendat))
