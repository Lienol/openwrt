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

#include <linux/kernel.h>
#include <linux/debugfs.h>
#include <linux/device.h>
#include <linux/dma-direction.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/list.h>
#include <linux/of.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/wait.h>
#include "mhi.h"
#include "mhi_internal.h"

const char * const mhi_ee_str[MHI_EE_MAX] = {
	[MHI_EE_PBL] = "PBL",
	[MHI_EE_SBL] = "SBL",
	[MHI_EE_AMSS] = "AMSS",
	[MHI_EE_RDDM] = "RDDM",
	[MHI_EE_WFW] = "WFW",
	[MHI_EE_PT] = "PASS THRU",
	[MHI_EE_EDL] = "EDL",
	[MHI_EE_FP] = "FlashProg",
	[MHI_EE_UEFI] = "UEFI",
	[MHI_EE_DISABLE_TRANSITION] = "RESET",
};

const char * const mhi_state_tran_str[MHI_ST_TRANSITION_MAX] = {
	[MHI_ST_TRANSITION_PBL] = "PBL",
	[MHI_ST_TRANSITION_READY] = "READY",
	[MHI_ST_TRANSITION_SBL] = "SBL",
	[MHI_ST_TRANSITION_AMSS] = "AMSS",
	[MHI_ST_TRANSITION_FP] = "FlashProg",
	[MHI_ST_TRANSITION_BHIE] = "BHIE",
};

const char * const mhi_state_str[MHI_STATE_MAX] = {
	[MHI_STATE_RESET] = "RESET",
	[MHI_STATE_READY] = "READY",
	[MHI_STATE_M0] = "M0",
	[MHI_STATE_M1] = "M1",
	[MHI_STATE_M2] = "M2",
	[MHI_STATE_M3] = "M3",
	[MHI_STATE_D3] = "D3",
	[MHI_STATE_BHI] = "BHI",
	[MHI_STATE_SYS_ERR] = "SYS_ERR",
};

static const char * const mhi_pm_state_str[] = {
	"DISABLE",
	"POR",
	"M0",
	"M1",
	"M1->M2",
	"M2",
	"M?->M3",
	"M3",
	"M3->M0",
	"FW DL Error",
	"SYS_ERR Detect",
	"SYS_ERR Process",
	"SHUTDOWN Process",
	"LD or Error Fatal Detect",
};

struct mhi_bus mhi_bus;

const char *to_mhi_pm_state_str(enum MHI_PM_STATE state)
{
	int index = find_last_bit((unsigned long *)&state, 32);

	if (index >= ARRAY_SIZE(mhi_pm_state_str))
		return "Invalid State";

	return mhi_pm_state_str[index];
}

static void mhi_ring_aligned_check(struct mhi_controller *mhi_cntrl, u64 rbase, u64 rlen) {
	uint64_t ra;

	ra = rbase;
	do_div(ra, roundup_pow_of_two(rlen));

	if (rbase != ra * roundup_pow_of_two(rlen)) {
		MHI_ERR("bad params ring base not aligned 0x%llx align 0x%lx\n", rbase, roundup_pow_of_two(rlen));
	}
}

void mhi_deinit_free_irq(struct mhi_controller *mhi_cntrl)
{
	int i;
	struct mhi_event *mhi_event = mhi_cntrl->mhi_event;
	MHI_LOG("enter\n");

	if (mhi_cntrl->msi_allocated == 1) {
		free_irq(mhi_cntrl->irq[0], mhi_event);
		return;
	}

	
	free_irq(mhi_cntrl->irq[0], mhi_cntrl);

	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		if (mhi_event->offload_ev)
			continue;

		free_irq(mhi_cntrl->irq[mhi_event->msi], mhi_event);
	}
}

int mhi_init_irq_setup(struct mhi_controller *mhi_cntrl)
{
	int i;
	int ret;
	struct mhi_event *mhi_event = mhi_cntrl->mhi_event;

	if (mhi_cntrl->msi_allocated == 1) {
		for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
			mhi_event->msi = 0;
		}

		ret = request_irq(mhi_cntrl->irq[0],
				  mhi_msi_handlr, IRQF_SHARED, "mhi", mhi_cntrl->mhi_event);
		if (ret) {
			MHI_ERR("Error requesting irq:%d, ret=%d\n", mhi_cntrl->irq[0], ret);
		}
		return ret;
	}

	/* for BHI INTVEC msi */
	ret = request_threaded_irq(mhi_cntrl->irq[0], mhi_intvec_handlr,
				   mhi_intvec_threaded_handlr, IRQF_ONESHOT,
				   "mhi", mhi_cntrl);
	if (ret)
		return ret;

	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		if (mhi_event->offload_ev)
			continue;

		ret = request_irq(mhi_cntrl->irq[mhi_event->msi],
				  mhi_msi_handlr, IRQF_SHARED, "mhi",
				  mhi_event);
		if (ret) {
			MHI_ERR("Error requesting irq:%d for ev:%d\n",
				mhi_cntrl->irq[mhi_event->msi], i);
			goto error_request;
		}
	}

	return 0;

error_request:
	for (--i, --mhi_event; i >= 0; i--, mhi_event--) {
		if (mhi_event->offload_ev)
			continue;

		free_irq(mhi_cntrl->irq[mhi_event->msi], mhi_event);
	}
	free_irq(mhi_cntrl->irq[0], mhi_cntrl);

	return ret;
}

void mhi_deinit_dev_ctxt(struct mhi_controller *mhi_cntrl)
{
	int i;
	struct mhi_ctxt *mhi_ctxt = mhi_cntrl->mhi_ctxt;
	struct mhi_cmd *mhi_cmd;
	struct mhi_event *mhi_event;
	struct mhi_ring *ring;
	MHI_LOG("enter\n");

	mhi_cmd = mhi_cntrl->mhi_cmd;
	for (i = 0; i < NR_OF_CMD_RINGS; i++, mhi_cmd++) {
		ring = &mhi_cmd->ring;
        
		ring->base = NULL;
		ring->iommu_base = 0;
	}

	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		if (mhi_event->offload_ev)
			continue;

		ring = &mhi_event->ring;

		ring->base = NULL;
		ring->iommu_base = 0;
	}

	mhi_free_coherent(mhi_cntrl, sizeof(*mhi_ctxt->ctrl_seg), mhi_ctxt->ctrl_seg, mhi_ctxt->ctrl_seg_addr);

	mhi_cntrl->mhi_ctxt = NULL;
}

static int mhi_init_debugfs_mhi_states_open(struct inode *inode,
					    struct file *fp)
{
	return single_open(fp, mhi_debugfs_mhi_states_show, inode->i_private);
}

static int mhi_init_debugfs_mhi_event_open(struct inode *inode, struct file *fp)
{
	return single_open(fp, mhi_debugfs_mhi_event_show, inode->i_private);
}

static int mhi_init_debugfs_mhi_chan_open(struct inode *inode, struct file *fp)
{
	return single_open(fp, mhi_debugfs_mhi_chan_show, inode->i_private);
}

static const struct file_operations debugfs_state_ops = {
	.open = mhi_init_debugfs_mhi_states_open,
	.release = single_release,
	.read = seq_read,
};

