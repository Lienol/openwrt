GRUB_PLATFORM:=efi

PKG_BUILD_DEPENDS:=grub2-efi/host
include ../common.mk

define Package/grub2-efi
  CATEGORY:=Boot Loaders
  SECTION:=boot
  TITLE:=GRand Unified Bootloader(EFI)
  URL:=http://www.gnu.org/software/grub/
  DEPENDS:=@TARGET_x86
endef

define Host/Install
	$(call Host/Compile/Default,install-data)
endef

$(eval $(call HostBuild))
$(eval $(call BuildPackage,grub2-efi))
