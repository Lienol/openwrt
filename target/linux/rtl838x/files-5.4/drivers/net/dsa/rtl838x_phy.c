// SPDX-License-Identifier: GPL-2.0-only
/* Realtek RTL838X Ethernet MDIO interface driver
 *
 * Copyright (C) 2020 B. Koblitz
 */

#include <linux/delay.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/of_mdio.h>
#include <linux/phy.h>
#include <linux/platform_device.h>
#include <linux/firmware.h>
#include <linux/crc32.h>

#include <asm/mach-rtl838x/mach-rtl838x.h>
#include "rtl838x.h"

/* External RTL8218B and RTL8214FC IDs are identical */
#define PHY_ID_RTL8214C		0x001cc942
#define PHY_ID_RTL8214FC	0x001cc981
#define PHY_ID_RTL8218B_E	0x001cc981
#define PHY_ID_RTL8218B_I	0x001cca40
#define PHY_ID_RTL8390_GENERIC	0x001ccab0
#define PHY_ID_RTL8393_I	0x001c8393

struct __attribute__ ((__packed__)) part {
	uint16_t start;
	uint8_t wordsize;
	uint8_t words;
};

struct __attribute__ ((__packed__)) fw_header {
	uint32_t magic;
	uint32_t phy;
	uint32_t checksum;
	uint32_t version;
	struct part parts[10];
};

#define FIRMWARE_838X_8380_1	"rtl838x_phy/rtl838x_8380.fw"
#define FIRMWARE_838X_8214FC_1	"rtl838x_phy/rtl838x_8214fc.fw"
#define FIRMWARE_838X_8218b_1	"rtl838x_phy/rtl838x_8218b.fw"

static const struct firmware rtl838x_8380_fw;
static const struct firmware rtl838x_8214fc_fw;
static const struct firmware rtl838x_8218b_fw;

struct rtl838x_phy_priv {
	char *name;
};

static int read_phy(u32 port, u32 page, u32 reg, u32 *val)
{
	if (soc_info.family == RTL8390_FAMILY_ID)
		return rtl839x_read_phy(port, page, reg, val);
	else
		return rtl838x_read_phy(port, page, reg, val);
}

static int write_phy(u32 port, u32 page, u32 reg, u32 val)
{
	if (soc_info.family == RTL8390_FAMILY_ID)
		return rtl839x_write_phy(port, page, reg, val);
	else
		return rtl838x_write_phy(port, page, reg, val);
}

static void rtl8380_int_phy_on_off(int mac, bool on)
{
	u32 val;

	read_phy(mac, 0, 0, &val);
	if (on)
		write_phy(mac, 0, 0, val & ~(1 << 11));
	else
		write_phy(mac, 0, 0, val | (1 << 11));
}

static void rtl8380_rtl8214fc_on_off(int mac, bool on)
{
	u32 val;

	/* fiber ports */
	write_phy(mac, 4095, 30, 3);
	read_phy(mac, 0, 16, &val);
	if (on)
		write_phy(mac, 0, 16, val & ~(1 << 11));
	else
		write_phy(mac, 0, 16, val | (1 << 11));

	/* copper ports */
	write_phy(mac, 4095, 30, 1);
	read_phy(mac, 0, 16, &val);
	if (on)
		write_phy(mac, 0xa40, 16, val & ~(1 << 11));
	else
		write_phy(mac, 0xa40, 16, val | (1 << 11));
}

static void rtl8380_phy_reset(int mac)
{
	u32 val;

	read_phy(mac, 0, 0, &val);
	write_phy(mac, 0, 0, val | (0x1 << 15));
}

void rtl8380_sds_rst(int mac)
{
	u32 offset = (mac == 24) ? 0 : 0x100;

	sw_w32_mask(1 << 11, 0, RTL8380_SDS4_FIB_REG0 + offset);
	sw_w32_mask(0x3, 0, RTL838X_SDS4_REG28 + offset);
	sw_w32_mask(0x3, 0x3, RTL838X_SDS4_REG28 + offset);
	sw_w32_mask(0, 0x1 << 6, RTL838X_SDS4_DUMMY0 + offset);
	sw_w32_mask(0x1 << 6, 0, RTL838X_SDS4_DUMMY0 + offset);
	pr_info("SERDES reset: %d\n", mac);
}

int rtl839x_read_sds_phy(int phy_addr, int phy_reg)
{
	int offset = 0;
	int reg;
	u32 val;

	if (phy_addr == 49)
		offset = 0x100;

	/* For the RTL8393 internal SerDes, we simulate a PHY ID in registers 2/3
	 * which would otherwise read as 0
	 */
	if (soc_info.id == 0x8393) {
		if (phy_reg == 2)
			return 0x1c;
		if (phy_reg == 3)
			return 0x8393;
	}

	reg = (phy_reg << 1) & 0xfc;
	val = sw_r32(RTL839X_SDS12_13_XSG0 + offset + 0x80 + reg);

	if (phy_reg & 1)
		val = (val >> 16) & 0xffff;
	else
		val &= 0xffff;
	return val;
}

int rtl838x_read_sds_phy(int phy_addr, int phy_reg)
{
	int offset = 0;
	u32 val;

	if (phy_addr == 26)
		offset = 0x100;
	val = sw_r32(MAPLE_SDS4_FIB_REG0r + offset + (phy_reg << 2)) & 0xffff;

	return val;
}

int rtl839x_write_sds_phy(int phy_addr, int phy_reg, u16 v)
{
	int offset = 0;
	int reg;
	u32 val;

	if (phy_addr == 49)
		offset = 0x100;

	reg = (phy_reg << 1) & 0xfc;
	val = v;
	if (phy_reg & 1) {
		val = val << 16;
		sw_w32_mask(0xffff0000, val,
			    RTL839X_SDS12_13_XSG0 + offset + 0x80 + reg);
	} else {
		sw_w32_mask(0xffff, val,
			    RTL839X_SDS12_13_XSG0 + offset + 0x80 + reg);
	}

	return 0;
}

