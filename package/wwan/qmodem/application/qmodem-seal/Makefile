include $(TOPDIR)/rules.mk

include ../../version.mk

PKG_NAME:=qmodem-seal
PKG_VERSION:=$(QMODEM_VERSION)
PKG_RELEASE:=$(QMODEM_RELEASE)

include $(INCLUDE_DIR)/package.mk

define Package/qmodem-seal
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=QModem encrypted feedback tool
  DEPENDS:=+libsodium
endef

define Package/qmodem-seal/description
  Encrypts QModem feedback for a maintainer recipient and derives a
  reproducible recipient identity from a user-supplied recovery token.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
		-Wall -Wextra -Werror -o $(PKG_BUILD_DIR)/qmodem-seal \
		$(PKG_BUILD_DIR)/qmodem-seal.c $(TARGET_LDFLAGS) -lsodium
endef

define Package/qmodem-seal/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/qmodem-seal $(1)/usr/bin/
endef

$(eval $(call BuildPackage,qmodem-seal))
