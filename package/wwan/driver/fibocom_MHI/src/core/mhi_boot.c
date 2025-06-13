/* Copyright (c) 2018, The Linux Foundation. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 and
 * only version 2 as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/dma-direction.h>
#include <linux/dma-mapping.h>
#include <linux/firmware.h>
#include <linux/interrupt.h>
#include <linux/list.h>
#include <linux/of.h>
#include <linux/module.h>
#include <linux/random.h>
#include <linux/slab.h>
#include <linux/sched.h>
#include <linux/wait.h>
#include <linux/uaccess.h>
#include "mhi.h"
#include "mhi_internal.h"

#define IOCTL_BHI_GETDEVINFO 0x8BE0 + 1
#define IOCTL_BHI_WRITEIMAGE 0x8BE0 + 2

/* Software defines */
/* BHI Version */
#define BHI_MAJOR_VERSION 0x1
#define BHI_MINOR_VERSION 0x1

#define MSMHWID_NUMDWORDS 6       /* Number of dwords that make the MSMHWID */
#define OEMPKHASH_NUMDWORDS 48    /* Number of dwords that make the OEM PK HASH */

#define IsPBLExecEnv(ExecEnv)   ((ExecEnv == MHI_EE_PBL) || (ExecEnv == MHI_EE_EDL) )

typedef u32 ULONG;

typedef struct _bhi_info_type
{
   ULONG bhi_ver_minor;
   ULONG bhi_ver_major;
   ULONG bhi_image_address_low;
   ULONG bhi_image_address_high;
   ULONG bhi_image_size;
   ULONG bhi_rsvd1;
   ULONG bhi_imgtxdb;
   ULONG bhi_rsvd2;
   ULONG bhi_msivec;
   ULONG bhi_rsvd3;
   ULONG bhi_ee;
   ULONG bhi_status;
   ULONG bhi_errorcode;
   ULONG bhi_errdbg1;
   ULONG bhi_errdbg2;
   ULONG bhi_errdbg3;
   ULONG bhi_sernum;
   ULONG bhi_sblantirollbackver;
   ULONG bhi_numsegs;
   ULONG bhi_msmhwid[6];
   ULONG bhi_oempkhash[48];
   ULONG bhi_rsvd5;
}BHI_INFO_TYPE, *PBHI_INFO_TYPE;

#if 0
static void PrintBhiInfo(BHI_INFO_TYPE *bhi_info)
{
   ULONG index;

   printk("BHI Device Info...\n");
   printk("BHI Version               = { Major = 0x%X Minor = 0x%X}\n", bhi_info->bhi_ver_major, bhi_info->bhi_ver_minor);
   printk("BHI Execution Environment = 0x%X\n", bhi_info->bhi_ee);
   printk("BHI Status                = 0x%X\n", bhi_info->bhi_status);
   printk("BHI Error code            = 0x%X { Dbg1 = 0x%X Dbg2 = 0x%X Dbg3 = 0x%X }\n", bhi_info->bhi_errorcode, bhi_info->bhi_errdbg1, bhi_info->bhi_errdbg2, bhi_info->bhi_errdbg3);
   printk("BHI Serial Number         = 0x%X\n", bhi_info->bhi_sernum);
   printk("BHI SBL Anti-Rollback Ver = 0x%X\n", bhi_info->bhi_sblantirollbackver);
   printk("BHI Number of Segments    = 0x%X\n", bhi_info->bhi_numsegs);
   printk("BHI MSM HW-Id             = ");
   for (index = 0; index < 6; index++)
   {
      printk("0x%X ", bhi_info->bhi_msmhwid[index]);
   }
   printk("\n");

   printk("BHI OEM PK Hash           =  \n");
   for (index = 0; index < 24; index++)
   {
      printk("0x%X ", bhi_info->bhi_oempkhash[index]);
   }
   printk("\n");
}
#endif

static u32 bhi_read_reg(struct mhi_controller *mhi_cntrl, u32 offset)
{
	u32 out = 0;
	int ret = mhi_read_reg(mhi_cntrl, mhi_cntrl->bhi, offset, &out);

	return (ret) ? 0 : out;
}