/* Read the link and speed status of the 2 internal SGMII/1000Base-X
 * ports of the RTL838x SoCs
 */
static int rtl8380_read_status(struct phy_device *phydev)
{
	int err;
	int phy_addr = phydev->mdio.addr;

	err = genphy_read_status(phydev);

	if (phydev->link) {
		phydev->speed = SPEED_1000;
		phydev->duplex = DUPLEX_FULL;
	}

	return err;
}

/* Read the link and speed status of the 2 internal SGMII/1000Base-X
 * ports of the RTL8393 SoC
 */
static int rtl8393_read_status(struct phy_device *phydev)
{
	int offset = 0;
	int err;
	int phy_addr = phydev->mdio.addr;
	u32 v;

	err = genphy_read_status(phydev);
	if (phy_addr == 49)
		offset = 0x100;

	if (phydev->link) {
		phydev->speed = SPEED_100;
		/* Read SPD_RD_00 (bit 13) and SPD_RD_01 (bit 6) out of the internal
		 * PHY registers
		 */
		v = sw_r32(RTL839X_SDS12_13_XSG0 + offset + 0x80);
		if (!(v & (1 << 13)) && (v & (1 << 6)))
			phydev->speed = SPEED_1000;
		phydev->duplex = DUPLEX_FULL;
	}

	return err;
}

static struct fw_header *
rtl838x_request_fw(struct phy_device *phydev, const struct firmware *fw,
		   const char *name)
{
	struct device *dev = &phydev->mdio.dev;
	int err;
	struct fw_header *h;
	uint32_t checksum, my_checksum;

	err = request_firmware(&fw, name, dev);
	if (err < 0)
		goto out;

	if (fw->size < sizeof(struct fw_header)) {
		pr_err("Firmware size too small.\n");
		err = -EINVAL;
		goto out;
	}

	h = (struct fw_header *) fw->data;
	pr_info("Firmware loaded. Size %d, magic: %08x\n", fw->size, h->magic);

	if (h->magic != 0x83808380) {
		pr_err("Wrong firmware file: MAGIC mismatch.\n");
		goto out;
	}

	checksum = h->checksum;
	h->checksum = 0;
	my_checksum = ~crc32(0xFFFFFFFFU, fw->data, fw->size);
	if (checksum != my_checksum) {
		pr_err("Firmware checksum mismatch.\n");
		err = -EINVAL;
		goto out;
	}
	h->checksum = checksum;

	return h;
out:
	dev_err(dev, "Unable to load firmware %s (%d)\n", name, err);
	return NULL;
}

static int rtl8390_configure_generic(struct phy_device *phydev)
{
	u32 val, phy_id;
	int mac = phydev->mdio.addr;

	read_phy(mac, 0, 2, &val);
	phy_id = val << 16;
	read_phy(mac, 0, 3, &val);
	phy_id |= val;
	pr_debug("Phy on MAC %d: %x\n", mac, phy_id);

	/* Read internal PHY ID */
	write_phy(mac, 31, 27, 0x0002);
	read_phy(mac, 31, 28, &val);

	/* Internal RTL8218B, version 2 */
	phydev_info(phydev, "Detected unknown %x\n", val);
	return 0;
}

static int rtl8380_configure_int_rtl8218b(struct phy_device *phydev)
{
	u32 val, phy_id;
	int i, p, ipd_flag;
	int mac = phydev->mdio.addr;
	struct fw_header *h;
	u32 *rtl838x_6275B_intPhy_perport;
	u32 *rtl8218b_6276B_hwEsd_perport;


	read_phy(mac, 0, 2, &val);
	phy_id = val << 16;
	read_phy(mac, 0, 3, &val);
	phy_id |= val;
	pr_debug("Phy on MAC %d: %x\n", mac, phy_id);

	/* Read internal PHY ID */
	write_phy(mac, 31, 27, 0x0002);
	read_phy(mac, 31, 28, &val);
	if (val != 0x6275) {
		phydev_err(phydev, "Expected internal RTL8218B, found PHY-ID %x\n", val);
		return -1;
	}

	/* Internal RTL8218B, version 2 */
	phydev_info(phydev, "Detected internal RTL8218B\n");

	h = rtl838x_request_fw(phydev, &rtl838x_8380_fw, FIRMWARE_838X_8380_1);
	if (!h)
		return -1;

	if (h->phy != 0x83800000) {
		phydev_err(phydev, "Wrong firmware file: PHY mismatch.\n");
		return -1;
	}

	rtl838x_6275B_intPhy_perport = (void *)h + sizeof(struct fw_header)
			+ h->parts[8].start;

	rtl8218b_6276B_hwEsd_perport = (void *)h + sizeof(struct fw_header)
			+ h->parts[9].start;

	if (sw_r32(RTL838X_DMY_REG31) == 0x1)
		ipd_flag = 1;

	read_phy(mac, 0, 0, &val);
	if (val & (1 << 11))
		rtl8380_int_phy_on_off(mac, true);
	else
		rtl8380_phy_reset(mac);
	msleep(100);

	/* Ready PHY for patch */
	for (p = 0; p < 8; p++) {
		write_phy(mac + p, 0xfff, 0x1f, 0x0b82);
		write_phy(mac + p, 0xfff, 0x10, 0x0010);
	}
	msleep(500);
	for (p = 0; p < 8; p++) {
		for (i = 0; i < 100 ; i++) {
			read_phy(mac + p, 0x0b80, 0x10, &val);
			if (val & 0x40)
				break;
		}
		if (i >= 100) {
			phydev_err(phydev,
				   "ERROR: Port %d not ready for patch.\n",
				   mac + p);
			return -1;
		}
	}
	for (p = 0; p < 8; p++) {
		i = 0;
		while (rtl838x_6275B_intPhy_perport[i * 2]) {
			write_phy(mac + p, 0xfff,
				rtl838x_6275B_intPhy_perport[i * 2],
				rtl838x_6275B_intPhy_perport[i * 2 + 1]);
			i++;
		}
		i = 0;
		while (rtl8218b_6276B_hwEsd_perport[i * 2]) {
			write_phy(mac + p, 0xfff,
				rtl8218b_6276B_hwEsd_perport[i * 2],
				rtl8218b_6276B_hwEsd_perport[i * 2 + 1]);
			i++;
		}
	}
	return 0;
}

