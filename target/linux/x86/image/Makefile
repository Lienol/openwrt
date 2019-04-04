# 
# Copyright (C) 2006-2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

export PATH=$(TARGET_PATH):/sbin

GRUB2_MODULES = biosdisk boot chain configfile ext2 linux ls part_msdos reboot serial test vga
GRUB2_MODULES_ISO = biosdisk boot chain configfile iso9660 linux ls part_msdos reboot serial test vga
GRUB2_MODULES_EFI = boot chain configfile ext2 fat linux ls part_msdos part_gpt reboot serial test efi_gop efi_uga
GRUB_TERMINALS =
GRUB_SERIAL_CONFIG =
GRUB_TERMINAL_CONFIG =
GRUB_CONSOLE_CMDLINE =

USE_ATKBD = generic 64

ifneq ($(strip $(foreach subtarget,$(USE_ATKBD),$(CONFIG_TARGET_x86_$(subtarget)))),)
  GRUB2_MODULES += at_keyboard
  GRUB2_MODULES_ISO += at_keyboard
endif

ifneq ($(CONFIG_GRUB_CONSOLE),)
  GRUB_CONSOLE_CMDLINE += console=tty0
  GRUB_TERMINALS += console
endif

GRUB_SERIAL:=$(call qstrip,$(CONFIG_GRUB_SERIAL))

ifneq ($(GRUB_SERIAL),)
  GRUB_CONSOLE_CMDLINE += console=$(GRUB_SERIAL),$(CONFIG_GRUB_BAUDRATE)n8$(if $(CONFIG_GRUB_FLOWCONTROL),r,)
  GRUB_SERIAL_CONFIG := serial --unit=0 --speed=$(CONFIG_GRUB_BAUDRATE) --word=8 --parity=no --stop=1 --rtscts=$(if $(CONFIG_GRUB_FLOWCONTROL),on,off)
  GRUB_TERMINALS += serial
endif

ifneq ($(GRUB_TERMINALS),)
  GRUB_TERMINAL_CONFIG := terminal_input $(GRUB_TERMINALS); terminal_output $(GRUB_TERMINALS)
endif

SIGNATURE:=$(shell perl -e 'printf("%08x", rand(0xFFFFFFFF))')
ROOTPART:=$(call qstrip,$(CONFIG_TARGET_ROOTFS_PARTNAME))
ROOTPART:=$(if $(ROOTPART),$(ROOTPART),PARTUUID=$(SIGNATURE)-02)
EFI_SIGNATURE:=$(strip $(shell uuidgen | sed -r 's/[a-zA-Z0-9]{2}$$/00/'))
EFI_ROOTPART:=$(call qstrip,$(CONFIG_TARGET_ROOTFS_PARTNAME))
EFI_ROOTPART:=$(if $(EFI_ROOTPART),$(EFI_ROOTPART),PARTUUID=$(shell echo $(EFI_SIGNATURE) | sed 's/00$$/02/'))

GRUB_TIMEOUT:=$(call qstrip,$(CONFIG_GRUB_TIMEOUT))
GRUB_TITLE:=$(call qstrip,$(CONFIG_GRUB_TITLE))

