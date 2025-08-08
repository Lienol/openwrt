include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

# Include unified version
include ../version.mk

PKG_NAME:=qmodem
PKG_RELEASE:=$(QMODEM_RELEASE)
PKG_VERSION:=$(QMODEM_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  PKGARCH:=all
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=QModem scripts
  DEPENDS:=	\
  		+kmod-usb2 +kmod-usb3 \
		+kmod-usb-serial +kmod-usb-serial-option +kmod-usb-serial-qualcomm \
		+kmod-usb-net +kmod-usb-acm \
		+kmod-usb-wdm \
		+kmod-usb-net-cdc-ether \
		+kmod-usb-net-cdc-mbim \
		+kmod-usb-net-rndis \
		+kmod-usb-net-cdc-ncm +kmod-usb-net-huawei-cdc-ncm \
  		+tom_modem +terminfo +sms-tool_q \
		+jq +bc\
		+coreutils +coreutils-stat \
		+usbutils \
		+ndisc6 \
		+PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan:kmod-usb-net-qmi-wwan \
		+PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan:kmod-usb-net-qmi-wwan-quectel \
		+PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan:kmod-usb-net-qmi-wwan-fibocom \
		+PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan:kmod-usb-net-qmi-wwan-simcom \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_PCI_SUPPORT:kmod-pcie_mhi \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_PCI_SUPPORT:pciutils \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_MTK_T7XX_SUPPORT:umbim \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_MTK_T7XX_SUPPORT:kmod-mtk-t7xx \
		+PACKAGE_luci-app-qmodem_INCLUDE_ADD_QFIREHOSE_SUPPORT:qfirehose \
		+PACKAGE_luci-app-qmodem_USE_TOM_CUSTOMIZED_QUECTEL_CM:quectel-CM-5G-M \
		+PACKAGE_luci-app-qmodem_USING_NORMAL_QUECTEL_CM:quectel-cm
endef

define Package/$(PKG_NAME)/description
	QModem scripts
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
		$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