static int rtl8380_configure_ext_rtl8218b(struct phy_device *phydev)
{
	u32 val, ipd, phy_id;
	int i, l;
	int mac = phydev->mdio.addr;
	struct fw_header *h;
	u32 *rtl8380_rtl8218b_perchip;
	u32 *rtl8218B_6276B_rtl8380_perport;
	u32 *rtl8380_rtl8218b_perport;

	if (soc_info.family == RTL8380_FAMILY_ID && mac != 0 && mac != 16) {
		phydev_err(phydev, "External RTL8218B must have PHY-IDs 0 or 16!\n");
		return -1;
	}
	read_phy(mac, 0, 2, &val);
	phy_id = val << 16;
	read_phy(mac, 0, 3, &val);
	phy_id |= val;
	pr_info("Phy on MAC %d: %x\n", mac, phy_id);

	/* Read internal PHY ID */
	write_phy(mac, 31, 27, 0x0002);
	read_phy(mac, 31, 28, &val);
	if (val != 0x6276) {
		phydev_err(phydev, "Expected external RTL8218B, found PHY-ID %x\n", val);
		return -1;
	}
	phydev_info(phydev, "Detected external RTL8218B\n");

	h = rtl838x_request_fw(phydev, &rtl838x_8218b_fw, FIRMWARE_838X_8218b_1);
	if (!h)
		return -1;

	if (h->phy != 0x8218b000) {
		phydev_err(phydev, "Wrong firmware file: PHY mismatch.\n");
		return -1;
	}

	rtl8380_rtl8218b_perchip = (void *)h + sizeof(struct fw_header)
			+ h->parts[0].start;

	rtl8218B_6276B_rtl8380_perport = (void *)h + sizeof(struct fw_header)
			+ h->parts[1].start;

	rtl8380_rtl8218b_perport = (void *)h + sizeof(struct fw_header)
			+ h->parts[2].start;

	read_phy(mac, 0, 0, &val);
	if (val & (1 << 11))
		rtl8380_int_phy_on_off(mac, true);
	else
		rtl8380_phy_reset(mac);
	msleep(100);

	/* Get Chip revision */
	write_phy(mac, 0xfff, 0x1f, 0x0);
	write_phy(mac,  0xfff, 0x1b, 0x4);
	read_phy(mac, 0xfff, 0x1c, &val);

	i = 0;
	while (rtl8380_rtl8218b_perchip[i * 3]
		&& rtl8380_rtl8218b_perchip[i * 3 + 1]) {
		write_phy(mac + rtl8380_rtl8218b_perchip[i * 3],
					  0xfff, rtl8380_rtl8218b_perchip[i * 3 + 1],
					  rtl8380_rtl8218b_perchip[i * 3 + 2]);
		i++;
	}

	/* Enable PHY */
	for (i = 0; i < 8; i++) {
		write_phy(mac + i, 0xfff, 0x1f, 0x0000);
		write_phy(mac + i, 0xfff, 0x00, 0x1140);
	}
	mdelay(100);

	/* Request patch */
	for (i = 0; i < 8; i++) {
		write_phy(mac + i,  0xfff, 0x1f, 0x0b82);
		write_phy(mac + i,  0xfff, 0x10, 0x0010);
	}
	mdelay(300);

	/* Verify patch readiness */
	for (i = 0; i < 8; i++) {
		for (l = 0; l < 100; l++) {
			read_phy(mac + i, 0xb80, 0x10, &val);
			if (val & 0x40)
				break;
		}
		if (l >= 100) {
			phydev_err(phydev, "Could not patch PHY\n");
			return -1;
		}
	}

	/* Use Broadcast ID method for patching */
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0008);
	write_phy(mac, 0xfff, 0x1f, 0x0266);
	write_phy(mac, 0xfff, 0x16, 0xff00 + mac);
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0000);
	mdelay(1);

	write_phy(mac, 0xfff, 30, 8);
	write_phy(mac, 0x26e, 17, 0xb);
	write_phy(mac, 0x26e, 16, 0x2);
	mdelay(1);
	read_phy(mac, 0x26e, 19, &ipd);
	write_phy(mac, 0, 30, 0);
	ipd = (ipd >> 4) & 0xf;

	i = 0;
	while (rtl8218B_6276B_rtl8380_perport[i * 2]) {
		write_phy(mac, 0xfff, rtl8218B_6276B_rtl8380_perport[i * 2],
				  rtl8218B_6276B_rtl8380_perport[i * 2 + 1]);
		i++;
	}

	/*Disable broadcast ID*/
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0008);
	write_phy(mac, 0xfff, 0x1f, 0x0266);
	write_phy(mac, 0xfff, 0x16, 0x00 + mac);
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0000);
	mdelay(1);

	return 0;
}

static int rtl8218b_ext_match_phy_device(struct phy_device *phydev)
{
	int addr = phydev->mdio.addr;

	/* Both the RTL8214FC and the external RTL8218B have the same
	 * PHY ID. On the RTL838x, the RTL8218B can only be attached_dev
	 * at PHY IDs 0-7, while the RTL8214FC must be attached via
	 * the pair of SGMII/1000Base-X with higher PHY-IDs
	 */
	if (soc_info.family == RTL8380_FAMILY_ID)
		return phydev->phy_id == PHY_ID_RTL8218B_E && addr < 8;
	else
		return phydev->phy_id == PHY_ID_RTL8218B_E;
}


static int rtl8380_rtl8218b_write_mmd(struct phy_device *phydev,
				      int devnum, u16 regnum, u16 val)
{
	int addr = phydev->mdio.addr;

	return rtl838x_write_mmd_phy(addr, devnum, regnum, val);
}

