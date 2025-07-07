include $(TOPDIR)/rules.mk

PKG_NAME:=qfirehose
PKG_VERSION:=1.4.21
PKG_RELEASE:=1

PKG_MAINTAINER:=Oskari Rauta <oskari.rauta@gmail.com>
PKG_LICENSE:=
PKG_LICENSE_FILES:=NOTICE

include $(INCLUDE_DIR)/package.mk

define Package/qfirehose
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Quectel Firehose Recovery application
  URL:=https://github.com/nippynetworks/qfirehose
endef

define Package/qfirehose/description
  Utility that is able to flash firmwares on Quectel's modems.
  Usage: qfirehose -f FW_PATH
  
  Warning.

   - Use of software is completely on your own risk.
     Flashing wrong firmware or failed flash can brick your modem permanently.
     Avoid flashing, if device works without issues and updated firmware does not contain new necessary changes.
     Do not flash, if you are not willing to take this risk or do not know what you are doing.

   - After succesful flashing, you should use terminal to issue factory reset for modem settings with AT&F command.

   - mPCIe users (mostly): If modem has completely disappeared after succesful flashing, reason might be that some firmware updates
     set default mode to USB3 which is unsupported by some mPCIe slots, in this case, you should connect it to USB
     port using mPCIe -> USB adapter, even most of cheap chinese modules can reveal device. After this you should issue
     a command to use USB2, which may vary between models, but on most Quectel modems is: AT+QUSBCFG="SS",0
     Changing value on end of AT command 0 to 1, selects USB3 instead. Refer to documents of your modem.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

MAKE_ARGS += linux

define Package/qfirehose/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/out/QFirehose $(1)/usr/bin/qfirehose
endef

$(eval $(call BuildPackage,qfirehose))