static int BhiRead(struct mhi_controller *mhi_cntrl, BHI_INFO_TYPE *bhi_info)
{
	ULONG index;

	memset(bhi_info, 0x00, sizeof(BHI_INFO_TYPE));

	/* bhi_ver */
	bhi_info->bhi_ver_minor = bhi_read_reg(mhi_cntrl, BHI_BHIVERSION_MINOR);
	bhi_info->bhi_ver_major = bhi_read_reg(mhi_cntrl, BHI_BHIVERSION_MINOR);
	bhi_info->bhi_image_address_low = bhi_read_reg(mhi_cntrl, BHI_IMGADDR_LOW);
	bhi_info->bhi_image_address_high = bhi_read_reg(mhi_cntrl, BHI_IMGADDR_HIGH);
	bhi_info->bhi_image_size = bhi_read_reg(mhi_cntrl, BHI_IMGSIZE);
	bhi_info->bhi_rsvd1 = bhi_read_reg(mhi_cntrl, BHI_RSVD1);
	bhi_info->bhi_imgtxdb = bhi_read_reg(mhi_cntrl, BHI_IMGTXDB);
	bhi_info->bhi_rsvd2 = bhi_read_reg(mhi_cntrl, BHI_RSVD2);
	bhi_info->bhi_msivec = bhi_read_reg(mhi_cntrl, BHI_INTVEC);
	bhi_info->bhi_rsvd3 = bhi_read_reg(mhi_cntrl, BHI_RSVD3);
	bhi_info->bhi_ee = bhi_read_reg(mhi_cntrl, BHI_EXECENV);
	bhi_info->bhi_status = bhi_read_reg(mhi_cntrl, BHI_STATUS);
	bhi_info->bhi_errorcode = bhi_read_reg(mhi_cntrl, BHI_ERRCODE);
	bhi_info->bhi_errdbg1 = bhi_read_reg(mhi_cntrl, BHI_ERRDBG1);
	bhi_info->bhi_errdbg2 = bhi_read_reg(mhi_cntrl, BHI_ERRDBG2);
	bhi_info->bhi_errdbg3 = bhi_read_reg(mhi_cntrl, BHI_ERRDBG3);
	bhi_info->bhi_sernum = bhi_read_reg(mhi_cntrl, BHI_SERIALNUM);
	bhi_info->bhi_sblantirollbackver = bhi_read_reg(mhi_cntrl, BHI_SBLANTIROLLVER);
	bhi_info->bhi_numsegs = bhi_read_reg(mhi_cntrl, BHI_NUMSEG);
	for (index = 0; index < MSMHWID_NUMDWORDS; index++)
	{
		bhi_info->bhi_msmhwid[index] = bhi_read_reg(mhi_cntrl, BHI_MSMHWID(index));
	}
	for (index = 0; index < OEMPKHASH_NUMDWORDS; index++)
	{
		bhi_info->bhi_oempkhash[index] = bhi_read_reg(mhi_cntrl, BHI_OEMPKHASH(index));
	}
	bhi_info->bhi_rsvd5 = bhi_read_reg(mhi_cntrl, BHI_RSVD5);
	//PrintBhiInfo(bhi_info);
	/* Check the Execution Environment */
	if (!IsPBLExecEnv(bhi_info->bhi_ee))
	{
		printk("E - EE: 0x%X Expected PBL/EDL\n", bhi_info->bhi_ee);
	}

	/* Return the number of bytes read */
	return 0;
}

/* setup rddm vector table for rddm transfer */
static void mhi_rddm_prepare(struct mhi_controller *mhi_cntrl,
			     struct image_info *img_info)
{
	struct mhi_buf *mhi_buf = img_info->mhi_buf;
	struct bhi_vec_entry *bhi_vec = img_info->bhi_vec;
	int i = 0;

	for (i = 0; i < img_info->entries - 1; i++, mhi_buf++, bhi_vec++) {
		MHI_VERB("Setting vector:%pad size:%zu\n",
			 &mhi_buf->dma_addr, mhi_buf->len);
		bhi_vec->dma_addr = mhi_buf->dma_addr;
		bhi_vec->size = mhi_buf->len;
	}
}