static int rtl8380_rtl8218b_read_mmd(struct phy_device *phydev,
				     int devnum, u16 regnum)
{
	int ret;
	u32 val;
	int addr = phydev->mdio.addr;

	ret = rtl838x_read_mmd_phy(addr, devnum, regnum, &val);
	if (ret)
		return ret;
	return val;
}

static void rtl8380_rtl8214fc_media_set(int mac, bool set_fibre)
{
	int base = mac - (mac % 4);
	static int reg[] = {16, 19, 20, 21};
	int val, media, power;

	pr_info("%s: port %d, set_fibre: %d\n", __func__, mac, set_fibre);
	write_phy(base, 0xfff, 29, 8);
	read_phy(base, 0x266, reg[mac % 4], &val);

	media = (val >> 10) & 0x3;
	pr_info("Current media %x\n", media);
	if (media & 0x2) {
		pr_info("Powering off COPPER\n");
		write_phy(base, 0xfff, 29, 1);
		/* Ensure power is off */
		read_phy(base, 0xa40, 16, &power);
		if (!(power & (1 << 11)))
			write_phy(base, 0xa40, 16, power | (1 << 11));
	} else {
		pr_info("Powering off FIBRE");
		write_phy(base, 0xfff, 29, 3);
		/* Ensure power is off */
		read_phy(base, 0xa40, 16, &power);
		if (!(power & (1 << 11)))
			write_phy(base, 0xa40, 16, power | (1 << 11));
	}

	if (set_fibre) {
		val |= 1 << 10;
		val &= ~(1 << 11);
	} else {
		val |= 1 << 10;
		val |= 1 << 11;
	}
	write_phy(base, 0xfff, 29, 8);
	write_phy(base, 0x266, reg[mac % 4], val);
	write_phy(base, 0xfff, 29, 0);

	if (set_fibre) {
		pr_info("Powering on FIBRE");
		write_phy(base, 0xfff, 29, 3);
		/* Ensure power is off */
		read_phy(base, 0xa40, 16, &power);
		if (power & (1 << 11))
			write_phy(base, 0xa40, 16, power & ~(1 << 11));
	} else {
		pr_info("Powering on COPPER\n");
		write_phy(base, 0xfff, 29, 1);
		/* Ensure power is off */
		read_phy(base, 0xa40, 16, &power);
		if (power & (1 << 11))
			write_phy(base, 0xa40, 16, power & ~(1 << 11));
	}

	write_phy(base, 0xfff, 29, 0);
}

static bool rtl8380_rtl8214fc_media_is_fibre(int mac)
{
	int base = mac - (mac % 4);
	static int reg[] = {16, 19, 20, 21};
	u32 val;

	write_phy(base, 0xfff, 29, 8);
	read_phy(base, 0x266, reg[mac % 4], &val);
	write_phy(base, 0xfff, 29, 0);
	if (val & (1 << 11))
		return false;
	return true;
}

static int rtl8380_rtl8214fc_set_port(struct phy_device *phydev, int port)
{
	bool is_fibre = (port == PORT_FIBRE ? true : false);
	int addr = phydev->mdio.addr;

	pr_debug("%s port %d to %d\n", __func__, addr, port);

	rtl8380_rtl8214fc_media_set(addr, is_fibre);
	return 0;
}

static int rtl8380_rtl8214fc_get_port(struct phy_device *phydev)
{
	int addr = phydev->mdio.addr;

	pr_debug("%s: port %d\n", __func__, addr);
	if (rtl8380_rtl8214fc_media_is_fibre(addr))
		return PORT_FIBRE;
	return PORT_MII;
}

void rtl8380_rtl8214fc_ldps_set(int mac, struct ethtool_eee *e)
{

}

static void rtl8380_rtl8218b_eee_set_u_boot(int port, bool enable)
{
	u32 val;
	bool an_enabled;

	/* Set GPHY page to copper */
	write_phy(port, 0, 30, 0x0001);
	read_phy(port, 0, 0, &val);
	an_enabled = val & (1 << 12);

	if (enable) {
		/* 100/1000M EEE Capability */
		write_phy(port, 0, 13, 0x0007);
		write_phy(port, 0, 14, 0x003C);
		write_phy(port, 0, 13, 0x4007);
		write_phy(port, 0, 14, 0x0006);

		read_phy(port, 0x0A43, 25, &val);
		val |= 1 << 4;
		write_phy(port, 0x0A43, 25, val);
	} else {
		/* 100/1000M EEE Capability */
		write_phy(port, 0, 13, 0x0007);
		write_phy(port, 0, 14, 0x003C);
		write_phy(port, 0, 13, 0x0007);
		write_phy(port, 0, 14, 0x0000);

		read_phy(port, 0x0A43, 25, &val);
		val &= ~(1 << 4);
		write_phy(port, 0x0A43, 25, val);
	}

	/* Restart AN if enabled */
	if (an_enabled) {
		read_phy(port, 0, 0, &val);
		val |= (1 << 12) | (1 << 9);
		write_phy(port, 0, 0, val);
	}

	/* GPHY page back to auto*/
	write_phy(port, 0xa42, 29, 0);
}

static	int rtl8380_rtl8218b_get_eee_u_boot(struct phy_device *phydev, struct ethtool_eee *e)
{
	u32 val;
	int addr = phydev->mdio.addr;

	pr_debug("In %s %d\n", __func__, addr);

	/* Set GPHY page to copper */
	write_phy(addr, 0xa42, 29, 0x0001);

	read_phy(addr, 0xa43, 25, &val);
	if (e->eee_enabled && (!!(val & (1 << 4))))
		e->eee_enabled = !!(val & (1 << 4));
	else
		e->eee_enabled = 0;

	/* GPHY page to auto */
	write_phy(addr, 0xa42, 29, 0x0000);

	return 0;
}