static const struct file_operations debugfs_ev_ops = {
	.open = mhi_init_debugfs_mhi_event_open,
	.release = single_release,
	.read = seq_read,
};

static const struct file_operations debugfs_chan_ops = {
	.open = mhi_init_debugfs_mhi_chan_open,
	.release = single_release,
	.read = seq_read,
};

DEFINE_SIMPLE_ATTRIBUTE(debugfs_trigger_reset_fops, NULL,
			mhi_debugfs_trigger_reset, "%llu\n");

void mhi_init_debugfs(struct mhi_controller *mhi_cntrl)
{
	struct dentry *dentry;
	char node[32];

	if (!mhi_cntrl->parent)
		return;

	snprintf(node, sizeof(node), "%04x_%02u:%02u.%02u",
		 mhi_cntrl->dev_id, mhi_cntrl->domain, mhi_cntrl->bus,
		 mhi_cntrl->slot);

	dentry = debugfs_create_dir(node, mhi_cntrl->parent);
	if (IS_ERR_OR_NULL(dentry))
		return;

	debugfs_create_file("states", 0444, dentry, mhi_cntrl,
			    &debugfs_state_ops);
	debugfs_create_file("events", 0444, dentry, mhi_cntrl,
			    &debugfs_ev_ops);
	debugfs_create_file("chan", 0444, dentry, mhi_cntrl, &debugfs_chan_ops);
	debugfs_create_file("reset", 0444, dentry, mhi_cntrl,
			    &debugfs_trigger_reset_fops);
	mhi_cntrl->dentry = dentry;
}

void mhi_deinit_debugfs(struct mhi_controller *mhi_cntrl)
{
	debugfs_remove_recursive(mhi_cntrl->dentry);
	mhi_cntrl->dentry = NULL;
}

int mhi_init_dev_ctxt(struct mhi_controller *mhi_cntrl)
{
	struct mhi_ctxt *mhi_ctxt;
	struct mhi_chan_ctxt *chan_ctxt;
	struct mhi_event_ctxt *er_ctxt;
	struct mhi_cmd_ctxt *cmd_ctxt;
	struct mhi_chan *mhi_chan;
	struct mhi_event *mhi_event;
	struct mhi_cmd *mhi_cmd;
	int ret = -ENOMEM, i;

	atomic_set(&mhi_cntrl->dev_wake, 0);
	atomic_set(&mhi_cntrl->alloc_size, 0);

	mhi_ctxt = &mhi_cntrl->data->mhi_ctxt;

	/* setup channel ctxt */
	mhi_ctxt->ctrl_seg = mhi_alloc_coherent(mhi_cntrl, sizeof(*mhi_ctxt->ctrl_seg),
			&mhi_ctxt->ctrl_seg_addr, GFP_KERNEL);
	if (!mhi_ctxt->ctrl_seg)
		goto error_alloc_chan_ctxt;

	MHI_LOG("mhi_ctxt->ctrl_seg = %p\n", mhi_ctxt->ctrl_seg);
	if ((unsigned long)mhi_ctxt->ctrl_seg & (4096-1)) {
		mhi_free_coherent(mhi_cntrl, sizeof(*mhi_ctxt->ctrl_seg), mhi_ctxt->ctrl_seg, mhi_ctxt->ctrl_seg_addr);
		goto error_alloc_chan_ctxt;
	}

/*
+Transfer rings
+--------------
+MHI channels are logical, unidirectional data pipes between host and device.
+Each channel associated with a single transfer ring.  The data direction can be
+either inbound (device to host) or outbound (host to device).  Transfer
+descriptors are managed by using transfer rings, which are defined for each
+channel between device and host and resides in the host memory.
+
+Transfer ring Pointer:	  	Transfer Ring Array
+[Read Pointer (RP)] ----------->[Ring Element] } TD
+[Write Pointer (WP)]-		[Ring Element]
+                     -		[Ring Element]
+		      --------->[Ring Element]
+				[Ring Element]
+
+1. Host allocate memory for transfer ring
+2. Host sets base, read pointer, write pointer in corresponding channel context
+3. Ring is considered empty when RP == WP
+4. Ring is considered full when WP + 1 == RP
+4. RP indicates the next element to be serviced by device
+4. When host new buffer to send, host update the Ring element with buffer information
+5. Host increment the WP to next element
+6. Ring the associated channel DB.
*/

	mhi_ctxt->chan_ctxt = mhi_ctxt->ctrl_seg->chan_ctxt;
	mhi_ctxt->chan_ctxt_addr = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, chan_ctxt);

	mhi_chan = mhi_cntrl->data->mhi_chan;
	chan_ctxt = mhi_ctxt->chan_ctxt;
	for (i = 0; i < mhi_cntrl->max_chan; i++, chan_ctxt++, mhi_chan++) {
		/* If it's offload channel skip this step */
		if (mhi_chan->offload_ch)
			continue;

		chan_ctxt->chstate = MHI_CH_STATE_DISABLED;
		chan_ctxt->brstmode = mhi_chan->db_cfg.brstmode;
		chan_ctxt->pollcfg = mhi_chan->db_cfg.pollcfg;
		chan_ctxt->chtype = cpu_to_le32(mhi_chan->dir);
		chan_ctxt->erindex = cpu_to_le32(mhi_chan->er_index);

		mhi_chan->ch_state = MHI_CH_STATE_DISABLED;
		mhi_chan->tre_ring.db_addr = &chan_ctxt->wp;
	}