/* collect rddm during kernel panic */
static int __mhi_download_rddm_in_panic(struct mhi_controller *mhi_cntrl)
{
	int ret;
	struct mhi_buf *mhi_buf;
	u32 sequence_id;
	u32 rx_status;
	enum MHI_EE ee;
	struct image_info *rddm_image = mhi_cntrl->rddm_image;
	const u32 delayus = 100;
	u32 retry = (mhi_cntrl->timeout_ms * 1000) / delayus;
	void __iomem *base = mhi_cntrl->bhi;

	MHI_LOG("Entered with pm_state:%s dev_state:%s ee:%s\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		TO_MHI_EXEC_STR(mhi_cntrl->ee));

	/*
	 * This should only be executing during a kernel panic, we expect all
	 * other cores to shutdown while we're collecting rddm buffer. After
	 * returning from this function, we expect device to reset.
	 *
	 * Normaly, we would read/write pm_state only after grabbing
	 * pm_lock, since we're in a panic, skipping it.
	 */

	if (!MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state))
		return -EIO;

	/*
	 * There is no gurantee this state change would take effect since
	 * we're setting it w/o grabbing pmlock, it's best effort
	 */
	mhi_cntrl->pm_state = MHI_PM_LD_ERR_FATAL_DETECT;
	/* update should take the effect immediately */
	smp_wmb();

	/* setup the RX vector table */
	mhi_rddm_prepare(mhi_cntrl, rddm_image);
	mhi_buf = &rddm_image->mhi_buf[rddm_image->entries - 1];

	MHI_LOG("Starting BHIe programming for RDDM\n");

	mhi_write_reg(mhi_cntrl, base, BHIE_RXVECADDR_HIGH_OFFS,
		      upper_32_bits(mhi_buf->dma_addr));

	mhi_write_reg(mhi_cntrl, base, BHIE_RXVECADDR_LOW_OFFS,
		      lower_32_bits(mhi_buf->dma_addr));

	mhi_write_reg(mhi_cntrl, base, BHIE_RXVECSIZE_OFFS, mhi_buf->len);
	sequence_id = prandom_u32() & BHIE_RXVECSTATUS_SEQNUM_BMSK;

	if (unlikely(!sequence_id))
		sequence_id = 1;


	mhi_write_reg_field(mhi_cntrl, base, BHIE_RXVECDB_OFFS,
			    BHIE_RXVECDB_SEQNUM_BMSK, BHIE_RXVECDB_SEQNUM_SHFT,
			    sequence_id);

	MHI_LOG("Trigger device into RDDM mode\n");
	mhi_set_mhi_state(mhi_cntrl, MHI_STATE_SYS_ERR);

	MHI_LOG("Waiting for image download completion\n");
	while (retry--) {
		ret = mhi_read_reg_field(mhi_cntrl, base, BHIE_RXVECSTATUS_OFFS,
					 BHIE_RXVECSTATUS_STATUS_BMSK,
					 BHIE_RXVECSTATUS_STATUS_SHFT,
					 &rx_status);
		if (ret)
			return -EIO;

		if (rx_status == BHIE_RXVECSTATUS_STATUS_XFER_COMPL) {
			MHI_LOG("RDDM successfully collected\n");
			return 0;
		}

		udelay(delayus);
	}

	ee = mhi_get_exec_env(mhi_cntrl);
	ret = mhi_read_reg(mhi_cntrl, base, BHIE_RXVECSTATUS_OFFS, &rx_status);

	MHI_ERR("Did not complete RDDM transfer\n");
	MHI_ERR("Current EE:%s\n", TO_MHI_EXEC_STR(ee));
	MHI_ERR("RXVEC_STATUS:0x%x, ret:%d\n", rx_status, ret);

	return -EIO;
}

