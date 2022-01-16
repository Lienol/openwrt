REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN='fw_printenv fw_setenv fwtool'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

platform_do_upgrade() {
	local board=$(board_name)
	local file_type=$(identify $1)

	case "$board" in
	bananapi,bpi-r64)
		export_bootdevice
		export_partdevice rootdev 0
		case "$rootdev" in
		mmc*)
			CI_ROOTDEV="$rootdev"
			CI_KERNPART="production"
			emmc_do_upgrade "$1"
			;;
		*)
			CI_KERNPART="fit"
			nand_do_upgrade "$1"
			;;
		esac
		;;
	buffalo,wsr-2533dhp2)
		local magic="$(get_magic_long "$1")"

		# use "mtd write" if the magic is "DHP2 (0x44485032)"
		# or "DHP3 (0x44485033)"
		if [ "$magic" = "44485032" -o "$magic" = "44485033" ]; then
			buffalo_upgrade_ubinized "$1"
		else
			CI_KERNPART="firmware"
			nand_do_upgrade "$1"
		fi
		;;
	linksys,e8450-ubi)
		CI_KERNPART="fit"
		nand_do_upgrade "$1"
		;;
	linksys,e8450)
		if grep -q mtdparts=slave /proc/cmdline; then
			PART_NAME=firmware2
		else
			PART_NAME=firmware1
		fi
		default_do_upgrade "$1"
		;;
	mediatek,mt7622-rfb1-ubi|\
	totolink,a8000ru)
		nand_do_upgrade "$1"
		;;
	*)
		default_do_upgrade "$1"
		;;
	esac
}

PART_NAME=firmware

platform_check_image() {
	local board=$(board_name)
	local magic="$(get_magic_long "$1")"

	[ "$#" -gt 1 ] && return 1

	case "$board" in
	buffalo,wsr-2533dhp2)
		buffalo_check_image "$board" "$magic" "$1" || return 1
		;;
	mediatek,mt7622-rfb1-ubi|\
	totolink,a8000ru)
		nand_do_platform_check "$board" "$1"
		;;
	*)
		[ "$magic" != "d00dfeed" ] && {
			echo "Invalid image type."
			return 1
		}
		return 0
		;;
	esac

	return 0
}

platform_copy_config() {
	case "$(board_name)" in
	bananapi,bpi-r64)
		export_bootdevice
		export_partdevice rootdev 0
		if echo $rootdev | grep -q mmc; then
			emmc_copy_config
		fi
		;;
	esac
}