/*
+Event rings
+-----------
+Events from the device to host are organized in event rings and defined in event
+descriptors.  Event rings are array of EDs that resides in the host memory.
+
+Transfer ring Pointer:	  	Event Ring Array
+[Read Pointer (RP)] ----------->[Ring Element] } ED
+[Write Pointer (WP)]-		[Ring Element]
+                     -		[Ring Element]
+		      --------->[Ring Element]
+				[Ring Element]
+
+1. Host allocate memory for event ring
+2. Host sets base, read pointer, write pointer in corresponding channel context
+3. Both host and device has local copy of RP, WP
+3. Ring is considered empty (no events to service) when WP + 1 == RP
+4. Ring is full of events when RP == WP
+4. RP - 1 = last event device programmed
+4. When there is a new event device need to send, device update ED pointed by RP
+5. Device increment RP to next element
+6. Device trigger and interrupt
+
+Example Operation for data transfer:
+
+1. Host prepare TD with buffer information
+2. Host increment Chan[id].ctxt.WP
+3. Host ring channel DB register
+4. Device wakes up process the TD
+5. Device generate a completion event for that TD by updating ED
+6. Device increment Event[id].ctxt.RP
+7. Device trigger MSI to wake host
+8. Host wakes up and check event ring for completion event
+9. Host update the Event[i].ctxt.WP to indicate processed of completion event.
*/
	mhi_ctxt->er_ctxt = mhi_ctxt->ctrl_seg->er_ctxt;
	mhi_ctxt->er_ctxt_addr = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, er_ctxt);

	er_ctxt = mhi_ctxt->er_ctxt;
	mhi_event = mhi_cntrl->data->mhi_event;
	for (i = 0; i < NUM_MHI_EVT_RINGS; i++, er_ctxt++, mhi_event++) {
		struct mhi_ring *ring = &mhi_event->ring;

		/* it's a satellite ev, we do not touch it */
		if (mhi_event->offload_ev)
			continue;

		er_ctxt->intmodc = 0;
		er_ctxt->intmodt = cpu_to_le16(mhi_event->intmod);
		er_ctxt->ertype = cpu_to_le32(MHI_ER_TYPE_VALID);
		if (mhi_cntrl->msi_allocated == 1) {
			mhi_event->msi = 0;
		}
		er_ctxt->msivec = cpu_to_le32(mhi_event->msi);
		mhi_event->db_cfg.db_mode = true;

		ring->el_size = sizeof(struct __packed mhi_tre);
		ring->len = ring->el_size * ring->elements;

		ring->alloc_size = ring->len;
		

              if (i == 0)
              {
                  ring->pre_aligned = mhi_ctxt->ctrl_seg->event_ring_0;
		    ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, event_ring_0);
              }
              else if (i == 1)
              {
                  ring->pre_aligned = mhi_ctxt->ctrl_seg->event_ring_1;
		    ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, event_ring_1);
              }
              else if (i == 2)
              {
                  ring->pre_aligned = mhi_ctxt->ctrl_seg->event_ring_2;
		    ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, event_ring_2);
              }
              
		ring->iommu_base = ring->dma_handle;
		ring->base = ring->pre_aligned + (ring->iommu_base - ring->dma_handle);

		ring->rp = ring->wp = ring->base;
		er_ctxt->rbase = cpu_to_le64(ring->iommu_base);
		er_ctxt->rp = er_ctxt->wp = er_ctxt->rbase;
		er_ctxt->rlen = cpu_to_le64(ring->len);
		ring->ctxt_wp = &er_ctxt->wp;

		mhi_ring_aligned_check(mhi_cntrl, er_ctxt->rbase, er_ctxt->rlen);
		memset(ring->base, 0xCC, ring->len);
	}

	mhi_ctxt->cmd_ctxt = mhi_ctxt->ctrl_seg->cmd_ctxt;
	mhi_ctxt->cmd_ctxt_addr = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, cmd_ctxt);

	mhi_cmd = mhi_cntrl->data->mhi_cmd;
	cmd_ctxt = mhi_ctxt->cmd_ctxt;
	for (i = 0; i < NR_OF_CMD_RINGS; i++, mhi_cmd++, cmd_ctxt++) {
		struct mhi_ring *ring = &mhi_cmd->ring;

		ring->el_size = sizeof(struct __packed mhi_tre);
		ring->elements = CMD_EL_PER_RING;
		ring->len = ring->el_size * ring->elements;

		ring->alloc_size = ring->len;
		ring->pre_aligned = mhi_ctxt->ctrl_seg->cmd_ring[i];
		ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, cmd_ring[i]);
		ring->iommu_base = ring->dma_handle;
		ring->base = ring->pre_aligned + (ring->iommu_base - ring->dma_handle);

		ring->rp = ring->wp = ring->base;
		cmd_ctxt->rbase = cpu_to_le64(ring->iommu_base);
		cmd_ctxt->rp = cmd_ctxt->wp = cmd_ctxt->rbase;
		cmd_ctxt->rlen = cpu_to_le64(ring->len);
		ring->ctxt_wp = &cmd_ctxt->wp;

		mhi_ring_aligned_check(mhi_cntrl, cmd_ctxt->rbase, cmd_ctxt->rlen);
	}

	mhi_cntrl->mhi_ctxt = mhi_ctxt;

	return 0;

error_alloc_chan_ctxt:

	return ret;
}

int mhi_init_mmio(struct mhi_controller *mhi_cntrl)
{
	u32 val;
	int i, ret;
	struct mhi_chan *mhi_chan;
	struct mhi_event *mhi_event;
	void __iomem *base = mhi_cntrl->regs;
	struct {
		u32 offset;
		u32 mask;
		u32 shift;
		u32 val;
	} reg_info[] = {
		{
			CCABAP_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->mhi_ctxt->chan_ctxt_addr),
		},
		{
			CCABAP_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->mhi_ctxt->chan_ctxt_addr),
		},
		{
			ECABAP_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->mhi_ctxt->er_ctxt_addr),
		},
		{
			ECABAP_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->mhi_ctxt->er_ctxt_addr),
		},
		{
			CRCBAP_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->mhi_ctxt->cmd_ctxt_addr),
		},
		{
			CRCBAP_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->mhi_ctxt->cmd_ctxt_addr),
		},

		{
			MHICTRLBASE_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->iova_start),
		},
		{
			MHICTRLBASE_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->iova_start),
		},
		{
			MHIDATABASE_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->iova_start),
		},
		{
			MHIDATABASE_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->iova_start),
		},
		{
			MHICTRLLIMIT_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->iova_stop),
		},
		{
			MHICTRLLIMIT_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->iova_stop),
		},
		{
			MHIDATALIMIT_HIGHER, U32_MAX, 0,
			upper_32_bits(mhi_cntrl->iova_stop),
		},
		{
			MHIDATALIMIT_LOWER, U32_MAX, 0,
			lower_32_bits(mhi_cntrl->iova_stop),
		},
		{ 0, 0, 0 }
	};

	MHI_LOG("Initializing MMIO\n");

	MHI_LOG("iova_start = %llx, iova_stop = %llx\n", (u64)mhi_cntrl->iova_start, (u64)mhi_cntrl->iova_stop);
	MHI_LOG("cmd_ctxt_addr = %llx\n", (u64)mhi_cntrl->mhi_ctxt->cmd_ctxt_addr);
	MHI_LOG("chan_ctxt_addr = %llx\n", (u64)mhi_cntrl->mhi_ctxt->chan_ctxt_addr);
	MHI_LOG("er_ctxt_addr = %llx\n", (u64)mhi_cntrl->mhi_ctxt->er_ctxt_addr);

	/* set up DB register for all the chan rings */
	ret = mhi_read_reg_field(mhi_cntrl, base, CHDBOFF, CHDBOFF_CHDBOFF_MASK,
				 CHDBOFF_CHDBOFF_SHIFT, &val);
	if (ret)
		return -EIO;

	MHI_LOG("CHDBOFF:0x%x\n", val);

	/* setup wake db */
	mhi_cntrl->wake_db = base + val + (8 * MHI_DEV_WAKE_DB);
	mhi_write_reg(mhi_cntrl, mhi_cntrl->wake_db, 4, 0);
	mhi_write_reg(mhi_cntrl, mhi_cntrl->wake_db, 0, 0);
	mhi_cntrl->wake_set = false;

	/* setup channel db addresses */
	mhi_chan = mhi_cntrl->mhi_chan;
	for (i = 0; i < mhi_cntrl->max_chan; i++, val += 8, mhi_chan++)
		mhi_chan->tre_ring.db_addr = base + val;

	/* setup event ring db addresses */
	ret = mhi_read_reg_field(mhi_cntrl, base, ERDBOFF, ERDBOFF_ERDBOFF_MASK,
				 ERDBOFF_ERDBOFF_SHIFT, &val);
	if (ret)
		return -EIO;

	MHI_LOG("ERDBOFF:0x%x\n", val);

	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, val += 8, mhi_event++) {
		if (mhi_event->offload_ev)
			continue;

		mhi_event->ring.db_addr = base + val;
	}

	/* set up DB register for primary CMD rings */
	mhi_cntrl->mhi_cmd[PRIMARY_CMD_RING].ring.db_addr = base + CRDB_LOWER;

	MHI_LOG("Programming all MMIO values.\n");
	for (i = 0; reg_info[i].offset; i++)
		mhi_write_reg_field(mhi_cntrl, base, reg_info[i].offset,
				    reg_info[i].mask, reg_info[i].shift,
				    reg_info[i].val);

	return 0;
}