/* download ramdump image from device */
int mhi_download_rddm_img(struct mhi_controller *mhi_cntrl, bool in_panic)
{
	void __iomem *base = mhi_cntrl->bhi;
	rwlock_t *pm_lock = &mhi_cntrl->pm_lock;
	struct image_info *rddm_image = mhi_cntrl->rddm_image;
	struct mhi_buf *mhi_buf;
	int ret;
	u32 rx_status;
	u32 sequence_id;

	if (!rddm_image)
		return -ENOMEM;

	if (in_panic)
		return __mhi_download_rddm_in_panic(mhi_cntrl);

	MHI_LOG("Waiting for device to enter RDDM state from EE:%s\n",
		TO_MHI_EXEC_STR(mhi_cntrl->ee));

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->ee == MHI_EE_RDDM ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("MHI is not in valid state, pm_state:%s ee:%s\n",
			to_mhi_pm_state_str(mhi_cntrl->pm_state),
			TO_MHI_EXEC_STR(mhi_cntrl->ee));
		return -EIO;
	}

	mhi_rddm_prepare(mhi_cntrl, mhi_cntrl->rddm_image);

	/* vector table is the last entry */
	mhi_buf = &rddm_image->mhi_buf[rddm_image->entries - 1];

	read_lock_bh(pm_lock);
	if (!MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state)) {
		read_unlock_bh(pm_lock);
		return -EIO;
	}

	MHI_LOG("Starting BHIe Programming for RDDM\n");

	mhi_write_reg(mhi_cntrl, base, BHIE_RXVECADDR_HIGH_OFFS,
		      upper_32_bits(mhi_buf->dma_addr));

	mhi_write_reg(mhi_cntrl, base, BHIE_RXVECADDR_LOW_OFFS,
		      lower_32_bits(mhi_buf->dma_addr));

	mhi_write_reg(mhi_cntrl, base, BHIE_RXVECSIZE_OFFS, mhi_buf->len);

	sequence_id = prandom_u32() & BHIE_RXVECSTATUS_SEQNUM_BMSK;
	mhi_write_reg_field(mhi_cntrl, base, BHIE_RXVECDB_OFFS,
			    BHIE_RXVECDB_SEQNUM_BMSK, BHIE_RXVECDB_SEQNUM_SHFT,
			    sequence_id);
	read_unlock_bh(pm_lock);

	MHI_LOG("Upper:0x%x Lower:0x%x len:0x%zx sequence:%u\n",
		upper_32_bits(mhi_buf->dma_addr),
		lower_32_bits(mhi_buf->dma_addr),
		mhi_buf->len, sequence_id);
	MHI_LOG("Waiting for image download completion\n");

	/* waiting for image download completion */
	wait_event_timeout(mhi_cntrl->state_event,
			   MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||
			   mhi_read_reg_field(mhi_cntrl, base,
					      BHIE_RXVECSTATUS_OFFS,
					      BHIE_RXVECSTATUS_STATUS_BMSK,
					      BHIE_RXVECSTATUS_STATUS_SHFT,
					      &rx_status) || rx_status,
			   msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		return -EIO;

	return (rx_status == BHIE_RXVECSTATUS_STATUS_XFER_COMPL) ? 0 : -EIO;
}
EXPORT_SYMBOL(mhi_download_rddm_img);

static int mhi_fw_load_amss(struct mhi_controller *mhi_cntrl,
			    const struct mhi_buf *mhi_buf)
{
	void __iomem *base = mhi_cntrl->bhi;
	rwlock_t *pm_lock = &mhi_cntrl->pm_lock;
	u32 tx_status;

	read_lock_bh(pm_lock);
	if (!MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state)) {
		read_unlock_bh(pm_lock);
		return -EIO;
	}

	MHI_LOG("Starting BHIe Programming\n");

	mhi_write_reg(mhi_cntrl, base, BHIE_TXVECADDR_HIGH_OFFS,
		      upper_32_bits(mhi_buf->dma_addr));

	mhi_write_reg(mhi_cntrl, base, BHIE_TXVECADDR_LOW_OFFS,
		      lower_32_bits(mhi_buf->dma_addr));

	mhi_write_reg(mhi_cntrl, base, BHIE_TXVECSIZE_OFFS, mhi_buf->len);

	mhi_cntrl->sequence_id = prandom_u32() & BHIE_TXVECSTATUS_SEQNUM_BMSK;
	mhi_write_reg_field(mhi_cntrl, base, BHIE_TXVECDB_OFFS,
			    BHIE_TXVECDB_SEQNUM_BMSK, BHIE_TXVECDB_SEQNUM_SHFT,
			    mhi_cntrl->sequence_id);
	read_unlock_bh(pm_lock);

	MHI_LOG("Upper:0x%x Lower:0x%x len:0x%zx sequence:%u\n",
		upper_32_bits(mhi_buf->dma_addr),
		lower_32_bits(mhi_buf->dma_addr),
		mhi_buf->len, mhi_cntrl->sequence_id);
	MHI_LOG("Waiting for image transfer completion\n");

	/* waiting for image download completion */
	wait_event_timeout(mhi_cntrl->state_event,
			   MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||
			   mhi_read_reg_field(mhi_cntrl, base,
					      BHIE_TXVECSTATUS_OFFS,
					      BHIE_TXVECSTATUS_STATUS_BMSK,
					      BHIE_TXVECSTATUS_STATUS_SHFT,
					      &tx_status) || tx_status,
			   msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		return -EIO;

	return (tx_status == BHIE_TXVECSTATUS_STATUS_XFER_COMPL) ? 0 : -EIO;
}