ifneq ($(CONFIG_GRUB_IMAGES),)

  BOOTOPTS:=$(call qstrip,$(CONFIG_GRUB_BOOTOPTS))

  define Image/cmdline/ext4
    root=$(ROOTPART) rootfstype=ext4 rootwait
  endef

  define Image/cmdline/squashfs
    root=$(ROOTPART) rootfstype=squashfs rootwait
  endef

  define Image/Build/grub2
	# left here because the image builder doesnt need these
	$(INSTALL_DIR) $(KDIR)/root.grub/boot/grub $(KDIR)/grub2
	$(CP) $(KDIR)/bzImage $(KDIR)/root.grub/boot/vmlinuz
	grub-mkimage \
		-p /boot/grub \
		-d $(STAGING_DIR_HOST)/lib/grub/i386-pc \
		-o $(KDIR)/grub2/core.img \
		-O i386-pc \
		-c ./grub-early.cfg \
		$(GRUB2_MODULES)
	$(CP) $(STAGING_DIR_HOST)/lib/grub/i386-pc/*.img $(KDIR)/grub2/
	echo '(hd0) $(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).img' > $(KDIR)/grub2/device.map
	sed \
		-e 's#@SERIAL_CONFIG@#$(strip $(GRUB_SERIAL_CONFIG))#g' \
		-e 's#@TERMINAL_CONFIG@#$(strip $(GRUB_TERMINAL_CONFIG))#g' \
		-e 's#@CMDLINE@#$(strip $(call Image/cmdline/$(1)) $(BOOTOPTS) $(GRUB_CONSOLE_CMDLINE))#g' \
		-e 's#@TIMEOUT@#$(GRUB_TIMEOUT)#g' \
		-e 's#@TITLE@#$(GRUB_TITLE)#g' \
		./grub.cfg > $(KDIR)/root.grub/boot/grub/grub.cfg
	-$(CP) $(STAGING_DIR_ROOT)/boot/. $(KDIR)/root.grub/boot/
	PADDING="$(CONFIG_TARGET_IMAGES_PAD)" SIGNATURE="$(SIGNATURE)" PATH="$(TARGET_PATH)" $(SCRIPT_DIR)/gen_image_generic.sh \
		$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).img \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $(KDIR)/root.grub \
		$(CONFIG_TARGET_ROOTFS_PARTSIZE) $(KDIR)/root.$(1) \
		256
	grub-bios-setup \
		--device-map="$(KDIR)/grub2/device.map" \
		-d "$(KDIR)/grub2" \
		-r "hd0,msdos1" \
		"$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).img"
  endef
endif

define Image/Build/squashfs
	dd if=/dev/zero bs=128k count=1 >> $(KDIR)/root.squashfs
endef
ifneq ($(CONFIG_EFI_IMAGES),)

  BOOTOPTS:=$(call qstrip,$(CONFIG_GRUB_BOOTOPTS))

  define Image/cmdline/ext4/efi
    root=$(EFI_ROOTPART) rootfstype=ext4 rootwait
  endef

  define Image/cmdline/squashfs/efi
    root=$(EFI_ROOTPART) rootfstype=squashfs rootwait
  endef

  define Image/Build/grub2/efi
	# left here because the image builder doesnt need these
	$(INSTALL_DIR) $(KDIR)/root.grub/boot/grub $(KDIR)/grub2 $(KDIR)/root.grub/efi/boot
	$(CP) $(KDIR)/bzImage $(KDIR)/root.grub/boot/vmlinuz
	sed -e 's#msdos1#gpt1#g' ./grub-early.cfg > $(KDIR)/grub2/grub-early.cfg

	grub-mkimage \
		-p /boot/grub \
		-d $(STAGING_DIR_HOST)/lib/grub/$(CONFIG_ARCH)-efi \
		-o $(KDIR)/root.grub/efi/boot/boot$(if $(CONFIG_x86_64),x64,ia32).efi \
		-O $(CONFIG_ARCH)-efi \
		-c $(KDIR)/grub2/grub-early.cfg \
		$(GRUB2_MODULES_EFI)

	grub-mkimage \
		-p /boot/grub \
		-d $(STAGING_DIR_HOST)/lib/grub/i386-pc \
		-o $(KDIR)/grub2/core.img \
		-O i386-pc \
		-c $(KDIR)/grub2/grub-early.cfg \
		$(GRUB2_MODULES) part_gpt fat

	$(CP) $(STAGING_DIR_HOST)/lib/grub/i386-pc/*.img $(KDIR)/grub2/
	echo '(hd0) $(BIN_DIR)/$(IMG_PREFIX)-combined-$(1)-efi.img' > $(KDIR)/grub2/device.map
	sed \
		-e 's#@SERIAL_CONFIG@#$(strip $(GRUB_SERIAL_CONFIG))#g' \
		-e 's#@TERMINAL_CONFIG@#$(strip $(GRUB_TERMINAL_CONFIG))#g' \
		-e 's#@CMDLINE@#$(strip $(call Image/cmdline/$(1)/efi) $(BOOTOPTS) $(GRUB_CONSOLE_CMDLINE))#g' \
		-e 's#@TIMEOUT@#$(GRUB_TIMEOUT)#g' \
		-e 's#@TITLE@#$(GRUB_TITLE)#g' \
		-e 's#msdos1#gpt1#g' \
		./grub.cfg > $(KDIR)/root.grub/boot/grub/grub.cfg
	-$(CP) $(STAGING_DIR_ROOT)/boot/. $(KDIR)/root.grub/boot/
	EFI_SIGNATURE=$(EFI_SIGNATURE) PADDING="1" SIGNATURE="$(SIGNATURE)" PATH="$(TARGET_PATH)" $(SCRIPT_DIR)/gen_image_generic.sh \
		$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1)-efi.img \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $(KDIR)/root.grub \
		$(CONFIG_TARGET_ROOTFS_PARTSIZE) $(KDIR)/root.$(1) \
		256
	grub-bios-setup \
		--device-map="$(KDIR)/grub2/device.map" \
		-d "$(KDIR)/grub2" \
		-r "hd0,gpt1" \
		"$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1)-efi.img"
  endef
endif

define Image/Build/iso
	$(INSTALL_DIR) $(KDIR)/root.grub/boot/grub $(KDIR)/grub2
	$(INSTALL_DIR) $(KDIR)/root.grub/efi/boot
	$(CP) $(KDIR)/bzImage $(KDIR)/root.grub/boot/vmlinuz
	grub-mkimage \
		-p /boot/grub \
		-d $(STAGING_DIR_HOST)/lib/grub/i386-pc \
		-o $(KDIR)/grub2/eltorito.img \
		-O i386-pc \
		-c ./grub-early.cfg \
		$(GRUB2_MODULES_ISO)
	cat \
		$(STAGING_DIR_HOST)/lib/grub/i386-pc/cdboot.img \
		$(KDIR)/grub2/eltorito.img \
		> $(KDIR)/root.grub/boot/grub/eltorito.img
	grub-mkimage \
		-p /boot/grub \
		-d $(STAGING_DIR_HOST)/lib/grub/$(CONFIG_ARCH)-efi \
		-o $(KDIR)/root.grub/efi/boot/boot$(if $(CONFIG_x86_64),x64,ia32).efi \
		-O $(CONFIG_ARCH)-efi \
		-c ./grub-early.cfg \
		$(GRUB2_MODULES_EFI) iso9660

	rm -f $(KDIR)/root.grub/efiboot.img
	mkfs.fat -C $(TARGET_DIR)/efiboot.img -S 512 1440
	mcopy -s -i $(TARGET_DIR)/efiboot.img $(KDIR)/root.grub/efi ::/
	sed \
		-e 's#@SERIAL_CONFIG@#$(strip $(GRUB_SERIAL_CONFIG))#g' \
		-e 's#@TERMINAL_CONFIG@#$(strip $(GRUB_TERMINAL_CONFIG))#g' \
		-e 's#@CMDLINE@#root=/dev/sr0 rootfstype=iso9660 rootwait $(strip $(call Image/cmdline/$(1)) $(BOOTOPTS) $(GRUB_CONSOLE_CMDLINE))#g' \
		-e 's#@TIMEOUT@#$(GRUB_TIMEOUT)#g' \
		-e 's#@TITLE@#$(GRUB_TITLE)#g' \
		./grub-iso.cfg > $(KDIR)/root.grub/boot/grub/grub.cfg
	-$(CP) $(STAGING_DIR_ROOT)/boot/. $(KDIR)/root.grub/boot/
	mkisofs -R -b boot/grub/eltorito.img -no-emul-boot -boot-info-table \
		-boot-load-size 4 -c boot.cat -eltorito-alt-boot -e efiboot.img -no-emul-boot \
		-o $(KDIR)/root.iso $(KDIR)/root.grub $(TARGET_DIR)
endef

ifneq ($(CONFIG_VDI_IMAGES),)
  define Image/Build/vdi/default
	rm $(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).vdi || true
	qemu-img convert -f raw -O vdi \
		$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).img \
		$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).vdi
  endef
endif

ifneq ($(CONFIG_VMDK_IMAGES),)
  define Image/Build/vmdk/default
	rm $(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).vmdk || true
	qemu-img convert -f raw -O vmdk \
		$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).img \
		$(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).vmdk
  endef
endif

ifneq ($(CONFIG_GRUB_IMAGES),)
  define Image/Build/vdi
	$(call Image/Build/vdi/default,$(1))
  endef
  define Image/Build/vmdk
	$(call Image/Build/vmdk/default,$(1))
  endef
endif

ifneq ($(CONFIG_EFI_IMAGES),)
  define Image/Build/vdi/efi
	$(call Image/Build/vdi/default,$(1)-efi)
  endef
  define Image/Build/vmdk/efi
	$(call Image/Build/vmdk/default,$(1)-efi)
  endef
endif

define Image/Build/gzip
	$(if $(CONFIG_GRUB_IMAGES),gzip -f9n $(BIN_DIR)/$(IMG_PREFIX)-combined-$(1).img)
	$(if $(CONFIG_EFI_IMAGES),gzip -f9n $(BIN_DIR)/$(IMG_PREFIX)-combined-$(1)-efi.img)
	gzip -f9n $(BIN_DIR)/$(IMG_PREFIX)-rootfs-$(1).img
endef

ifneq ($(CONFIG_TARGET_IMAGES_GZIP),)
  define Image/Build/gzip/ext4
	$(call Image/Build/gzip,ext4)
  endef
  define Image/Build/gzip/squashfs
	$(call Image/Build/gzip,squashfs)
  endef
endif

define Image/BuildKernel
	$(CP) $(KDIR)/bzImage $(BIN_DIR)/$(IMG_PREFIX)-vmlinuz
endef

define Image/Prepare
	$(call Image/Prepare/grub2)
endef

define Image/Build/Initramfs
	$(CP) $(KDIR)/bzImage-initramfs $(BIN_DIR)/$(IMG_PREFIX)-ramfs.bzImage
endef

define Image/Build
	$(call Image/Build/$(1))
  ifneq ($(1),iso)
	$(call Image/Build/grub2,$(1))
	$(call Image/Build/vdi,$(1))
	$(call Image/Build/vmdk,$(1))
	$(call Image/Build/grub2/efi,$(1))
	$(call Image/Build/vdi/efi,$(1))
	$(call Image/Build/vmdk/efi,$(1))
	$(CP) $(KDIR)/root.$(1) $(BIN_DIR)/$(IMG_PREFIX)-rootfs-$(1).img
  else
	$(CP) $(KDIR)/root.iso $(BIN_DIR)/$(IMG_PREFIX).iso
  endif
	$(CP) $(KDIR)/bzImage $(BIN_DIR)/$(IMG_PREFIX)-vmlinuz
	$(call Image/Build/gzip/$(1))
ifeq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),y)
	$(call Image/Build/Initramfs)
endif
endef

$(eval $(call BuildImage))