void mhi_deinit_chan_ctxt(struct mhi_controller *mhi_cntrl,
			  struct mhi_chan *mhi_chan)
{
	struct mhi_ring *buf_ring;
	struct mhi_ring *tre_ring;
	struct mhi_chan_ctxt *chan_ctxt;

	buf_ring = &mhi_chan->buf_ring;
	tre_ring = &mhi_chan->tre_ring;
	chan_ctxt = &mhi_cntrl->mhi_ctxt->chan_ctxt[mhi_chan->chan];

	kfree(buf_ring->base);

	buf_ring->base = tre_ring->base = NULL;
	chan_ctxt->rbase = cpu_to_le64(0);
}

int mhi_init_chan_ctxt(struct mhi_controller *mhi_cntrl,
		       struct mhi_chan *mhi_chan)
{
	struct mhi_ring *buf_ring;
	struct mhi_ring *tre_ring;
	struct mhi_chan_ctxt *chan_ctxt;
	struct mhi_ctxt *mhi_ctxt = mhi_cntrl->mhi_ctxt;

	buf_ring = &mhi_chan->buf_ring;
	tre_ring = &mhi_chan->tre_ring;
	tre_ring->el_size = sizeof(struct __packed mhi_tre);
	tre_ring->len = tre_ring->el_size * tre_ring->elements;
	chan_ctxt = &mhi_ctxt->chan_ctxt[mhi_chan->chan];

	tre_ring->alloc_size = tre_ring->len;
	if (MHI_CLIENT_IP_HW_0_IN == mhi_chan->chan) {
		tre_ring->pre_aligned = &mhi_ctxt->ctrl_seg->hw_in_chan_ring[mhi_chan->ring];
		tre_ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, hw_in_chan_ring[mhi_chan->ring]);
	}
	else if (MHI_CLIENT_IP_HW_0_OUT == mhi_chan->chan) {
		tre_ring->pre_aligned = &mhi_ctxt->ctrl_seg->hw_out_chan_ring[mhi_chan->ring];
		tre_ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, hw_out_chan_ring[mhi_chan->ring]);
	}
	else if (MHI_CLIENT_DIAG_IN == mhi_chan->chan) {
		tre_ring->pre_aligned = &mhi_ctxt->ctrl_seg->diag_in_chan_ring[mhi_chan->ring];
		tre_ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, diag_in_chan_ring[mhi_chan->ring]);
	}
	else {
		tre_ring->pre_aligned = &mhi_ctxt->ctrl_seg->chan_ring[mhi_chan->ring];
		tre_ring->dma_handle = mhi_ctxt->ctrl_seg_addr + offsetof(struct mhi_ctrl_seg, chan_ring[mhi_chan->ring]);
	}
	tre_ring->iommu_base = tre_ring->dma_handle;
	tre_ring->base = tre_ring->pre_aligned + (tre_ring->iommu_base - tre_ring->dma_handle);

	buf_ring->el_size = sizeof(struct mhi_buf_info);
	buf_ring->len = buf_ring->el_size * buf_ring->elements;
	buf_ring->base = kzalloc(buf_ring->len, GFP_KERNEL);
	MHI_LOG("%d size = %zd\n", __LINE__, buf_ring->len);

	if (!buf_ring->base) {
		return -ENOMEM;
	}

	chan_ctxt->chstate = MHI_CH_STATE_ENABLED;
	chan_ctxt->rbase = cpu_to_le64(tre_ring->iommu_base);
	chan_ctxt->rp = chan_ctxt->wp = chan_ctxt->rbase;
	chan_ctxt->rlen = cpu_to_le64(tre_ring->len);
	tre_ring->ctxt_wp = &chan_ctxt->wp;

	tre_ring->rp = tre_ring->wp = tre_ring->base;
	buf_ring->rp = buf_ring->wp = buf_ring->base;
	mhi_chan->db_cfg.db_mode = 1;

	mhi_ring_aligned_check(mhi_cntrl, chan_ctxt->rbase, chan_ctxt->rlen);
	/* update to all cores */
	smp_wmb();

	return 0;
}

int mhi_device_configure(struct mhi_device *mhi_dev,
			 enum dma_data_direction dir,
			 struct mhi_buf *cfg_tbl,
			 int elements)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_chan *mhi_chan;
	struct mhi_event_ctxt *er_ctxt;
	struct mhi_chan_ctxt *ch_ctxt;
	int er_index, chan;

	mhi_chan = (dir == DMA_TO_DEVICE) ? mhi_dev->ul_chan : mhi_dev->dl_chan;
	er_index = mhi_chan->er_index;
	chan = mhi_chan->chan;

	for (; elements > 0; elements--, cfg_tbl++) {
		/* update event context array */
		if (!strcmp(cfg_tbl->name, "ECA")) {
			er_ctxt = &mhi_cntrl->mhi_ctxt->er_ctxt[er_index];
			if (sizeof(*er_ctxt) != cfg_tbl->len) {
				MHI_ERR(
					"Invalid ECA size, expected:%zu actual%zu\n",
					sizeof(*er_ctxt), cfg_tbl->len);
				return -EINVAL;
			}
			memcpy((void *)er_ctxt, cfg_tbl->buf, sizeof(*er_ctxt));
			continue;
		}

		/* update channel context array */
		if (!strcmp(cfg_tbl->name, "CCA")) {
			ch_ctxt = &mhi_cntrl->mhi_ctxt->chan_ctxt[chan];
			if (cfg_tbl->len != sizeof(*ch_ctxt)) {
				MHI_ERR(
					"Invalid CCA size, expected:%zu actual:%zu\n",
					sizeof(*ch_ctxt), cfg_tbl->len);
				return -EINVAL;
			}
			memcpy((void *)ch_ctxt, cfg_tbl->buf, sizeof(*ch_ctxt));
			continue;
		}

		return -EINVAL;
	}

	return 0;
}

static int of_parse_ev_cfg(struct mhi_controller *mhi_cntrl,
			   struct device_node *of_node)
{
	int num, i;
	struct mhi_event *mhi_event;
	u32 bit_cfg;

	num = NUM_MHI_EVT_RINGS;

	mhi_cntrl->total_ev_rings = num;
	mhi_cntrl->mhi_event = mhi_cntrl->data->mhi_event;