static int mhi_fw_load_sbl(struct mhi_controller *mhi_cntrl,
			   void *buf,
			   size_t size)
{
	u32 tx_status, val;
	int i, ret;
	void __iomem *base = mhi_cntrl->bhi;
	rwlock_t *pm_lock = &mhi_cntrl->pm_lock;
	dma_addr_t phys = dma_map_single(mhi_cntrl->dev, buf, size,
					 DMA_TO_DEVICE);
	struct {
		char *name;
		u32 offset;
	} error_reg[] = {
		{ "ERROR_CODE", BHI_ERRCODE },
		{ "ERROR_DBG1", BHI_ERRDBG1 },
		{ "ERROR_DBG2", BHI_ERRDBG2 },
		{ "ERROR_DBG3", BHI_ERRDBG3 },
		{ NULL },
	};

	if (dma_mapping_error(mhi_cntrl->dev, phys))
		return -ENOMEM;

	MHI_LOG("Starting BHI programming\n");

	/* program start sbl download via  bhi protocol */
	read_lock_bh(pm_lock);
	if (!MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state)) {
		read_unlock_bh(pm_lock);
		goto invalid_pm_state;
	}

	mhi_write_reg(mhi_cntrl, base, BHI_STATUS, 0);
	mhi_write_reg(mhi_cntrl, base, BHI_IMGADDR_HIGH, upper_32_bits(phys));
	mhi_write_reg(mhi_cntrl, base, BHI_IMGADDR_LOW, lower_32_bits(phys));
	mhi_write_reg(mhi_cntrl, base, BHI_IMGSIZE, size);
	mhi_cntrl->session_id = prandom_u32() & BHI_TXDB_SEQNUM_BMSK;
	mhi_write_reg(mhi_cntrl, base, BHI_IMGTXDB, mhi_cntrl->session_id);
	read_unlock_bh(pm_lock);

	MHI_LOG("Waiting for image transfer completion\n");

	/* waiting for image download completion */
	wait_event_timeout(mhi_cntrl->state_event,
			   /*MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||*/
			   mhi_read_reg_field(mhi_cntrl, base, BHI_STATUS,
					      BHI_STATUS_MASK, BHI_STATUS_SHIFT,
					      &tx_status) || tx_status,
			   msecs_to_jiffies(mhi_cntrl->timeout_ms));
	
	#if 0
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		goto invalid_pm_state;
	#endif

	MHI_LOG("image transfer status:%d\n", tx_status);

	if (tx_status == BHI_STATUS_ERROR) {
		MHI_ERR("Image transfer failed\n");
		read_lock_bh(pm_lock);
		if (MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state)) {
			for (i = 0; error_reg[i].name; i++) {
				ret = mhi_read_reg(mhi_cntrl, base,
						   error_reg[i].offset, &val);
				if (ret)
					break;
				MHI_ERR("reg:%s value:0x%x\n",
					error_reg[i].name, val);
			}
		}
		read_unlock_bh(pm_lock);
		goto invalid_pm_state;
	}

	dma_unmap_single(mhi_cntrl->dev, phys, size, DMA_TO_DEVICE);

	return (tx_status == BHI_STATUS_SUCCESS) ? 0 : -ETIMEDOUT;

invalid_pm_state:
	dma_unmap_single(mhi_cntrl->dev, phys, size, DMA_TO_DEVICE);

	return -EIO;
}

void mhi_free_bhie_table(struct mhi_controller *mhi_cntrl,
			 struct image_info *image_info)
{
	int i;
	struct mhi_buf *mhi_buf = image_info->mhi_buf;

	for (i = 0; i < image_info->entries; i++, mhi_buf++)
		mhi_free_coherent(mhi_cntrl, mhi_buf->len, mhi_buf->buf,
				  mhi_buf->dma_addr);

	kfree(image_info->mhi_buf);
	kfree(image_info);
}

