#
# Copyright (C) 2016 LEDE
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=sched-cake-oot
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/dtaht/sch_cake.git
PKG_SOURCE_DATE:=2021-06-10
PKG_SOURCE_VERSION:=d9e1398cc9091e9e7c7a740361e4617b75c24427
PKG_MIRROR_HASH:=ce34fe5ebe9413b22c61db01b6d34fbfb363e8aeba638cdf93b00fd37daffaab
PKG_MAINTAINER:=Kevin Darbyshire-Bryant <ldir@darbyshire-bryant.me.uk>

include $(INCLUDE_DIR)/package.mk

define KernelPackage/sched-cake-oot
  SUBMENU:=Network Support
  TITLE:=OOT Cake fq_codel/blue derived shaper
  URL:=https://github.com/dtaht/sch_cake
  FILES:=$(PKG_BUILD_DIR)/sch_cake.ko
  AUTOLOAD:=$(call AutoLoad,75,sch_cake)
  DEPENDS:=@(LINUX_4_9||LINUX_4_14) +kmod-sched-core +kmod-ipt-conntrack
endef

define KernelPackage/sched-cake-oot/description
  O(ut) O(f) T(ree) Common Applications Kept Enhanced fq_codel/blue derived shaper
endef

define KernelPackage/sched-cake-virtual
  SUBMENU:=Network Support
  TITLE:=Virtual package for sched-cake
  URL:=https://github.com/dtaht/sch_cake
  DEPENDS:=+!(LINUX_4_9||LINUX_4_14):kmod-sched-cake +(LINUX_4_9||LINUX_4_14):kmod-sched-cake-oot
endef

define KernelPackage/sched-cake-virtual/description
  Virtual package for resolving sch_cake dependencies
endef

include $(INCLUDE_DIR)/kernel-defaults.mk

define Build/Compile
	$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,sched-cake-oot))
$(eval $(call KernelPackage,sched-cake-virtual))