	/* populate ev ring */
	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		mhi_event->er_index = i;
		mhi_event->ring.elements = NUM_MHI_EVT_RING_ELEMENTS; //Event ring length in elements
		mhi_event->intmod = 1; //Interrupt moderation time in ms
		mhi_event->priority = MHI_ER_PRIORITY_MEDIUM; //Event ring priority, set to 1 for now

		mhi_event->msi = 1 + i;  //MSI associated with this event ring
		if (i == IPA_OUT_EVENT_RING)
		{
			mhi_event->chan = MHI_CLIENT_IP_HW_0_OUT; //Dedicated channel number, if it's a dedicated event ring
		       mhi_event->ring.elements = NUM_MHI_IPA_OUT_EVT_RING_ELEMENTS;
                     mhi_event->priority = MHI_ER_PRIORITY_HIGH;
		}
		else if (i == IPA_IN_EVENT_RING)
		{
			mhi_event->chan = MHI_CLIENT_IP_HW_0_IN; //Dedicated channel number, if it's a dedicated event ring
			mhi_event->ring.elements = NUM_MHI_IPA_IN_EVT_RING_ELEMENTS;
                     mhi_event->priority = MHI_ER_PRIORITY_HIGH;
		}
		else
			mhi_event->chan = 0;

		if (mhi_event->chan >= mhi_cntrl->max_chan)
			goto error_ev_cfg;

		/* this event ring has a dedicated channel */
		if (mhi_event->chan)
			mhi_event->mhi_chan = &mhi_cntrl->mhi_chan[mhi_event->chan];

		//mhi_event->priority = 1; //Event ring priority, set to 1 for now
		mhi_event->db_cfg.brstmode = MHI_BRSTMODE_DISABLE;

		if (mhi_event->chan == MHI_CLIENT_IP_HW_0_OUT || mhi_event->chan == MHI_CLIENT_IP_HW_0_IN)
			mhi_event->db_cfg.brstmode = MHI_BRSTMODE_ENABLE;

		if (MHI_INVALID_BRSTMODE(mhi_event->db_cfg.brstmode))
			goto error_ev_cfg;

		mhi_event->db_cfg.process_db =
			(mhi_event->db_cfg.brstmode == MHI_BRSTMODE_ENABLE) ?
			mhi_db_brstmode : mhi_db_brstmode_disable;

		bit_cfg = (MHI_EV_CFG_BIT_CTRL_EV & 0);
		if (bit_cfg & MHI_EV_CFG_BIT_HW_EV) {
			mhi_event->hw_ring = true;
			mhi_cntrl->hw_ev_rings++;
		} else
			mhi_cntrl->sw_ev_rings++;

		mhi_event->cl_manage = !!(bit_cfg & MHI_EV_CFG_BIT_CL_MANAGE);
		mhi_event->offload_ev = !!(bit_cfg & MHI_EV_CFG_BIT_OFFLOAD_EV);
		mhi_event->ctrl_ev = !!(bit_cfg & MHI_EV_CFG_BIT_CTRL_EV);
	}

	/* we need msi for each event ring + additional one for BHI */
	mhi_cntrl->msi_required = mhi_cntrl->total_ev_rings + 1;

	return 0;

 error_ev_cfg:
	return -EINVAL;
}
static int of_parse_ch_cfg(struct mhi_controller *mhi_cntrl,
			   struct device_node *of_node)
{
	u32 num, i;
	u32 ring = 0;

	struct chan_cfg_t {
		const char *chan_name;
		u32 chan_id;
		u32 elements;
	};