int mhi_alloc_bhie_table(struct mhi_controller *mhi_cntrl,
			 struct image_info **image_info,
			 size_t alloc_size)
{
	size_t seg_size = mhi_cntrl->seg_len;
	/* requier additional entry for vec table */
	int segments = DIV_ROUND_UP(alloc_size, seg_size) + 1;
	int i;
	struct image_info *img_info;
	struct mhi_buf *mhi_buf;

	MHI_LOG("Allocating bytes:%zu seg_size:%zu total_seg:%u\n",
		alloc_size, seg_size, segments);

	img_info = kzalloc(sizeof(*img_info), GFP_KERNEL);
	if (!img_info)
		return -ENOMEM;

	/* allocate memory for entries */
	img_info->mhi_buf = kcalloc(segments, sizeof(*img_info->mhi_buf),
				    GFP_KERNEL);
	if (!img_info->mhi_buf)
		goto error_alloc_mhi_buf;

	/* allocate and populate vector table */
	mhi_buf = img_info->mhi_buf;
	for (i = 0; i < segments; i++, mhi_buf++) {
		size_t vec_size = seg_size;

		/* last entry is for vector table */
		if (i == segments - 1)
			vec_size = sizeof(struct __packed bhi_vec_entry) * i;

		mhi_buf->len = vec_size;
		mhi_buf->buf = mhi_alloc_coherent(mhi_cntrl, vec_size,
					&mhi_buf->dma_addr, GFP_KERNEL);
		if (!mhi_buf->buf)
			goto error_alloc_segment;

		MHI_LOG("Entry:%d Address:0x%llx size:%zd\n", i,
			(u64)mhi_buf->dma_addr, mhi_buf->len);
	}

	img_info->bhi_vec = img_info->mhi_buf[segments - 1].buf;
	img_info->entries = segments;
	*image_info = img_info;

	MHI_LOG("Successfully allocated bhi vec table\n");

	return 0;

error_alloc_segment:
	for (--i, --mhi_buf; i >= 0; i--, mhi_buf--)
		mhi_free_coherent(mhi_cntrl, mhi_buf->len, mhi_buf->buf,
				  mhi_buf->dma_addr);

error_alloc_mhi_buf:
	kfree(img_info);

	return -ENOMEM;
}

static void mhi_firmware_copy(struct mhi_controller *mhi_cntrl,
			      const struct firmware *firmware,
			      struct image_info *img_info)
{
	size_t remainder = firmware->size;
	size_t to_cpy;
	const u8 *buf = firmware->data;
	int i = 0;
	struct mhi_buf *mhi_buf = img_info->mhi_buf;
	struct bhi_vec_entry *bhi_vec = img_info->bhi_vec;

	while (remainder) {
		MHI_ASSERT(i >= img_info->entries, "malformed vector table");

		to_cpy = min(remainder, mhi_buf->len);
		memcpy(mhi_buf->buf, buf, to_cpy);
		bhi_vec->dma_addr = mhi_buf->dma_addr;
		bhi_vec->size = to_cpy;

		MHI_VERB("Setting Vector:0x%llx size: %llu\n",
			 bhi_vec->dma_addr, bhi_vec->size);
		buf += to_cpy;
		remainder -= to_cpy;
		i++;
		bhi_vec++;
		mhi_buf++;
	}
}