void rtl8380_rtl8218b_eee_set(int port, bool enable)
{
	u32 val;
	bool an_enabled;

	pr_debug("In %s %d, enable %d\n", __func__, port, enable);
	/* Set GPHY page to copper */
	write_phy(port, 0xa42, 29, 0x0001);

	read_phy(port, 0, 0, &val);
	an_enabled = val & (1 << 12);

	/* MAC based EEE */
	read_phy(port, 0xa43, 25, &val);
	val &= ~(1 << 5);
	write_phy(port, 0xa43, 25, val);

	/* 100M / 1000M EEE */
	if (enable)
		rtl838x_write_mmd_phy(port, 7, 60, 0x6);
	else
		rtl838x_write_mmd_phy(port, 7, 60, 0);

	/* 500M EEE ability */
	read_phy(port, 0xa42, 20, &val);
	if (enable)
		val |= 1 << 7;
	else
		val &= ~(1 << 7);
	write_phy(port, 0xa42, 20, val);

	/* Restart AN if enabled */
	if (an_enabled) {
		read_phy(port, 0, 0, &val);
		val |= (1 << 12) | (1 << 9);
		write_phy(port, 0, 0, val);
	}

	/* GPHY page back to auto*/
	write_phy(port, 0xa42, 29, 0);
}

int rtl8380_rtl8218b_get_eee(struct phy_device *phydev,
				     struct ethtool_eee *e)
{
	u32 val;
	int addr = phydev->mdio.addr;

	pr_debug("In %s, port %d\n", __func__, addr);

	/* Set GPHY page to copper */
	write_phy(addr, 0xa42, 29, 0x0001);

	rtl838x_read_mmd_phy(addr, 7, 60, &val);
	if (e->eee_enabled && (!!(val & (1 << 7))))
		e->eee_enabled = !!(val & (1 << 7));
	else
		e->eee_enabled = 0;

	/* GPHY page to auto */
	write_phy(addr, 0xa42, 29, 0x0000);

	return 0;
}

void rtl8380_rtl8218b_green_set(int mac, bool enable)
{
	u32 val;

	/* Set GPHY page to copper */
	write_phy(mac, 0xa42, 29, 0x0001);

	write_phy(mac, 0, 27, 0x8011);
	read_phy(mac, 0, 28, &val);
	if (enable) {
		val |= 1 << 9;
		write_phy(mac, 0, 27, 0x8011);
		write_phy(mac, 0, 28, val);
	} else {
		val &= ~(1 << 9);
		write_phy(mac, 0, 27, 0x8011);
		write_phy(mac, 0, 28, val);
	}

	/* GPHY page to auto */
	write_phy(mac, 0xa42, 29, 0x0000);
}

int rtl8380_rtl8214fc_get_green(struct phy_device *phydev, struct ethtool_eee *e)
{
	u32 val;
	int addr = phydev->mdio.addr;

	pr_debug("In %s %d\n", __func__, addr);
	/* Set GPHY page to copper */
	write_phy(addr, 0xa42, 29, 0x0001);

	write_phy(addr, 0, 27, 0x8011);
	read_phy(addr, 0, 28, &val);
	if (e->eee_enabled && (!!(val & (1 << 9))))
		e->eee_enabled = !!(val & (1 << 9));
	else
		e->eee_enabled = 0;

	/* GPHY page to auto */
	write_phy(addr, 0xa42, 29, 0x0000);

	return 0;
}

static	int rtl8380_rtl8214fc_set_eee(struct phy_device *phydev,
				      struct ethtool_eee *e)
{
	u32 pollMask;
	int addr = phydev->mdio.addr;

	pr_debug("In %s port %d, enabled %d\n", __func__, addr, e->eee_enabled);

	if (rtl8380_rtl8214fc_media_is_fibre(addr)) {
		netdev_err(phydev->attached_dev, "Port %d configured for FIBRE", addr);
		return -ENOTSUPP;
	}

	pollMask = sw_r32(RTL838X_SMI_POLL_CTRL);
	sw_w32(0, RTL838X_SMI_POLL_CTRL);
	rtl8380_rtl8218b_eee_set_u_boot(addr, (bool) e->eee_enabled);
	sw_w32(pollMask, RTL838X_SMI_POLL_CTRL);
	return 0;
}

static	int rtl8380_rtl8214fc_get_eee(struct phy_device *phydev,
				      struct ethtool_eee *e)
{
	int addr = phydev->mdio.addr;

	pr_debug("In %s port %d, enabled %d\n", __func__, addr, e->eee_enabled);
	if (rtl8380_rtl8214fc_media_is_fibre(addr)) {
		netdev_err(phydev->attached_dev, "Port %d configured for FIBRE", addr);
		return -ENOTSUPP;
	}

	return rtl8380_rtl8218b_get_eee_u_boot(phydev, e);
}

static	int rtl8380_rtl8218b_set_eee(struct phy_device *phydev,
				     struct ethtool_eee *e)
{
	u32 pollMask;
	int addr = phydev->mdio.addr;

	pr_debug("In %s, port %d, enabled %d\n", __func__, addr, e->eee_enabled);

	pollMask = sw_r32(RTL838X_SMI_POLL_CTRL);
	sw_w32(0, RTL838X_SMI_POLL_CTRL);
	rtl8380_rtl8218b_eee_set_u_boot(addr, (bool) e->eee_enabled);
	sw_w32(pollMask, RTL838X_SMI_POLL_CTRL);

	return 0;
}

static int rtl8214c_match_phy_device(struct phy_device *phydev)
{
	return phydev->phy_id == PHY_ID_RTL8214C;
}

static int rtl8380_configure_rtl8214c(struct phy_device *phydev)
{
	u32 phy_id, val;
	int mac = phydev->mdio.addr;

	read_phy(mac, 0, 2, &val);
	phy_id = val << 16;
	read_phy(mac, 0, 3, &val);
	phy_id |= val;
	pr_debug("Phy on MAC %d: %x\n", mac, phy_id);

	phydev_info(phydev, "Detected external RTL8214C\n");

	/* GPHY auto conf */
	write_phy(mac, 0xa42, 29, 0);
	return 0;
}