	static struct chan_cfg_t chan_cfg[] = {
	//"Qualcomm PCIe Loopback"
		{"LOOPBACK", MHI_CLIENT_LOOPBACK_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"LOOPBACK", MHI_CLIENT_LOOPBACK_IN, NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm PCIe Sahara"
		{"SAHARA", MHI_CLIENT_SAHARA_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"SAHARA", MHI_CLIENT_SAHARA_IN, NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm PCIe Diagnostics"
		{"DIAG", MHI_CLIENT_DIAG_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"DIAG", MHI_CLIENT_DIAG_IN, NUM_MHI_DIAG_IN_RING_ELEMENTS},
	//"Qualcomm PCIe QDSS Data"
		{"QDSS", MHI_CLIENT_QDSS_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"QDSS", MHI_CLIENT_QDSS_IN, NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm PCIe EFS"
		{"EFS", MHI_CLIENT_EFS_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"EFS", MHI_CLIENT_EFS_IN, NUM_MHI_CHAN_RING_ELEMENTS},
#ifdef CONFIG_MHI_NETDEV_MBIM
	//"Qualcomm PCIe MBIM"
		{"MBIM", MHI_CLIENT_MBIM_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"MBIM", MHI_CLIENT_MBIM_IN, NUM_MHI_CHAN_RING_ELEMENTS},
#else
	//"Qualcomm PCIe QMI"
		{"QMI0", MHI_CLIENT_QMI_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"QMI0", MHI_CLIENT_QMI_IN, NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm PCIe QMI"
		//{"QMI1", MHI_CLIENT_QMI_2_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		//{"QMI1", MHI_CLIENT_QMI_2_IN, NUM_MHI_CHAN_RING_ELEMENTS},
#endif
	//"Qualcomm PCIe IP CTRL"
		{"IP_CTRL", MHI_CLIENT_IP_CTRL_1_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"IP_CTRL", MHI_CLIENT_IP_CTRL_1_IN, NUM_MHI_CHAN_RING_ELEMENTS},

	//"Qualcomm PCIe Boot Logging"
		//{"BL", MHI_CLIENT_BOOT_LOG_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		//{"BL", MHI_CLIENT_BOOT_LOG_IN, NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm PCIe Modem"
		{"DUN", MHI_CLIENT_DUN_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"DUN", MHI_CLIENT_DUN_IN, NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm EDL "
		{"EDL", MHI_CLIENT_EDL_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
		{"EDL", MHI_CLIENT_EDL_IN, NUM_MHI_CHAN_RING_ELEMENTS},

        {"GNSS", MHI_CLIENT_GNSS_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
        {"GNSS", MHI_CLIENT_GNSS_IN,  NUM_MHI_CHAN_RING_ELEMENTS},

        {"AUDIO", MHI_CLIENT_AUDIO_OUT, NUM_MHI_CHAN_RING_ELEMENTS},
        {"AUDIO", MHI_CLIENT_AUDIO_IN,  NUM_MHI_CHAN_RING_ELEMENTS},
	//"Qualcomm PCIe WWAN Adapter"
		{"IP_HW0", MHI_CLIENT_IP_HW_0_OUT, NUM_MHI_IPA_OUT_RING_ELEMENTS},
		{"IP_HW0", MHI_CLIENT_IP_HW_0_IN, NUM_MHI_IPA_IN_RING_ELEMENTS},
	};

	mhi_cntrl->max_chan = MHI_MAX_CHANNELS;
	num = sizeof(chan_cfg)/sizeof(chan_cfg[0]);

	mhi_cntrl->mhi_chan = mhi_cntrl->data->mhi_chan,
	INIT_LIST_HEAD(&mhi_cntrl->lpm_chans);

	/* populate channel configurations */
	for (i = 0; i < num; i++) {
		struct mhi_chan *mhi_chan;
		u32 chan_id = chan_cfg[i].chan_id;
		u32 bit_cfg = 0;
		u32 pollcfg = 0;
		enum MHI_BRSTMODE brstmode = MHI_BRSTMODE_DISABLE;

		if (chan_id >= mhi_cntrl->max_chan)
			goto error_chan_cfg;

		mhi_chan = &mhi_cntrl->mhi_chan[chan_id];
		mhi_chan->chan = chan_id;
		mhi_chan->buf_ring.elements = chan_cfg[i].elements;
		if (MHI_HW_CHAN(mhi_chan->chan) || mhi_chan->chan == MHI_CLIENT_DIAG_IN) {
			mhi_chan->ring = 0;
		}
		else {
			mhi_chan->ring = ring;
			ring += mhi_chan->buf_ring.elements;
		}
		mhi_chan->tre_ring.elements = mhi_chan->buf_ring.elements;
		if (chan_id == MHI_CLIENT_IP_HW_0_OUT)
			mhi_chan->er_index = IPA_OUT_EVENT_RING;
		else if (chan_id == MHI_CLIENT_IP_HW_0_IN)
			mhi_chan->er_index = IPA_IN_EVENT_RING;
		else
			mhi_chan->er_index = PRIMARY_EVENT_RING;
		mhi_chan->dir = (chan_cfg[i].chan_id&1) ? INBOUND_CHAN : OUTBOUND_CHAN;

		mhi_chan->db_cfg.pollcfg = pollcfg;
		mhi_chan->ee = MHI_EE_AMSS;
		if (CHAN_SBL(chan_cfg[i].chan_id))
			mhi_chan->ee = MHI_EE_SBL;
		else if (CHAN_EDL(chan_cfg[i].chan_id))
			mhi_chan->ee = MHI_EE_FP;
			
		mhi_chan->xfer_type = MHI_XFER_BUFFER;
		if ((chan_cfg[i].chan_id == MHI_CLIENT_IP_HW_0_OUT || chan_cfg[i].chan_id == MHI_CLIENT_IP_HW_0_IN)
			|| (chan_cfg[i].chan_id == MHI_CLIENT_IP_SW_0_OUT || chan_cfg[i].chan_id == MHI_CLIENT_IP_SW_0_IN))
			mhi_chan->xfer_type = MHI_XFER_SKB;

		switch (mhi_chan->xfer_type) {
		case MHI_XFER_BUFFER:
			mhi_chan->gen_tre = mhi_gen_tre;
			mhi_chan->queue_xfer = mhi_queue_buf;
			break;
		case MHI_XFER_SKB:
			mhi_chan->queue_xfer = mhi_queue_skb;
			break;
		case MHI_XFER_SCLIST:
			mhi_chan->gen_tre = mhi_gen_tre;
			mhi_chan->queue_xfer = mhi_queue_sclist;
			break;
		case MHI_XFER_NOP:
			mhi_chan->queue_xfer = mhi_queue_nop;
			break;
		default:
			goto error_chan_cfg;
		}

		mhi_chan->lpm_notify = !!(bit_cfg & MHI_CH_CFG_BIT_LPM_NOTIFY);
		mhi_chan->offload_ch = !!(bit_cfg & MHI_CH_CFG_BIT_OFFLOAD_CH);
		mhi_chan->db_cfg.reset_req =
			!!(bit_cfg & MHI_CH_CFG_BIT_DBMODE_RESET_CH);
		mhi_chan->pre_alloc = !!(bit_cfg & MHI_CH_CFG_BIT_PRE_ALLOC);

		if (mhi_chan->pre_alloc &&
		    (mhi_chan->dir != DMA_FROM_DEVICE ||
		     mhi_chan->xfer_type != MHI_XFER_BUFFER))
			goto error_chan_cfg;

		/* if mhi host allocate the buffers then client cannot queue */
		if (mhi_chan->pre_alloc)
			mhi_chan->queue_xfer = mhi_queue_nop;

		mhi_chan->name = chan_cfg[i].chan_name;

		if (!mhi_chan->offload_ch) {
			if (mhi_chan->chan == MHI_CLIENT_IP_HW_0_OUT || mhi_chan->chan == MHI_CLIENT_IP_HW_0_IN)
				brstmode = MHI_BRSTMODE_ENABLE;

			mhi_chan->db_cfg.brstmode = brstmode;
			if (MHI_INVALID_BRSTMODE(mhi_chan->db_cfg.brstmode))
				goto error_chan_cfg;

			mhi_chan->db_cfg.process_db =
				(mhi_chan->db_cfg.brstmode ==
				 MHI_BRSTMODE_ENABLE) ?
				mhi_db_brstmode : mhi_db_brstmode_disable;
		}
		mhi_chan->configured = true;

		if (mhi_chan->lpm_notify)
			list_add_tail(&mhi_chan->node, &mhi_cntrl->lpm_chans);
	}

	MHI_LOG("chan ring need %d, chan ring size %zd\n",
		ring, sizeof(mhi_cntrl->data->mhi_ctxt.ctrl_seg->chan_ring)/sizeof(struct __packed mhi_tre));

	if (ring > sizeof(mhi_cntrl->data->mhi_ctxt.ctrl_seg->chan_ring)/sizeof(struct __packed mhi_tre))
		return -ENOMEM;

	return 0;

error_chan_cfg:
	return -EINVAL;
}

static int of_parse_dt(struct mhi_controller *mhi_cntrl, struct device_node *of_node)
{
	int ret;

	mhi_cntrl->fw_image = NULL;
	mhi_cntrl->edl_image = NULL;
	mhi_cntrl->fbc_download = 0;
	mhi_cntrl->sbl_size = 0;
	mhi_cntrl->seg_len = 0;

	/* parse MHI channel configuration */
	ret = of_parse_ch_cfg(mhi_cntrl, of_node);
	if (ret) {
		MHI_ERR("Error of_parse_ch_cfg ret:%d\n", ret);
		return ret;
	}

	/* parse MHI event configuration */
	ret = of_parse_ev_cfg(mhi_cntrl, of_node);
	if (ret) {
		MHI_ERR("Error of_parse_ch_cfg ret:%d\n", ret);
		goto error_ev_cfg;
	}

	mhi_cntrl->timeout_ms = MHI_TIMEOUT_MS;

	return 0;

 error_ev_cfg:
	return ret;
}

int mhi_register_mhi_controller(struct mhi_controller *mhi_cntrl)
{
	int ret;
	int i;
	struct mhi_event *mhi_event;
	struct mhi_chan *mhi_chan;
	struct mhi_cmd *mhi_cmd;

	mhi_cntrl->klog_lvl = MHI_MSG_LVL_ERROR;

	if (!mhi_cntrl->runtime_get || !mhi_cntrl->runtime_put)
		return -EINVAL;

	if (!mhi_cntrl->status_cb || !mhi_cntrl->link_status)
		return -EINVAL;

	ret = of_parse_dt(mhi_cntrl, NULL);
	if (ret) {
		MHI_ERR("Error of_parse_dt ret:%d\n", ret);
		return -EINVAL;
	}

	mhi_cntrl->mhi_cmd = &mhi_cntrl->data->mhi_cmd[0];

	INIT_LIST_HEAD(&mhi_cntrl->transition_list);
	mutex_init(&mhi_cntrl->pm_mutex);
	rwlock_init(&mhi_cntrl->pm_lock);
	spin_lock_init(&mhi_cntrl->transition_lock);
	spin_lock_init(&mhi_cntrl->wlock);
	INIT_WORK(&mhi_cntrl->st_worker, mhi_pm_st_worker);
	INIT_WORK(&mhi_cntrl->fw_worker, mhi_fw_load_worker);
	INIT_WORK(&mhi_cntrl->m1_worker, mhi_pm_m1_worker);
	INIT_WORK(&mhi_cntrl->syserr_worker, mhi_pm_sys_err_worker);
	init_waitqueue_head(&mhi_cntrl->state_event);

	mhi_cmd = mhi_cntrl->mhi_cmd;
	for (i = 0; i < NR_OF_CMD_RINGS; i++, mhi_cmd++)
		spin_lock_init(&mhi_cmd->lock);

	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		if (mhi_event->offload_ev)
			continue;

		mhi_event->mhi_cntrl = mhi_cntrl;
		spin_lock_init(&mhi_event->lock);
		if (mhi_event->ctrl_ev)
			tasklet_init(&mhi_event->task, mhi_ctrl_ev_task,
				     (ulong)mhi_event);
		else
			tasklet_init(&mhi_event->task, mhi_ev_task,
				     (ulong)mhi_event);
	}

	mhi_chan = mhi_cntrl->mhi_chan;
	for (i = 0; i < mhi_cntrl->max_chan; i++, mhi_chan++) {
		mutex_init(&mhi_chan->mutex);
		init_completion(&mhi_chan->completion);
		rwlock_init(&mhi_chan->lock);
	}

	mhi_cntrl->parent = mhi_bus.dentry;

	/* add to list */
	mutex_lock(&mhi_bus.lock);
	list_add_tail(&mhi_cntrl->node, &mhi_bus.controller_list);
	mutex_unlock(&mhi_bus.lock);

	return 0;

//error_alloc_cmd:

	return -ENOMEM;
};

void mhi_unregister_mhi_controller(struct mhi_controller *mhi_cntrl)
{
	mutex_lock(&mhi_bus.lock);
	list_del(&mhi_cntrl->node);
	mutex_unlock(&mhi_bus.lock);
}

/* set ptr to control private data */
static inline void mhi_controller_set_devdata(struct mhi_controller *mhi_cntrl,
					 void *priv)
{
	mhi_cntrl->priv_data = priv;
}


/* allocate mhi controller to register */
struct mhi_controller *mhi_alloc_controller(size_t size)
{
	struct mhi_controller *mhi_cntrl;

	mhi_cntrl = kzalloc(size + sizeof(*mhi_cntrl) + sizeof(struct mhi_cntrl_data), GFP_KERNEL);
	MHI_LOG("%d size = %zd\n", __LINE__, size + sizeof(*mhi_cntrl));

	if (mhi_cntrl && size)
		mhi_controller_set_devdata(mhi_cntrl, mhi_cntrl + 1);

	mhi_cntrl->data = (struct mhi_cntrl_data *)(((char *)mhi_cntrl) + (size + sizeof(*mhi_cntrl)));

	return mhi_cntrl;
}
EXPORT_SYMBOL(mhi_alloc_controller);

int mhi_prepare_for_power_up(struct mhi_controller *mhi_cntrl)
{
	int ret;

	mutex_lock(&mhi_cntrl->pm_mutex);

	ret = mhi_init_dev_ctxt(mhi_cntrl);
	if (ret) {
		MHI_ERR("Error with init dev_ctxt\n");
		goto error_dev_ctxt;
	}

	ret = mhi_init_irq_setup(mhi_cntrl);
	if (ret) {
		MHI_ERR("Error setting up irq\n");
		goto error_setup_irq;
	}

	/*
	 * allocate rddm table if specified, this table is for debug purpose
	 * so we'll ignore erros
	 */
	if (mhi_cntrl->rddm_size)
		mhi_alloc_bhie_table(mhi_cntrl, &mhi_cntrl->rddm_image,
				     mhi_cntrl->rddm_size);

	mhi_cntrl->pre_init = true;

	mutex_unlock(&mhi_cntrl->pm_mutex);

	return 0;

error_setup_irq:
	mhi_deinit_dev_ctxt(mhi_cntrl);

error_dev_ctxt:
	mutex_unlock(&mhi_cntrl->pm_mutex);

	return ret;
}
EXPORT_SYMBOL(mhi_prepare_for_power_up);

void mhi_unprepare_after_power_down(struct mhi_controller *mhi_cntrl)
{
	if (mhi_cntrl->fbc_image) {
		mhi_free_bhie_table(mhi_cntrl, mhi_cntrl->fbc_image);
		mhi_cntrl->fbc_image = NULL;
	}

	if (mhi_cntrl->rddm_image) {
		mhi_free_bhie_table(mhi_cntrl, mhi_cntrl->rddm_image);
		mhi_cntrl->rddm_image = NULL;
	}

	mhi_deinit_free_irq(mhi_cntrl);
	mhi_deinit_dev_ctxt(mhi_cntrl);
	mhi_cntrl->pre_init = false;
}

/* match dev to drv */
static int mhi_match(struct device *dev, struct device_driver *drv)
{
	struct mhi_device *mhi_dev = to_mhi_device(dev);
	struct mhi_driver *mhi_drv = to_mhi_driver(drv);
	const struct mhi_device_id *id;

	for (id = mhi_drv->id_table; id->chan != NULL && id->chan[0] != '\0'; id++) {
		if (!strcmp(mhi_dev->chan_name, id->chan)) {
			mhi_dev->id = id;
			return 1;
		}
	}

	return 0;
};

static void mhi_release_device(struct device *dev)
{
	struct mhi_device *mhi_dev = to_mhi_device(dev);

	kfree(mhi_dev);
}

struct bus_type mhi_bus_type = {
	.name = "mhi",
	.dev_name = "mhi",
	.match = mhi_match,
};

static int mhi_driver_probe(struct device *dev)
{
	struct mhi_device *mhi_dev = to_mhi_device(dev);
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct device_driver *drv = dev->driver;
	struct mhi_driver *mhi_drv = to_mhi_driver(drv);
	struct mhi_event *mhi_event;
	struct mhi_chan *ul_chan = mhi_dev->ul_chan;
	struct mhi_chan *dl_chan = mhi_dev->dl_chan;
	bool offload_ch = ((ul_chan && ul_chan->offload_ch) ||
			   (dl_chan && dl_chan->offload_ch));

	MHI_LOG("%s dev->name = %s\n", __func__, dev_name(dev));

	/* all offload channels require status_cb to be defined */
	if (offload_ch) {
		if (!mhi_dev->status_cb)
			return -EINVAL;
		mhi_dev->status_cb = mhi_drv->status_cb;
	}

	if (ul_chan && !offload_ch) {
		if (!mhi_drv->ul_xfer_cb)
			return -EINVAL;
		ul_chan->xfer_cb = mhi_drv->ul_xfer_cb;
	}

	if (dl_chan && !offload_ch) {
		if (!mhi_drv->dl_xfer_cb)
			return -EINVAL;
		dl_chan->xfer_cb = mhi_drv->dl_xfer_cb;
		mhi_event = &mhi_cntrl->mhi_event[dl_chan->er_index];

		/*
		 * if this channal event ring manage by client, then
		 * status_cb must be defined so we can send the async
		 * cb whenever there are pending data
		 */
		if (mhi_event->cl_manage && !mhi_drv->status_cb)
			return -EINVAL;
		mhi_dev->status_cb = mhi_drv->status_cb;
	}

	return mhi_drv->probe(mhi_dev, mhi_dev->id);
}

static int mhi_driver_remove(struct device *dev)
{
	struct mhi_device *mhi_dev = to_mhi_device(dev);
	struct mhi_driver *mhi_drv = to_mhi_driver(dev->driver);
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_chan *mhi_chan;
	enum MHI_CH_STATE ch_state[] = {
		MHI_CH_STATE_DISABLED,
		MHI_CH_STATE_DISABLED
	};
	int dir;

	MHI_LOG("Removing device for chan:%s\n", mhi_dev->chan_name);

	/* reset both channels */
	for (dir = 0; dir < 2; dir++) {
		mhi_chan = dir ? mhi_dev->ul_chan : mhi_dev->dl_chan;

		if (!mhi_chan)
			continue;

		/* wake all threads waiting for completion */
		write_lock_irq(&mhi_chan->lock);
		mhi_chan->ccs = MHI_EV_CC_INVALID;
		complete_all(&mhi_chan->completion);
		write_unlock_irq(&mhi_chan->lock);

		/* move channel state to disable, no more processing */
		mutex_lock(&mhi_chan->mutex);
		write_lock_irq(&mhi_chan->lock);
		ch_state[dir] = mhi_chan->ch_state;
		mhi_chan->ch_state = MHI_CH_STATE_DISABLED;
		write_unlock_irq(&mhi_chan->lock);

		/* reset the channel */
		if (!mhi_chan->offload_ch)
			mhi_reset_chan(mhi_cntrl, mhi_chan);
	}

	/* destroy the device */
	mhi_drv->remove(mhi_dev);

	/* de_init channel if it was enabled */
	for (dir = 0; dir < 2; dir++) {
		mhi_chan = dir ? mhi_dev->ul_chan : mhi_dev->dl_chan;

		if (!mhi_chan)
			continue;

		if (ch_state[dir] == MHI_CH_STATE_ENABLED &&
		    !mhi_chan->offload_ch)
			mhi_deinit_chan_ctxt(mhi_cntrl, mhi_chan);

		mutex_unlock(&mhi_chan->mutex);
	}

	/* relinquish any pending votes */
	read_lock_bh(&mhi_cntrl->pm_lock);
	while (atomic_read(&mhi_dev->dev_wake))
		mhi_device_put(mhi_dev);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	return 0;
}

int mhi_driver_register(struct mhi_driver *mhi_drv)
{
	struct device_driver *driver = &mhi_drv->driver;

	if (!mhi_drv->probe || !mhi_drv->remove)
		return -EINVAL;

	driver->bus = &mhi_bus_type;
	driver->probe = mhi_driver_probe;
	driver->remove = mhi_driver_remove;
	return driver_register(driver);
}
EXPORT_SYMBOL(mhi_driver_register);

void mhi_driver_unregister(struct mhi_driver *mhi_drv)
{
	driver_unregister(&mhi_drv->driver);
}
EXPORT_SYMBOL(mhi_driver_unregister);

struct mhi_device *mhi_alloc_device(struct mhi_controller *mhi_cntrl)
{
	struct mhi_device *mhi_dev = kzalloc(sizeof(*mhi_dev), GFP_KERNEL);
	struct device *dev;
	//MHI_LOG("%d size = %zd\n", __LINE__, sizeof(*mhi_dev));

	if (!mhi_dev)
		return NULL;

	dev = &mhi_dev->dev;
	device_initialize(dev);
	dev->bus = &mhi_bus_type;
	dev->release = mhi_release_device;
	dev->parent = mhi_cntrl->dev;
	mhi_dev->mhi_cntrl = mhi_cntrl;
	mhi_dev->dev_id = mhi_cntrl->dev_id;
	mhi_dev->domain = mhi_cntrl->domain;
	mhi_dev->bus = mhi_cntrl->bus;
	mhi_dev->slot = mhi_cntrl->slot;
	mhi_dev->mtu = MHI_MAX_MTU;
	atomic_set(&mhi_dev->dev_wake, 0);

	return mhi_dev;
}

extern int mhi_dtr_init(void);
extern void mhi_dtr_exit(void);
extern int mhi_device_netdev_init(struct dentry *parent);
extern void mhi_device_netdev_exit(void);
extern int mhi_device_uci_init(void);
extern void mhi_device_uci_exit(void);
extern int mhi_controller_qcom_init(void);
extern void mhi_controller_qcom_exit(void);

static char mhi_version[] = "Fibocom_Linux_PCIE_MHI_Driver_V1.0.5";
module_param_string(mhi_version, mhi_version, sizeof(mhi_version), S_IRUGO);

static int __init mhi_init(void)
{
	int ret;
	struct dentry *dentry;

	pr_err("INFO:%s %s\n", __func__, mhi_version);

	mutex_init(&mhi_bus.lock);
	INIT_LIST_HEAD(&mhi_bus.controller_list);
	dentry = debugfs_create_dir("mhi", NULL);
	if (!IS_ERR_OR_NULL(dentry))
		mhi_bus.dentry = dentry;

	ret = bus_register(&mhi_bus_type);
	if (ret) {
		pr_err("Error bus_register ret:%d\n", ret);
		return ret;
	}

	ret = mhi_dtr_init();
	if (ret) {
		pr_err("Error mhi_dtr_init ret:%d\n", ret);
		bus_unregister(&mhi_bus_type);
		return ret;
	}

	ret = mhi_device_netdev_init(dentry);
	if (ret) {
		pr_err("Error mhi_device_netdev_init ret:%d\n", ret);
	}

	ret = mhi_device_uci_init();
	if (ret) {
		pr_err("Error mhi_device_uci_init ret:%d\n", ret);
	}

	ret = mhi_controller_qcom_init();
	if (ret) {
		pr_err("Error mhi_controller_qcom_init ret:%d\n", ret);
	}

	return ret;
}

static void mhi_exit(void)
{
	mhi_controller_qcom_exit();
	mhi_device_uci_exit();
	mhi_device_netdev_exit();
	mhi_dtr_exit();
	bus_unregister(&mhi_bus_type);
	debugfs_remove_recursive(mhi_bus.dentry);
}

module_init(mhi_init);
module_exit(mhi_exit);

MODULE_LICENSE("GPL v2");
MODULE_ALIAS("MHI_CORE");
MODULE_DESCRIPTION("MHI Host Interface");