void mhi_fw_load_worker(struct work_struct *work)
{
	int ret;
	struct mhi_controller *mhi_cntrl;
	const char *fw_name;
	const struct firmware *firmware;
	struct image_info *image_info;
	void *buf;
	size_t size;

	mhi_cntrl = container_of(work, struct mhi_controller, fw_worker);

	MHI_LOG("Waiting for device to enter PBL from EE:%s\n",
		TO_MHI_EXEC_STR(mhi_cntrl->ee));

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 MHI_IN_PBL(mhi_cntrl->ee) ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("MHI is not in valid state\n");
		return;
	}

	MHI_LOG("Device current EE:%s\n", TO_MHI_EXEC_STR(mhi_cntrl->ee));

	/* if device in pthru, we do not have to load firmware */
	if (mhi_cntrl->ee == MHI_EE_PT)
		return;

	fw_name = (mhi_cntrl->ee == MHI_EE_EDL) ?
		mhi_cntrl->edl_image : mhi_cntrl->fw_image;

	if (!fw_name || (mhi_cntrl->fbc_download && (!mhi_cntrl->sbl_size ||
						     !mhi_cntrl->seg_len))) {
		MHI_ERR("No firmware image defined or !sbl_size || !seg_len\n");
		return;
	}

	ret = request_firmware(&firmware, fw_name, mhi_cntrl->dev);
	if (ret) {
		MHI_ERR("Error loading firmware, ret:%d\n", ret);
		return;
	}

	size = (mhi_cntrl->fbc_download) ? mhi_cntrl->sbl_size : firmware->size;

	/* the sbl size provided is maximum size, not necessarily image size */
	if (size > firmware->size)
		size = firmware->size;

	buf = kmalloc(size, GFP_KERNEL);
	if (!buf) {
		MHI_ERR("Could not allocate memory for image\n");
		release_firmware(firmware);
		return;
	}

	/* load sbl image */
	memcpy(buf, firmware->data, size);
	ret = mhi_fw_load_sbl(mhi_cntrl, buf, size);
	kfree(buf);

	if (!mhi_cntrl->fbc_download || ret || mhi_cntrl->ee == MHI_EE_EDL)
		release_firmware(firmware);

	/* error or in edl, we're done */
	if (ret || mhi_cntrl->ee == MHI_EE_EDL)
		return;

	write_lock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->dev_state = MHI_STATE_RESET;
	write_unlock_irq(&mhi_cntrl->pm_lock);

	/*
	 * if we're doing fbc, populate vector tables while
	 * device transitioning into MHI READY state
	 */
	if (mhi_cntrl->fbc_download) {
		ret = mhi_alloc_bhie_table(mhi_cntrl, &mhi_cntrl->fbc_image,
					   firmware->size);
		if (ret) {
			MHI_ERR("Error alloc size of %zu\n", firmware->size);
			goto error_alloc_fw_table;
		}

		MHI_LOG("Copying firmware image into vector table\n");

		/* load the firmware into BHIE vec table */
		mhi_firmware_copy(mhi_cntrl, firmware, mhi_cntrl->fbc_image);
	}

	/* transitioning into MHI RESET->READY state */
	ret = mhi_ready_state_transition(mhi_cntrl);

	MHI_LOG("To Reset->Ready PM_STATE:%s MHI_STATE:%s EE:%s, ret:%d\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		TO_MHI_EXEC_STR(mhi_cntrl->ee), ret);

	if (!mhi_cntrl->fbc_download)
		return;

	if (ret) {
		MHI_ERR("Did not transition to READY state\n");
		goto error_read;
	}

	/* wait for BHIE event */
	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->ee == MHI_EE_BHIE ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("MHI did not enter BHIE\n");
		goto error_read;
	}

	/* start full firmware image download */
	image_info = mhi_cntrl->fbc_image;
	ret = mhi_fw_load_amss(mhi_cntrl,
			       /* last entry is vec table */
			       &image_info->mhi_buf[image_info->entries - 1]);

	MHI_LOG("amss fw_load, ret:%d\n", ret);

	release_firmware(firmware);

	return;

error_read:
	mhi_free_bhie_table(mhi_cntrl, mhi_cntrl->fbc_image);
	mhi_cntrl->fbc_image = NULL;

error_alloc_fw_table:
	release_firmware(firmware);
}