static int rtl8380_configure_rtl8214fc(struct phy_device *phydev)
{
	u32 phy_id, val, page = 0;
	int i, l;
	int mac = phydev->mdio.addr;
	struct fw_header *h;
	u32 *rtl8380_rtl8214fc_perchip;
	u32 *rtl8380_rtl8214fc_perport;

	read_phy(mac, 0, 2, &val);
	phy_id = val << 16;
	read_phy(mac, 0, 3, &val);
	phy_id |= val;
	pr_debug("Phy on MAC %d: %x\n", mac, phy_id);

	/* Read internal PHY id */
	write_phy(mac, 0, 30, 0x0001);
	write_phy(mac, 0, 31, 0x0a42);
	write_phy(mac, 31, 27, 0x0002);
	read_phy(mac, 31, 28, &val);
	if (val != 0x6276) {
		phydev_err(phydev, "Expected external RTL8214FC, found PHY-ID %x\n", val);
		return -1;
	}
	phydev_info(phydev, "Detected external RTL8214FC\n");

	h = rtl838x_request_fw(phydev, &rtl838x_8214fc_fw, FIRMWARE_838X_8214FC_1);
	if (!h)
		return -1;

	if (h->phy != 0x8214fc00) {
		phydev_err(phydev, "Wrong firmware file: PHY mismatch.\n");
		return -1;
	}

	rtl8380_rtl8214fc_perchip = (void *)h + sizeof(struct fw_header)
		   + h->parts[0].start;

	rtl8380_rtl8214fc_perport = (void *)h + sizeof(struct fw_header)
		   + h->parts[1].start;

	/* detect phy version */
	write_phy(mac, 0xfff, 27, 0x0004);
	read_phy(mac, 0xfff, 28, &val);

	read_phy(mac, 0, 16, &val);
	if (val & (1 << 11))
		rtl8380_rtl8214fc_on_off(mac, true);
	else
		rtl8380_phy_reset(mac);

	msleep(100);
	write_phy(mac, 0, 30, 0x0001);

	i = 0;
	while (rtl8380_rtl8214fc_perchip[i * 3]
	       && rtl8380_rtl8214fc_perchip[i * 3 + 1]) {
		if (rtl8380_rtl8214fc_perchip[i * 3 + 1] == 0x1f)
			page = rtl8380_rtl8214fc_perchip[i * 3 + 2];
		if (rtl8380_rtl8214fc_perchip[i * 3 + 1] == 0x13 && page == 0x260) {
			read_phy(mac + rtl8380_rtl8214fc_perchip[i * 3], 0x260, 13, &val);
			val = (val & 0x1f00) | (rtl8380_rtl8214fc_perchip[i * 3 + 2]
				& 0xe0ff);
			write_phy(mac + rtl8380_rtl8214fc_perchip[i * 3],
					  0xfff, rtl8380_rtl8214fc_perchip[i * 3 + 1], val);
		} else {
			write_phy(mac + rtl8380_rtl8214fc_perchip[i * 3],
					  0xfff, rtl8380_rtl8214fc_perchip[i * 3 + 1],
					  rtl8380_rtl8214fc_perchip[i * 3 + 2]);
		}
		i++;
	}

	/* Force copper medium */
	for (i = 0; i < 4; i++) {
		write_phy(mac + i, 0xfff, 0x1f, 0x0000);
		write_phy(mac + i, 0xfff, 0x1e, 0x0001);
	}

	/* Enable PHY */
	for (i = 0; i < 4; i++) {
		write_phy(mac + i, 0xfff, 0x1f, 0x0000);
		write_phy(mac + i, 0xfff, 0x00, 0x1140);
	}
	mdelay(100);

	/* Disable Autosensing */
	for (i = 0; i < 4; i++) {
		for (l = 0; l < 100; l++) {
			read_phy(mac + i, 0x0a42, 0x10, &val);
			if ((val & 0x7) >= 3)
				break;
		}
		if (l >= 100) {
			phydev_err(phydev, "Could not disable autosensing\n");
			return -1;
		}
	}

	/* Request patch */
	for (i = 0; i < 4; i++) {
		write_phy(mac + i,  0xfff, 0x1f, 0x0b82);
		write_phy(mac + i,  0xfff, 0x10, 0x0010);
	}
	mdelay(300);

	/* Verify patch readiness */
	for (i = 0; i < 4; i++) {
		for (l = 0; l < 100; l++) {
			read_phy(mac + i, 0xb80, 0x10, &val);
			if (val & 0x40)
				break;
		}
		if (l >= 100) {
			phydev_err(phydev, "Could not patch PHY\n");
			return -1;
		}
	}

	/* Use Broadcast ID method for patching */
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0008);
	write_phy(mac, 0xfff, 0x1f, 0x0266);
	write_phy(mac, 0xfff, 0x16, 0xff00 + mac);
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0000);
	mdelay(1);

	i = 0;
	while (rtl8380_rtl8214fc_perport[i * 2]) {
		write_phy(mac, 0xfff, rtl8380_rtl8214fc_perport[i * 2],
				  rtl8380_rtl8214fc_perport[i * 2 + 1]);
		i++;
	}

	/*Disable broadcast ID*/
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0008);
	write_phy(mac, 0xfff, 0x1f, 0x0266);
	write_phy(mac, 0xfff, 0x16, 0x00 + mac);
	write_phy(mac, 0xfff, 0x1f, 0x0000);
	write_phy(mac, 0xfff, 0x1d, 0x0000);
	mdelay(1);

	/* Auto medium selection */
	for (i = 0; i < 4; i++) {
		write_phy(mac + i, 0xfff, 0x1f, 0x0000);
		write_phy(mac + i, 0xfff, 0x1e, 0x0000);
	}

	return 0;
}

static int rtl8214fc_match_phy_device(struct phy_device *phydev)
{
	int addr = phydev->mdio.addr;

	return phydev->phy_id == PHY_ID_RTL8214FC && addr >= 24;
}

