# Copyright (C) 2020 Lienol
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=AdGuardHome
PKG_VERSION:=0.103.2
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/AdguardTeam/AdGuardHome/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=62e096749fcaac0d48f83a9b8dbce03ed163be55cf77e2f21ad1ba0026ad61c8

PKG_CONFIG_DEPENDS := \
	CONFIG_AdGuardHome_COMPRESS_GOPROXY \
	CONFIG_AdGuardHome_COMPRESS_UPX

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

GO_PKG:=github.com/AdguardTeam/AdGuardHome
GO_PKG_LDFLAGS:=-s -w
GO_PKG_LDFLAGS_X:= \
	main.version=$(PKG_VERSION) \
	main.channel=release

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Network-wide ads & trackers blocking DNS server
	URL:=https://github.com/AdguardTeam/AdGuardHome
endef

define Package/$(PKG_NAME)/description
Network-wide ads & trackers blocking DNS server
endef

define Package/$(PKG_NAME)/config

menu "Configuration"
	depends on PACKAGE_$(PKG_NAME)

config AdGuardHome_COMPRESS_GOPROXY
	bool "Compiling with GOPROXY proxy"
	default n

config AdGuardHome_COMPRESS_UPX
	bool "Compress executable files with UPX"
	default y

endmenu

endef

ifeq ($(CONFIG_AdGuardHome_COMPRESS_GOPROXY),y)
export GO111MODULE=on
export GOPROXY=https://goproxy.cn
endif

define Build/Prepare
	tar -zxvf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components 1
endef

define Build/Compile
	$(eval GO_PKG_BUILD_PKG:=$(GO_PKG))
	$(call GoPackage/Build/Configure)
	$(call GoPackage/Build/Compile)
ifeq ($(CONFIG_AdGuardHome_COMPRESS_UPX),y)
	$(STAGING_DIR_HOST)/bin/upx --lzma --best $(GO_PKG_BUILD_BIN_DIR)/$(PKG_NAME)
endif
endef

define Package/$(PKG_NAME)/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin/$(PKG_NAME)
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(PKG_NAME) $(1)/usr/bin/$(PKG_NAME)/$(PKG_NAME)
endef

$(eval $(call GoBinPackage,$(PKG_NAME)))
$(eval $(call BuildPackage,$(PKG_NAME)))