int BhiWrite(struct mhi_controller *mhi_cntrl, void *buf, size_t size)
{
	int ret;
		
	MHI_LOG("Device current EE:%s,%d M:%s\n",
		TO_MHI_EXEC_STR(mhi_get_exec_env(mhi_cntrl)),
		mhi_cntrl->ee,
		TO_MHI_STATE_STR(mhi_get_m_state(mhi_cntrl)));

	mhi_cntrl->ee = mhi_get_exec_env(mhi_cntrl);
	
	if (!MHI_IN_PBL(mhi_cntrl->ee)/* || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)*/) {
		MHI_ERR("MHI is not in valid BHI state:%d\n", mhi_cntrl->ee);
		return -EINVAL;
	}

	if (mhi_cntrl->ee != MHI_EE_EDL)
		return 0;

	ret = mhi_fw_load_sbl(mhi_cntrl, buf, size);

	if (ret) {
		MHI_ERR("ret = %d, ee=%d\n", ret, mhi_cntrl->ee);
		goto error_state;
	}

	write_lock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->dev_state = MHI_STATE_RESET;
	write_unlock_irq(&mhi_cntrl->pm_lock);

	/* transitioning into MHI RESET->READY state */
	ret = mhi_ready_state_transition(mhi_cntrl);
	if (ret) {
		MHI_ERR("Did not transition to READY state\n");
		goto error_state;
	}
	
	MHI_LOG("To Reset->Ready PM_STATE:%s MHI_STATE:%s EE:%s, ret:%d\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		TO_MHI_EXEC_STR(mhi_cntrl->ee), ret);

	/* wait for BHIE event */
	ret = wait_event_timeout(mhi_cntrl->state_event,
			 mhi_cntrl->ee == MHI_EE_FP ||
			 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
			 msecs_to_jiffies(mhi_cntrl->timeout_ms));
	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("MHI did not enter Flash Programmer Environment\n");
		goto error_state;
	}

	MHI_LOG("MHI enter Flash Programmer Environment\n");
	return 0;

error_state:
	MHI_LOG("Device current EE:%s, M:%s\n",
		TO_MHI_EXEC_STR(mhi_get_exec_env(mhi_cntrl)),
		TO_MHI_STATE_STR(mhi_get_m_state(mhi_cntrl)));

	return ret;
}

static int mhi_cntrl_open(struct inode *inode, struct file *f)
{
	return 0;
}

static int mhi_cntrl_release(struct inode *inode, struct file *f)
{
	return 0;
}

static long mhi_cntrl_ioctl(struct file *f, unsigned int cmd, unsigned long __arg)
{
	long ret = -EINVAL;
	void *ubuf = (void *)__arg;
	struct miscdevice *c = (struct miscdevice *)f->private_data;
	struct mhi_controller *mhi_cntrl = container_of(c, struct mhi_controller, miscdev);

	switch (cmd) {
		case IOCTL_BHI_GETDEVINFO:
		{
			BHI_INFO_TYPE bhi_info;
			ret = BhiRead(mhi_cntrl, &bhi_info);
			if (ret) {
				MHI_ERR("IOCTL_BHI_GETDEVINFO BhiRead error, ret = %ld\n", ret);
				return ret;
			}
			
			ret = copy_to_user(ubuf, &bhi_info, sizeof(bhi_info));
			if (ret) {
				MHI_ERR("IOCTL_BHI_GETDEVINFO copy error, ret = %ld\n", ret);
			}
		}			
		break;

		case IOCTL_BHI_WRITEIMAGE:
		{
			void *buf;
			size_t size;

			ret = copy_from_user(&size, ubuf, sizeof(size));
			if (ret) {
				MHI_ERR("IOCTL_BHI_WRITEIMAGE copy size error, ret = %ld\n", ret);
				return ret;
			}

			buf = kmalloc(size, GFP_KERNEL);
			if (buf == NULL) {
				return -ENOMEM;
			}

			ret = copy_from_user(buf, ubuf+sizeof(size), size);
			if (ret) {
				MHI_ERR("IOCTL_BHI_WRITEIMAGE copy buf error, ret = %ld\n", ret);
				kfree(buf);
				return ret;
			}
			
			ret = BhiWrite(mhi_cntrl, buf, size);
			if (ret) {
				MHI_ERR("IOCTL_BHI_WRITEIMAGE BhiWrite error, ret = %ld\n", ret);
			}
			kfree(buf);
		}
		break;

		default:
		break;
	}

	return ret;
}

static const struct file_operations mhi_cntrl_fops = {
	.unlocked_ioctl =	mhi_cntrl_ioctl,
	.open =			mhi_cntrl_open,
	.release =		mhi_cntrl_release,
};

int mhi_cntrl_register_miscdev(struct mhi_controller *mhi_cntrl)
{
	mhi_cntrl->miscdev.minor = MISC_DYNAMIC_MINOR;
	mhi_cntrl->miscdev.name = "mhi_BHI";
	mhi_cntrl->miscdev.fops = &mhi_cntrl_fops;

	return misc_register(&mhi_cntrl->miscdev);
}

void mhi_cntrl_deregister_miscdev(struct mhi_controller *mhi_cntrl)
{
	misc_deregister(&mhi_cntrl->miscdev);
}
