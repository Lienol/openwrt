# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2018 Chion Tang <tech@chionlab.moe>
# Copyright (c) 2019-2022 GitHub/llccd Twitter/@gNodeB
# Copyright (c) 2022 Syrone Wong <wong.syrone@gmail.com>

include $(TOPDIR)/rules.mk

PKG_NAME:=fullconenat-nft
PKG_RELEASE:=$(AUTORELEASE)

PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2023-05-17
PKG_SOURCE_URL:=https://github.com/fullcone-nat-nftables/nft-fullcone.git
PKG_SOURCE_VERSION:=07d93b626ce5ea885cd16f9ab07fac3213c355d9
PKG_MIRROR_HASH:=6ea91089b9350df186961ac7a90200cc42083a2d29bb78f433a7279a25b76c2a

PKG_MAINTAINER:=Syrone Wong <wong.syrone@gmail.com>

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/nft-fullcone
  SUBMENU:=Netfilter Extensions
  DEPENDS:=+kmod-nft-nat
  TITLE:=Netfilter nf_tables fullcone support
  FILES:= $(PKG_BUILD_DIR)/src/nft_fullcone.ko
  KCONFIG:= \
    CONFIG_NF_CONNTRACK_EVENTS=y \
    CONFIG_NF_CONNTRACK_CHAIN_EVENTS=y
  AUTOLOAD:=$(call AutoProbe,nft_fullcone)
endef

define KernelPackage/nft-fullcone/Description
  nftables fullcone expression kernel module
endef

define Build/Compile
	+$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)/src" modules
endef

$(eval $(call KernelPackage,nft-fullcone))