static int rtl8380_configure_serdes(struct phy_device *phydev)
{
	u32 v;
	u32 sds_conf_value;
	int i;
	struct fw_header *h;
	u32 *rtl8380_sds_take_reset;
	u32 *rtl8380_sds_common;
	u32 *rtl8380_sds01_qsgmii_6275b;
	u32 *rtl8380_sds23_qsgmii_6275b;
	u32 *rtl8380_sds4_fiber_6275b;
	u32 *rtl8380_sds5_fiber_6275b;
	u32 *rtl8380_sds_reset;
	u32 *rtl8380_sds_release_reset;

	phydev_info(phydev, "Detected internal RTL8380 SERDES\n");

	h = rtl838x_request_fw(phydev, &rtl838x_8218b_fw, FIRMWARE_838X_8380_1);
	if (!h)
		return -1;

	if (h->magic != 0x83808380) {
		phydev_err(phydev, "Wrong firmware file: magic number mismatch.\n");
		return -1;
	}

	rtl8380_sds_take_reset = (void *)h + sizeof(struct fw_header)
		   + h->parts[0].start;

	rtl8380_sds_common = (void *)h + sizeof(struct fw_header)
		   + h->parts[1].start;

	rtl8380_sds01_qsgmii_6275b = (void *)h + sizeof(struct fw_header)
		   + h->parts[2].start;

	rtl8380_sds23_qsgmii_6275b = (void *)h + sizeof(struct fw_header)
		   + h->parts[3].start;

	rtl8380_sds4_fiber_6275b = (void *)h + sizeof(struct fw_header)
		   + h->parts[4].start;

	rtl8380_sds5_fiber_6275b = (void *)h + sizeof(struct fw_header)
		   + h->parts[5].start;

	rtl8380_sds_reset = (void *)h + sizeof(struct fw_header)
		   + h->parts[6].start;

	rtl8380_sds_release_reset = (void *)h + sizeof(struct fw_header)
		   + h->parts[7].start;

	/* Back up serdes power off value */
	sds_conf_value = sw_r32(RTL838X_SDS_CFG_REG);
	pr_info("SDS power down value: %x\n", sds_conf_value);

	/* take serdes into reset */
	i = 0;
	while (rtl8380_sds_take_reset[2 * i]) {
		sw_w32(rtl8380_sds_take_reset[2 * i + 1], rtl8380_sds_take_reset[2 * i]);
		i++;
		udelay(1000);
	}

	/* apply common serdes patch */
	i = 0;
	while (rtl8380_sds_common[2 * i]) {
		sw_w32(rtl8380_sds_common[2 * i + 1], rtl8380_sds_common[2 * i]);
		i++;
		udelay(1000);
	}

	/* internal R/W enable */
	sw_w32(3, RTL838X_INT_RW_CTRL);

	/* SerDes ports 4 and 5 are FIBRE ports */
	sw_w32_mask(0x7 | 0x38, 1 | (1 << 3), RTL838X_INT_MODE_CTRL);

	/* SerDes module settings, SerDes 0-3 are QSGMII */
	v = 0x6 << 25 | 0x6 << 20 | 0x6 << 15 | 0x6 << 10;
	/* SerDes 4 and 5 are 1000BX FIBRE */
	v |= 0x4 << 5 | 0x4;
	sw_w32(v, RTL838X_SDS_MODE_SEL);

	pr_info("PLL control register: %x\n", sw_r32(RTL838X_PLL_CML_CTRL));
	sw_w32_mask(0xfffffff0, 0xaaaaaaaf & 0xf, RTL838X_PLL_CML_CTRL);
	i = 0;
	while (rtl8380_sds01_qsgmii_6275b[2 * i]) {
		sw_w32(rtl8380_sds01_qsgmii_6275b[2 * i + 1],
			rtl8380_sds01_qsgmii_6275b[2 * i]);
		i++;
	}

	i = 0;
	while (rtl8380_sds23_qsgmii_6275b[2 * i]) {
		sw_w32(rtl8380_sds23_qsgmii_6275b[2 * i + 1], rtl8380_sds23_qsgmii_6275b[2 * i]);
		i++;
	}

	i = 0;
	while (rtl8380_sds4_fiber_6275b[2 * i]) {
		sw_w32(rtl8380_sds4_fiber_6275b[2 * i + 1], rtl8380_sds4_fiber_6275b[2 * i]);
		i++;
	}

	i = 0;
	while (rtl8380_sds5_fiber_6275b[2 * i]) {
		sw_w32(rtl8380_sds5_fiber_6275b[2 * i + 1], rtl8380_sds5_fiber_6275b[2 * i]);
		i++;
	}

	i = 0;
	while (rtl8380_sds_reset[2 * i]) {
		sw_w32(rtl8380_sds_reset[2 * i + 1], rtl8380_sds_reset[2 * i]);
		i++;
	}

	i = 0;
	while (rtl8380_sds_release_reset[2 * i]) {
		sw_w32(rtl8380_sds_release_reset[2 * i + 1], rtl8380_sds_release_reset[2 * i]);
		i++;
	}

	pr_info("SDS power down value now: %x\n", sw_r32(RTL838X_SDS_CFG_REG));
	sw_w32(sds_conf_value, RTL838X_SDS_CFG_REG);

	pr_info("Configuration of SERDES done\n");
	return 0;
}

static int rtl8390_configure_serdes(struct phy_device *phydev)
{
	phydev_info(phydev, "Detected internal RTL8390 SERDES\n");

	/* In autoneg state, force link, set SR4_CFG_EN_LINK_FIB1G */
	sw_w32_mask(0, 1 << 18, RTL839X_SDS12_13_XSG0 + 0x0a);

	/* Disable EEE: Clear FRE16_EEE_RSG_FIB1G, FRE16_EEE_STD_FIB1G,
	 * FRE16_C1_PWRSAV_EN_FIB1G, FRE16_C2_PWRSAV_EN_FIB1G
	 * and FRE16_EEE_QUIET_FIB1G
	 */
	sw_w32_mask(0x1f << 10, 0, RTL839X_SDS12_13_XSG0 + 0xe0);

	return 0;
}

static int rtl8214fc_phy_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	/* 839x has internal SerDes */
	if (soc_info.id == 0x8393)
		return -ENODEV;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8214FC";

	/* All base addresses of the PHYs start at multiples of 8 */
	if (!(addr % 8)) {
		/* Configuration must be done whil patching still possible */
		return rtl8380_configure_rtl8214fc(phydev);
	}
	return 0;
}

static int rtl8214c_phy_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8214C";

	/* All base addresses of the PHYs start at multiples of 8 */
	if (!(addr % 8)) {
		/* Configuration must be done whil patching still possible */
		return rtl8380_configure_rtl8214c(phydev);
	}
	return 0;
}

static int rtl8218b_ext_phy_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8218B (external)";

	/* All base addresses of the PHYs start at multiples of 8 */
	if (!(addr % 8) && soc_info.family == RTL8380_FAMILY_ID) {
		/* Configuration must be done while patching still possible */
		return rtl8380_configure_ext_rtl8218b(phydev);
	}
	return 0;
}

static int rtl8218b_int_phy_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	if (soc_info.family != RTL8380_FAMILY_ID)
		return -ENODEV;
	if (addr >= 24)
		return -ENODEV;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8218B (internal)";

	/* All base addresses of the PHYs start at multiples of 8 */
	if (!(addr % 8)) {
		/* Configuration must be done while patching still possible */
		return rtl8380_configure_int_rtl8218b(phydev);
	}
	return 0;
}

static int rtl838x_serdes_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	if (soc_info.family != RTL8380_FAMILY_ID)
		return -ENODEV;
	if (addr < 24)
		return -ENODEV;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8380 Serdes";

	/* On the RTL8380M, PHYs 24-27 connect to the internal SerDes */
	if (soc_info.id == 0x8380) {
		if (addr == 24)
			return rtl8380_configure_serdes(phydev);
		return 0;
	}
	return -ENODEV;
}

static int rtl8393_serdes_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	pr_info("%s: id: %d\n", __func__, addr);
	if (soc_info.family != RTL8390_FAMILY_ID)
		return -ENODEV;

	if (addr < 24)
		return -ENODEV;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8393 Serdes";
	return rtl8390_configure_serdes(phydev);
}

static int rtl8390_serdes_probe(struct phy_device *phydev)
{
	struct device *dev = &phydev->mdio.dev;
	struct rtl838x_phy_priv *priv;
	int addr = phydev->mdio.addr;

	if (soc_info.family != RTL8390_FAMILY_ID)
		return -ENODEV;

	if (addr < 24)
		return -ENODEV;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->name = "RTL8390 Serdes";
	return rtl8390_configure_generic(phydev);
}

static struct phy_driver rtl838x_phy_driver[] = {
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8214C),
		.name		= "REALTEK RTL8214C",
		.features	= PHY_GBIT_FEATURES,
		.match_phy_device = rtl8214c_match_phy_device,
		.probe		= rtl8214c_phy_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
	},
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8214FC),
		.name		= "REALTEK RTL8214FC",
		.features	= PHY_GBIT_FIBRE_FEATURES,
		.match_phy_device = rtl8214fc_match_phy_device,
		.probe		= rtl8214fc_phy_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
		.read_mmd	= rtl8380_rtl8218b_read_mmd,
		.write_mmd	= rtl8380_rtl8218b_write_mmd,
		.set_port	= rtl8380_rtl8214fc_set_port,
		.get_port	= rtl8380_rtl8214fc_get_port,
		.set_eee	= rtl8380_rtl8214fc_set_eee,
		.get_eee	= rtl8380_rtl8214fc_get_eee,
	},
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8218B_E),
		.name		= "REALTEK RTL8218B (external)",
		.features	= PHY_GBIT_FEATURES,
		.match_phy_device = rtl8218b_ext_match_phy_device,
		.probe		= rtl8218b_ext_phy_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
		.read_mmd	= rtl8380_rtl8218b_read_mmd,
		.write_mmd	= rtl8380_rtl8218b_write_mmd,
		.set_eee	= rtl8380_rtl8218b_set_eee,
		.get_eee	= rtl8380_rtl8218b_get_eee_u_boot,
	},
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8218B_I),
		.name		= "REALTEK RTL8218B (internal)",
		.features	= PHY_GBIT_FEATURES,
		.probe		= rtl8218b_int_phy_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
		.read_mmd	= rtl8380_rtl8218b_read_mmd,
		.write_mmd	= rtl8380_rtl8218b_write_mmd,
		.set_eee	= rtl8380_rtl8218b_set_eee,
		.get_eee	= rtl8380_rtl8218b_get_eee_u_boot,
	},
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8218B_I),
		.name		= "REALTEK RTL8380 SERDES",
		.features	= PHY_GBIT_FIBRE_FEATURES,
		.probe		= rtl838x_serdes_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
		.read_mmd	= rtl8380_rtl8218b_read_mmd,
		.write_mmd	= rtl8380_rtl8218b_write_mmd,
		.read_status	= rtl8380_read_status,
	},
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8393_I),
		.name		= "REALTEK RTL8393 SERDES",
		.features	= PHY_GBIT_FIBRE_FEATURES,
		.probe		= rtl8393_serdes_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
		.read_status	= rtl8393_read_status,
	},
	{
		PHY_ID_MATCH_MODEL(PHY_ID_RTL8390_GENERIC),
		.name		= "REALTEK RTL8390 Generic",
		.features	= PHY_GBIT_FIBRE_FEATURES,
		.probe		= rtl8390_serdes_probe,
		.suspend	= genphy_suspend,
		.resume		= genphy_resume,
		.set_loopback	= genphy_loopback,
	}
};

module_phy_driver(rtl838x_phy_driver);

static struct mdio_device_id __maybe_unused rtl838x_tbl[] = {
	{ PHY_ID_MATCH_MODEL(PHY_ID_RTL8214FC) },
	{ }
};

MODULE_DEVICE_TABLE(mdio, rtl838x_tbl);

MODULE_AUTHOR("B. Koblitz");
MODULE_DESCRIPTION("RTL838x PHY driver");
MODULE_LICENSE("GPL");
