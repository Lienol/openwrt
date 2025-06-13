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
#include <linux/device.h>
#include <linux/dma-direction.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/list.h>
#include <linux/of.h>
#include <linux/module.h>
#include <linux/skbuff.h>
#include <linux/slab.h>
#include <linux/sched.h>
#include <linux/wait.h>
#include <linux/io.h>
#include "mhi.h"
#include "mhi_internal.h"

static void __mhi_unprepare_channel(struct mhi_controller *mhi_cntrl,
				    struct mhi_chan *mhi_chan);

int __must_check mhi_read_reg(struct mhi_controller *mhi_cntrl,
			      void __iomem *base,
			      u32 offset,
			      u32 *out)
{
	u32 tmp = readl_relaxed(base + offset);

	/* unexpected value, query the link status */
	if (PCI_INVALID_READ(tmp) &&
	    mhi_cntrl->link_status(mhi_cntrl, mhi_cntrl->priv_data))
		return -EIO;

	*out = tmp;

	return 0;
}

int __must_check mhi_read_reg_field(struct mhi_controller *mhi_cntrl,
				    void __iomem *base,
				    u32 offset,
				    u32 mask,
				    u32 shift,
				    u32 *out)
{
	u32 tmp;
	int ret;

	ret = mhi_read_reg(mhi_cntrl, base, offset, &tmp);
	if (ret)
		return ret;

	*out = (tmp & mask) >> shift;

	return 0;
}

void mhi_write_reg(struct mhi_controller *mhi_cntrl,
		   void __iomem *base,
		   u32 offset,
		   u32 val)
{
	writel_relaxed(val, base + offset);
}

void mhi_write_reg_field(struct mhi_controller *mhi_cntrl,
			 void __iomem *base,
			 u32 offset,
			 u32 mask,
			 u32 shift,
			 u32 val)
{
	int ret;
	u32 tmp;

	ret = mhi_read_reg(mhi_cntrl, base, offset, &tmp);
	if (ret)
		return;

	tmp &= ~mask;
	tmp |= (val << shift);
	mhi_write_reg(mhi_cntrl, base, offset, tmp);
}

void mhi_write_db(struct mhi_controller *mhi_cntrl,
		  void __iomem *db_addr,
		  dma_addr_t wp)
{
	mhi_write_reg(mhi_cntrl, db_addr, 4, upper_32_bits(wp));
	mhi_write_reg(mhi_cntrl, db_addr, 0, lower_32_bits(wp));
}

void mhi_db_brstmode(struct mhi_controller *mhi_cntrl,
		     struct db_cfg *db_cfg,
		     void __iomem *db_addr,
		     dma_addr_t wp)
{
	if (db_cfg->db_mode) {
		db_cfg->db_val = wp;
		mhi_write_db(mhi_cntrl, db_addr, wp);
		db_cfg->db_mode = 0;
	}
}

void mhi_db_brstmode_disable(struct mhi_controller *mhi_cntrl,
			     struct db_cfg *db_cfg,
			     void __iomem *db_addr,
			     dma_addr_t wp)
{
	db_cfg->db_val = wp;
	mhi_write_db(mhi_cntrl, db_addr, wp);
}

void mhi_ring_er_db(struct mhi_event *mhi_event)
{
	struct mhi_ring *ring = &mhi_event->ring;

	mhi_event->db_cfg.process_db(mhi_event->mhi_cntrl, &mhi_event->db_cfg,
				     ring->db_addr, le64_to_cpu(*ring->ctxt_wp));
}

void mhi_ring_cmd_db(struct mhi_controller *mhi_cntrl, struct mhi_cmd *mhi_cmd)
{
	dma_addr_t db;
	struct mhi_ring *ring = &mhi_cmd->ring;

	db = ring->iommu_base + (ring->wp - ring->base);
	*ring->ctxt_wp = cpu_to_le64(db);
	mhi_write_db(mhi_cntrl, ring->db_addr, db);
}

void mhi_ring_chan_db(struct mhi_controller *mhi_cntrl,
		      struct mhi_chan *mhi_chan)
{
	struct mhi_ring *ring = &mhi_chan->tre_ring;
	dma_addr_t db;

	db = ring->iommu_base + (ring->wp - ring->base);
	*ring->ctxt_wp = cpu_to_le64(db);
	mhi_chan->db_cfg.process_db(mhi_cntrl, &mhi_chan->db_cfg, ring->db_addr,
				    db);
}

enum MHI_EE mhi_get_exec_env(struct mhi_controller *mhi_cntrl)
{
	u32 exec;
	int ret = mhi_read_reg(mhi_cntrl, mhi_cntrl->bhi, BHI_EXECENV, &exec);

	return (ret) ? MHI_EE_MAX : exec;
}

enum MHI_STATE mhi_get_m_state(struct mhi_controller *mhi_cntrl)
{
	u32 state;
	int ret = mhi_read_reg_field(mhi_cntrl, mhi_cntrl->regs, MHISTATUS,
				     MHISTATUS_MHISTATE_MASK,
				     MHISTATUS_MHISTATE_SHIFT, &state);
	return ret ? MHI_STATE_MAX : state;
}

int mhi_queue_sclist(struct mhi_device *mhi_dev,
		     struct mhi_chan *mhi_chan,
		     void *buf,
		     size_t len,
		     enum MHI_FLAGS mflags)
{
	return -EINVAL;
}

int mhi_queue_nop(struct mhi_device *mhi_dev,
		  struct mhi_chan *mhi_chan,
		  void *buf,
		  size_t len,
		  enum MHI_FLAGS mflags)
{
	return -EINVAL;
}

static void mhi_add_ring_element(struct mhi_controller *mhi_cntrl,
				 struct mhi_ring *ring)
{
	ring->wp += ring->el_size;
	if (ring->wp >= (ring->base + ring->len))
		ring->wp = ring->base;
	/* smp update */
	smp_wmb();
}

static void mhi_del_ring_element(struct mhi_controller *mhi_cntrl,
				 struct mhi_ring *ring)
{
	ring->rp += ring->el_size;
	if (ring->rp >= (ring->base + ring->len))
		ring->rp = ring->base;
	/* smp update */
	smp_wmb();
}

static int get_nr_avail_ring_elements(struct mhi_controller *mhi_cntrl,
				      struct mhi_ring *ring)
{
	int nr_el;

	if (ring->wp < ring->rp)
		nr_el = ((ring->rp - ring->wp) / ring->el_size) - 1;
	else {
		nr_el = (ring->rp - ring->base) / ring->el_size;
		nr_el += ((ring->base + ring->len - ring->wp) /
			  ring->el_size) - 1;
	}
	return nr_el;
}

static void *mhi_to_virtual(struct mhi_ring *ring, dma_addr_t addr)
{
	return (addr - ring->iommu_base) + ring->base;
}

dma_addr_t mhi_to_physical(struct mhi_ring *ring, void *addr)
{
	return (addr - ring->base) + ring->iommu_base;
}

static void mhi_recycle_ev_ring_element(struct mhi_controller *mhi_cntrl,
					struct mhi_ring *ring)
{
	dma_addr_t ctxt_wp;

	/* update the WP */
	ring->wp += ring->el_size;
	ctxt_wp = le64_to_cpu(*ring->ctxt_wp) + ring->el_size;

	if (ring->wp >= (ring->base + ring->len)) {
		ring->wp = ring->base;
		ctxt_wp = ring->iommu_base;
	}

	*ring->ctxt_wp = cpu_to_le64(ctxt_wp);

	/* update the RP */
	//memset((unsigned char *)ring->rp, 0x55, ring->el_size); //carl.yin debug
	ring->rp += ring->el_size;
	if (ring->rp >= (ring->base + ring->len))
		ring->rp = ring->base;

	/* visible to other cores */
	smp_wmb();
}

static bool mhi_is_ring_full(struct mhi_controller *mhi_cntrl,
			     struct mhi_ring *ring)
{
	void *tmp = ring->wp + ring->el_size;

	if (tmp >= (ring->base + ring->len))
		tmp = ring->base;

	return (tmp == ring->rp);
}

int mhi_queue_skb(struct mhi_device *mhi_dev,
		  struct mhi_chan *mhi_chan,
		  void *buf,
		  size_t len,
		  enum MHI_FLAGS mflags)
{
	struct sk_buff *skb = buf;
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_ring *tre_ring = &mhi_chan->tre_ring;
	struct mhi_ring *buf_ring = &mhi_chan->buf_ring;
	struct mhi_buf_info *buf_info;
	struct mhi_tre *mhi_tre;

	if (mhi_is_ring_full(mhi_cntrl, tre_ring))
		return -ENOMEM;

	read_lock_bh(&mhi_cntrl->pm_lock);
	if (unlikely(MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))) {
		MHI_ERR("MHI is not in activate state, pm_state:%s\n",
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		read_unlock_bh(&mhi_cntrl->pm_lock);

		return -EIO;
	}

	/* we're in M3 or transitioning to M3 */
	if (MHI_PM_IN_SUSPEND_STATE(mhi_cntrl->pm_state)) {
		mhi_cntrl->runtime_get(mhi_cntrl, mhi_cntrl->priv_data);
		mhi_cntrl->runtime_put(mhi_cntrl, mhi_cntrl->priv_data);
	}
	mhi_cntrl->wake_get(mhi_cntrl, false);

	/* generate the tre */
	buf_info = buf_ring->wp;
	buf_info->v_addr = skb->data;
	buf_info->cb_buf = skb;
	buf_info->wp = tre_ring->wp;
	buf_info->dir = mhi_chan->dir;
	buf_info->len = len;
	buf_info->p_addr = dma_map_single(mhi_cntrl->dev, buf_info->v_addr, len,
					  buf_info->dir);

	if (dma_mapping_error(mhi_cntrl->dev, buf_info->p_addr))
		goto map_error;

	mhi_tre = tre_ring->wp;
	mhi_tre->ptr = MHI_TRE_DATA_PTR(buf_info->p_addr);
	mhi_tre->dword[0] = MHI_TRE_DATA_DWORD0(buf_info->len);
	mhi_tre->dword[1] = MHI_TRE_DATA_DWORD1(1, 1, 0, 0);

	MHI_VERB("chan:%d WP:0x%llx TRE:0x%llx 0x%08x 0x%08x\n", mhi_chan->chan,
		 (u64)mhi_to_physical(tre_ring, mhi_tre), le64_to_cpu(mhi_tre->ptr),
		 le32_to_cpu(mhi_tre->dword[0]), le32_to_cpu(mhi_tre->dword[1]));

	/* increment WP */
	mhi_add_ring_element(mhi_cntrl, tre_ring);
	mhi_add_ring_element(mhi_cntrl, buf_ring);

	if (likely(MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state))) {
		read_lock_bh(&mhi_chan->lock);
		mhi_ring_chan_db(mhi_cntrl, mhi_chan);
		read_unlock_bh(&mhi_chan->lock);
	}

	if (mhi_chan->dir == DMA_FROM_DEVICE) {
		bool override = (mhi_cntrl->pm_state != MHI_PM_M0);

		mhi_cntrl->wake_put(mhi_cntrl, override);
	}

	read_unlock_bh(&mhi_cntrl->pm_lock);

	return 0;

map_error:
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	return -ENOMEM;
}

int mhi_gen_tre(struct mhi_controller *mhi_cntrl,
		struct mhi_chan *mhi_chan,
		void *buf,
		void *cb,
		size_t buf_len,
		enum MHI_FLAGS flags)
{
	struct mhi_ring *buf_ring, *tre_ring;
	struct mhi_tre *mhi_tre;
	struct mhi_buf_info *buf_info;
	int eot, eob, chain, bei;

	buf_ring = &mhi_chan->buf_ring;
	tre_ring = &mhi_chan->tre_ring;

	buf_info = buf_ring->wp;
	buf_info->v_addr = buf;
	buf_info->cb_buf = cb;
	buf_info->wp = tre_ring->wp;
	buf_info->dir = mhi_chan->dir;
	buf_info->len = buf_len;
	buf_info->p_addr = dma_map_single(mhi_cntrl->dev, buf, buf_len,
					  buf_info->dir);

	if (dma_mapping_error(mhi_cntrl->dev, buf_info->p_addr))
		return -ENOMEM;

	eob = !!(flags & MHI_EOB);
	eot = !!(flags & MHI_EOT);
	chain = !!(flags & MHI_CHAIN);
	bei = !!(mhi_chan->intmod);

	mhi_tre = tre_ring->wp;
	mhi_tre->ptr = MHI_TRE_DATA_PTR(buf_info->p_addr);
	mhi_tre->dword[0] = MHI_TRE_DATA_DWORD0(buf_len);
	mhi_tre->dword[1] = MHI_TRE_DATA_DWORD1(bei, eot, eob, chain);

	MHI_VERB("chan:%d WP:0x%llx TRE:0x%llx 0x%08x 0x%08x\n", mhi_chan->chan,
		 (u64)mhi_to_physical(tre_ring, mhi_tre), le64_to_cpu(mhi_tre->ptr),
		 le32_to_cpu(mhi_tre->dword[0]), le32_to_cpu(mhi_tre->dword[1]));

	/* increment WP */
	mhi_add_ring_element(mhi_cntrl, tre_ring);
	mhi_add_ring_element(mhi_cntrl, buf_ring);

	return 0;
}

int mhi_queue_buf(struct mhi_device *mhi_dev,
		  struct mhi_chan *mhi_chan,
		  void *buf,
		  size_t len,
		  enum MHI_FLAGS mflags)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_ring *tre_ring;
	unsigned long flags;
	int ret;

	read_lock_irqsave(&mhi_cntrl->pm_lock, flags);
	if (unlikely(MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))) {
		MHI_ERR("MHI is not in active state, pm_state:%s\n",
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		read_unlock_irqrestore(&mhi_cntrl->pm_lock, flags);

		return -EIO;
	}

	/* we're in M3 or transitioning to M3 */
	if (MHI_PM_IN_SUSPEND_STATE(mhi_cntrl->pm_state)) {
		mhi_cntrl->runtime_get(mhi_cntrl, mhi_cntrl->priv_data);
		mhi_cntrl->runtime_put(mhi_cntrl, mhi_cntrl->priv_data);
	}

	mhi_cntrl->wake_get(mhi_cntrl, false);
	read_unlock_irqrestore(&mhi_cntrl->pm_lock, flags);

	tre_ring = &mhi_chan->tre_ring;
	if (mhi_is_ring_full(mhi_cntrl, tre_ring))
		goto error_queue;

	ret = mhi_chan->gen_tre(mhi_cntrl, mhi_chan, buf, buf, len, mflags);
	if (unlikely(ret))
		goto error_queue;

	read_lock_irqsave(&mhi_cntrl->pm_lock, flags);
	if (likely(MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state))) {
		unsigned long flags;

		read_lock_irqsave(&mhi_chan->lock, flags);
		mhi_ring_chan_db(mhi_cntrl, mhi_chan);
		read_unlock_irqrestore(&mhi_chan->lock, flags);
	}

	if (mhi_chan->dir == DMA_FROM_DEVICE) {
		bool override = (mhi_cntrl->pm_state != MHI_PM_M0);

		mhi_cntrl->wake_put(mhi_cntrl, override);
	}

	read_unlock_irqrestore(&mhi_cntrl->pm_lock, flags);

	return 0;

error_queue:
	read_lock_irqsave(&mhi_cntrl->pm_lock, flags);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_irqrestore(&mhi_cntrl->pm_lock, flags);

	return -ENOMEM;
}

/* destroy specific device */
int mhi_destroy_device(struct device *dev, void *data)
{
	struct mhi_device *mhi_dev;
	struct mhi_driver *mhi_drv;
	struct mhi_controller *mhi_cntrl;
	struct mhi_chan *mhi_chan;
	int dir;

	if (dev->bus != &mhi_bus_type)
		return 0;

	mhi_dev = to_mhi_device(dev);
	mhi_drv = to_mhi_driver(dev->driver);
	mhi_cntrl = mhi_dev->mhi_cntrl;

	MHI_LOG("destroy device for chan:%s\n", mhi_dev->chan_name);

	for (dir = 0; dir < 2; dir++) {
		mhi_chan = dir ? mhi_dev->ul_chan : mhi_dev->dl_chan;

		if (!mhi_chan)
			continue;

		/* remove device associated with the channel */
		mutex_lock(&mhi_chan->mutex);
		mutex_unlock(&mhi_chan->mutex);
	}

	/* notify the client and remove the device from mhi bus */
	device_del(dev);

	return 0;
}

void mhi_notify(struct mhi_device *mhi_dev, enum MHI_CB cb_reason)
{
	struct mhi_driver *mhi_drv;

	if (!mhi_dev->dev.driver)
		return;

	mhi_drv = to_mhi_driver(mhi_dev->dev.driver);

	if (mhi_drv->status_cb)
		mhi_drv->status_cb(mhi_dev, cb_reason);
}

/* bind mhi channels into mhi devices */
void mhi_create_devices(struct mhi_controller *mhi_cntrl)
{
	int i;
	struct mhi_chan *mhi_chan;
	struct mhi_device *mhi_dev;
	int ret;

	mhi_chan = mhi_cntrl->mhi_chan;
	for (i = 0; i < mhi_cntrl->max_chan; i++, mhi_chan++) {
		if (!mhi_chan->configured || mhi_chan->ee != mhi_cntrl->ee)
			continue;
		mhi_dev = mhi_alloc_device(mhi_cntrl);
		if (!mhi_dev)
			return;

		if (mhi_chan->dir == DMA_TO_DEVICE) {
			mhi_dev->ul_chan = mhi_chan;
			mhi_dev->ul_chan_id = mhi_chan->chan;
			mhi_dev->ul_xfer = mhi_chan->queue_xfer;
			mhi_dev->ul_event_id = mhi_chan->er_index;
		} else {
			mhi_dev->dl_chan = mhi_chan;
			mhi_dev->dl_chan_id = mhi_chan->chan;
			mhi_dev->dl_xfer = mhi_chan->queue_xfer;
			mhi_dev->dl_event_id = mhi_chan->er_index;
		}

		mhi_chan->mhi_dev = mhi_dev;

		/* check next channel if it matches */
		if ((i + 1) < mhi_cntrl->max_chan && mhi_chan[1].configured) {
			if (!strcmp(mhi_chan[1].name, mhi_chan->name)) {
				i++;
				mhi_chan++;
				if (mhi_chan->dir == DMA_TO_DEVICE) {
					mhi_dev->ul_chan = mhi_chan;
					mhi_dev->ul_chan_id = mhi_chan->chan;
					mhi_dev->ul_xfer = mhi_chan->queue_xfer;
					mhi_dev->ul_event_id =
						mhi_chan->er_index;
				} else {
					mhi_dev->dl_chan = mhi_chan;
					mhi_dev->dl_chan_id = mhi_chan->chan;
					mhi_dev->dl_xfer = mhi_chan->queue_xfer;
					mhi_dev->dl_event_id =
						mhi_chan->er_index;
				}
				mhi_chan->mhi_dev = mhi_dev;
			}
		}

		mhi_dev->chan_name = mhi_chan->name;
		dev_set_name(&mhi_dev->dev, "%04x_%02u.%02u.%02u_%s",
			     mhi_dev->dev_id, mhi_dev->domain, mhi_dev->bus,
			     mhi_dev->slot, mhi_dev->chan_name);

		ret = device_add(&mhi_dev->dev);
		if (ret) {
			MHI_ERR("Failed to register dev for  chan:%s\n",
				mhi_dev->chan_name);
			mhi_dealloc_device(mhi_cntrl, mhi_dev);
		}
	}

	//mhi_cntrl->klog_lvl = MHI_MSG_LVL_ERROR;
}

static int parse_xfer_event(struct mhi_controller *mhi_cntrl,
			    struct mhi_tre *event,
			    struct mhi_chan *mhi_chan)
{
	struct mhi_ring *buf_ring, *tre_ring;
	u32 ev_code;
	struct mhi_result result;
	unsigned long flags = 0;

	ev_code = MHI_TRE_GET_EV_CODE(event);
	buf_ring = &mhi_chan->buf_ring;
	tre_ring = &mhi_chan->tre_ring;

	if (CHAN_INBOUND(mhi_chan->chan) && (tre_ring->rp + tre_ring->el_size == tre_ring->wp)) {
		mhi_chan->full++;
	}

	result.transaction_status = (ev_code == MHI_EV_CC_OVERFLOW) ?
		-EOVERFLOW : 0;

	/*
	 * if it's a DB Event then we need to grab the lock
	 * with preemption disable and as a write because we
	 * have to update db register and another thread could
	 * be doing same.
	 */
	if (ev_code >= MHI_EV_CC_OOB)
		write_lock_irqsave(&mhi_chan->lock, flags);
	else
		read_lock_bh(&mhi_chan->lock);

	if (mhi_chan->ch_state != MHI_CH_STATE_ENABLED)
		goto end_process_tx_event;

	switch (ev_code) {
	case MHI_EV_CC_OVERFLOW:
	case MHI_EV_CC_EOB:
	case MHI_EV_CC_EOT:
	{
		dma_addr_t ptr = MHI_TRE_GET_EV_PTR(event);
		struct mhi_tre *local_rp, *ev_tre;
		void *dev_rp;
		struct mhi_buf_info *buf_info;
		u16 xfer_len;

		/* Get the TRB this event points to */
		ev_tre = mhi_to_virtual(tre_ring, ptr);

		/* device rp after servicing the TREs */
		dev_rp = ev_tre + 1;
		if (dev_rp >= (tre_ring->base + tre_ring->len))
			dev_rp = tre_ring->base;

		result.dir = mhi_chan->dir;

		/* local rp */
		local_rp = tre_ring->rp;
		MHI_VERB("base=%p, local_wp=%p, local_rp=%p, dev_rp=%p\n", tre_ring->base, tre_ring->wp, tre_ring->rp, dev_rp);
		while (local_rp != dev_rp) {
			buf_info = buf_ring->rp;
			/* if it's last tre get len from the event */
			if (local_rp == ev_tre)
				xfer_len = MHI_TRE_GET_EV_LEN(event);
			else
				xfer_len = buf_info->len;

			dma_unmap_single(mhi_cntrl->dev, buf_info->p_addr,
					 buf_info->len, buf_info->dir);

			result.buf_addr = buf_info->cb_buf;
			result.bytes_xferd = xfer_len;
			mhi_del_ring_element(mhi_cntrl, buf_ring);
			mhi_del_ring_element(mhi_cntrl, tre_ring);
			local_rp = tre_ring->rp;

			MHI_VERB("buf_addr=%p, bytes_xferd=%zd\n", result.buf_addr, result.bytes_xferd);
			/* notify client */
			mhi_chan->xfer_cb(mhi_chan->mhi_dev, &result);

			if (mhi_chan->dir == DMA_TO_DEVICE) {
				read_lock_bh(&mhi_cntrl->pm_lock);
				mhi_cntrl->wake_put(mhi_cntrl, false);
				read_unlock_bh(&mhi_cntrl->pm_lock);
			}

			/*
			 * recycle the buffer if buffer is pre-allocated,
			 * if there is error, not much we can do apart from
			 * dropping the packet
			 */
			if (mhi_chan->pre_alloc) {
				if (mhi_queue_buf(mhi_chan->mhi_dev, mhi_chan,
						  buf_info->cb_buf,
						  buf_info->len, MHI_EOT)) {
					MHI_ERR(
						"Error recycling buffer for chan:%d\n",
						mhi_chan->chan);
					kfree(buf_info->cb_buf);
				}
			}
		};
		break;
	} /* CC_EOT */
	case MHI_EV_CC_OOB:
	case MHI_EV_CC_DB_MODE:
	{
		unsigned long flags;

		MHI_VERB("DB_MODE/OOB Detected chan %d.\n", mhi_chan->chan);
		mhi_chan->db_cfg.db_mode = 1;
		read_lock_irqsave(&mhi_cntrl->pm_lock, flags);
		if (tre_ring->wp != tre_ring->rp &&
		    MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state)) {
			mhi_ring_chan_db(mhi_cntrl, mhi_chan);
		}
		read_unlock_irqrestore(&mhi_cntrl->pm_lock, flags);
		break;
	}
	case MHI_EV_CC_BAD_TRE:
		MHI_ASSERT(1, "Received BAD TRE event for ring");
		break;
	default:
		MHI_CRITICAL("Unknown TX completion.\n");

		break;
	} /* switch(MHI_EV_READ_CODE(EV_TRB_CODE,event)) */

end_process_tx_event:
	if (ev_code >= MHI_EV_CC_OOB)
		write_unlock_irqrestore(&mhi_chan->lock, flags);
	else
		read_unlock_bh(&mhi_chan->lock);

	return 0;
}

#include "mhi_common.h"
static void mhi_dump_tre(struct mhi_controller *mhi_cntrl, struct mhi_tre *_ev) {
	union mhi_dev_ring_element_type *ev = (union mhi_dev_ring_element_type *)_ev;

	switch (ev->generic.type) {
		case MHI_DEV_RING_EL_INVALID: {
			MHI_ERR("carl_ev cmd_invalid, ptr=%llx, %x, %x\n", _ev->ptr, _ev->dword[0], _ev->dword[1]);
		}
		break;
		case MHI_DEV_RING_EL_NOOP: {
			MHI_LOG("carl_ev cmd_no_op chan=%u\n", ev->cmd_no_op.chid);
		}
		break;
		case MHI_DEV_RING_EL_TRANSFER: {
			MHI_LOG("carl_ev tre data=%llx, len=%u, chan=%u\n",
				ev->tre.data_buf_ptr, ev->tre.len, ev->tre.chain);
		}
		break;
		case MHI_DEV_RING_EL_RESET: {
			MHI_LOG("carl_ev cmd_reset chan=%u\n", ev->cmd_reset.chid);
		}
		break;
		case MHI_DEV_RING_EL_STOP: {
			MHI_LOG("carl_ev cmd_stop chan=%u\n", ev->cmd_stop.chid);
		}
		break;
		case MHI_DEV_RING_EL_START: {
			MHI_LOG("carl_ev cmd_start chan=%u\n", ev->cmd_start.chid);
		}
		break;
		case MHI_DEV_RING_EL_MHI_STATE_CHG: {
			MHI_LOG("carl_ev evt_state_change mhistate=%u\n", ev->evt_state_change.mhistate);
		}
		break;
		case MHI_DEV_RING_EL_CMD_COMPLETION_EVT:{
			MHI_LOG("carl_ev evt_cmd_comp code=%u\n", ev->evt_cmd_comp.code);
		}
		break;
		case MHI_DEV_RING_EL_TRANSFER_COMPLETION_EVENT:{
			MHI_VERB("carl_ev evt_tr_comp ptr=%llx, len=%u, code=%u, chan=%u\n",
				ev->evt_tr_comp.ptr, ev->evt_tr_comp.len, ev->evt_tr_comp.code,  ev->evt_tr_comp.chid);
		}
		break;
		case MHI_DEV_RING_EL_EE_STATE_CHANGE_NOTIFY:{
			MHI_LOG("carl_ev evt_ee_state execenv=%u\n", ev->evt_ee_state.execenv);
		}
		break;
		case MHI_DEV_RING_EL_UNDEF: 
		default: {
			MHI_ERR("carl_ev el_undef type=%d\n", ev->generic.type);
		};
		break;
	}
}


static int mhi_process_event_ring(struct mhi_controller *mhi_cntrl,
				  struct mhi_event *mhi_event,
				  u32 event_quota)
{
	struct mhi_tre *dev_rp, *local_rp;
	struct mhi_ring *ev_ring = &mhi_event->ring;
	struct mhi_event_ctxt *er_ctxt =
		&mhi_cntrl->mhi_ctxt->er_ctxt[mhi_event->er_index];
	int count = 0;

	read_lock_bh(&mhi_cntrl->pm_lock);
	if (unlikely(MHI_EVENT_ACCESS_INVALID(mhi_cntrl->pm_state))) {
		MHI_ERR("No EV access, PM_STATE:%s\n",
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		read_unlock_bh(&mhi_cntrl->pm_lock);
		return -EIO;
	}

	mhi_cntrl->wake_get(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	dev_rp = mhi_to_virtual(ev_ring, le64_to_cpu(er_ctxt->rp));
	local_rp = ev_ring->rp;

	while (dev_rp != local_rp && event_quota > 0) {
		enum MHI_PKT_TYPE type = MHI_TRE_GET_EV_TYPE(local_rp);

		mhi_dump_tre(mhi_cntrl, local_rp);
		MHI_VERB("Processing Event:0x%llx 0x%08x 0x%08x\n",
			local_rp->ptr, local_rp->dword[0], local_rp->dword[1]);

		switch (type) {
		case MHI_PKT_TYPE_TX_EVENT:
		{
			u32 chan;
			struct mhi_chan *mhi_chan;

			chan = MHI_TRE_GET_EV_CHID(local_rp);
			mhi_chan = &mhi_cntrl->mhi_chan[chan];
			parse_xfer_event(mhi_cntrl, local_rp, mhi_chan);
			event_quota--;
			break;
		}
		case MHI_PKT_TYPE_STATE_CHANGE_EVENT:
		{
			enum MHI_STATE new_state;

			new_state = MHI_TRE_GET_EV_STATE(local_rp);

			MHI_LOG("MHI state change event to state:%s\n",
				TO_MHI_STATE_STR(new_state));

			switch (new_state) {
			case MHI_STATE_M0:
				mhi_pm_m0_transition(mhi_cntrl);
				break;
			case MHI_STATE_M1:
				mhi_pm_m1_transition(mhi_cntrl);
				break;
			case MHI_STATE_M3:
				mhi_pm_m3_transition(mhi_cntrl);
				break;
			case MHI_STATE_SYS_ERR:
			{
				enum MHI_PM_STATE new_state;

				MHI_ERR("MHI system error detected\n");
				write_lock_irq(&mhi_cntrl->pm_lock);
				new_state = mhi_tryset_pm_state(mhi_cntrl,
							MHI_PM_SYS_ERR_DETECT);
				write_unlock_irq(&mhi_cntrl->pm_lock);
				if (new_state == MHI_PM_SYS_ERR_DETECT)
					schedule_work(
						&mhi_cntrl->syserr_worker);
				break;
			}
			default:
				MHI_ERR("Unsupported STE:%s\n",
					TO_MHI_STATE_STR(new_state));
			}

			break;
		}
		case MHI_PKT_TYPE_CMD_COMPLETION_EVENT:
		{
			dma_addr_t ptr = MHI_TRE_GET_EV_PTR(local_rp);
			struct mhi_cmd *cmd_ring =
				&mhi_cntrl->mhi_cmd[PRIMARY_CMD_RING];
			struct mhi_ring *mhi_ring = &cmd_ring->ring;
			struct mhi_tre *cmd_pkt;
			struct mhi_chan *mhi_chan;
			u32 chan;

			cmd_pkt = mhi_to_virtual(mhi_ring, ptr);

			/* out of order completion received */
			MHI_ASSERT(cmd_pkt != mhi_ring->rp,
				   "Out of order cmd completion");

			chan = MHI_TRE_GET_CMD_CHID(cmd_pkt);

			mhi_chan = &mhi_cntrl->mhi_chan[chan];
			write_lock_bh(&mhi_chan->lock);
			mhi_chan->ccs = MHI_TRE_GET_EV_CODE(local_rp);
			complete(&mhi_chan->completion);
			write_unlock_bh(&mhi_chan->lock);
			mhi_del_ring_element(mhi_cntrl, mhi_ring);
			break;
		}
		case MHI_PKT_TYPE_EE_EVENT:
		{
			enum MHI_ST_TRANSITION st = MHI_ST_TRANSITION_MAX;
			enum MHI_EE event = MHI_TRE_GET_EV_EXECENV(local_rp);

			MHI_LOG("MHI EE received event:%s, old EE:%s\n",
				TO_MHI_EXEC_STR(event), TO_MHI_EXEC_STR(mhi_cntrl->ee));

			switch (event) {
			case MHI_EE_SBL:
				st = MHI_ST_TRANSITION_SBL;
				break;
			case MHI_EE_AMSS:
				st = MHI_ST_TRANSITION_AMSS;
				break;
			case MHI_EE_RDDM:
				mhi_cntrl->status_cb(mhi_cntrl,
						     mhi_cntrl->priv_data,
						     MHI_CB_EE_RDDM);
				break;
			/* fall thru to wake up the event */
			case MHI_EE_WFW:
			case MHI_EE_PT:
			case MHI_EE_EDL:
			case MHI_EE_FP:
			case MHI_EE_UEFI:
				write_lock_irq(&mhi_cntrl->pm_lock);
				if (event == MHI_EE_FP)
					st = MHI_ST_TRANSITION_FP;
				write_unlock_irq(&mhi_cntrl->pm_lock);
				wake_up(&mhi_cntrl->state_event);
				break;
			default:
				MHI_ERR("Unhandled EE event:%s\n",
					TO_MHI_EXEC_STR(event));
			}
			if (st != MHI_ST_TRANSITION_MAX)
				mhi_queue_state_transition(mhi_cntrl, st);
			break;
		}
		case MHI_PKT_TYPE_STALE_EVENT:
			MHI_VERB("Stale Event received for chan:%u\n",
				 MHI_TRE_GET_EV_CHID(local_rp));
			break;
		default:
			//MHI_ERR("Unsupported packet type code 0x%x\n", type);
			break;
		}

		memset((unsigned char *)ev_ring->rp, 0x00, ev_ring->el_size); //carl.yin debug
		mhi_recycle_ev_ring_element(mhi_cntrl, ev_ring);
		local_rp = ev_ring->rp;
		dev_rp = mhi_to_virtual(ev_ring, le64_to_cpu(er_ctxt->rp));
		count++;
	}
	read_lock_bh(&mhi_cntrl->pm_lock);
	if (likely(MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state)))
		mhi_ring_er_db(mhi_event);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	MHI_VERB("exit er_index:%u\n", mhi_event->er_index);
	return count;
}

void mhi_ev_task(unsigned long data)
{
	struct mhi_event *mhi_event = (struct mhi_event *)data;
	struct mhi_controller *mhi_cntrl = mhi_event->mhi_cntrl;

	MHI_VERB("Enter for ev_index:%d\n", mhi_event->er_index);

	/* process all pending events */
	spin_lock_bh(&mhi_event->lock);
	mhi_process_event_ring(mhi_cntrl, mhi_event, U32_MAX);
	spin_unlock_bh(&mhi_event->lock);
}

void mhi_ctrl_ev_task(unsigned long data)
{
	struct mhi_event *mhi_event = (struct mhi_event *)data;
	struct mhi_controller *mhi_cntrl = mhi_event->mhi_cntrl;
	enum MHI_STATE state = MHI_STATE_MAX;
	enum MHI_PM_STATE pm_state = 0;
	int ret;

	MHI_VERB("Enter for ev_index:%d\n", mhi_event->er_index);

	/* process ctrl events events */
	ret = mhi_process_event_ring(mhi_cntrl, mhi_event, U32_MAX);

	/*
	 * we received a MSI but no events to process maybe device went to
	 * SYS_ERR state, check the state
	 */
	if (!ret) {
		write_lock_irq(&mhi_cntrl->pm_lock);
		if (MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state))
			state = mhi_get_m_state(mhi_cntrl);
		if (state == MHI_STATE_SYS_ERR) {
			MHI_ERR("MHI system error detected\n");
			pm_state = mhi_tryset_pm_state(mhi_cntrl,
						       MHI_PM_SYS_ERR_DETECT);
		}
		write_unlock_irq(&mhi_cntrl->pm_lock);
		if (pm_state == MHI_PM_SYS_ERR_DETECT)
			schedule_work(&mhi_cntrl->syserr_worker);
	}
}

irqreturn_t mhi_msi_handlr(int irq_number, void *dev)
{
	struct mhi_event *mhi_event = dev;
	struct mhi_controller *mhi_cntrl = mhi_event->mhi_cntrl;
	struct mhi_event_ctxt *er_ctxt =
		&mhi_cntrl->mhi_ctxt->er_ctxt[mhi_event->er_index];
	struct mhi_ring *ev_ring = &mhi_event->ring;
	void *dev_rp = mhi_to_virtual(ev_ring, le64_to_cpu(er_ctxt->rp));

	if (mhi_cntrl->msi_allocated == 1)
	{
		unsigned long flags;
		int i;
		enum MHI_STATE mhi_state = mhi_get_m_state(mhi_cntrl);

		if (mhi_state == MHI_STATE_SYS_ERR) {
			enum MHI_PM_STATE pm_state = 0;
			
			MHI_ERR("MHI system error detected\n");
			write_lock_irqsave(&mhi_cntrl->pm_lock, flags);
			pm_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_SYS_ERR_DETECT);
			write_unlock_irqrestore(&mhi_cntrl->pm_lock, flags);
			if (pm_state == MHI_PM_SYS_ERR_DETECT)
				schedule_work(&mhi_cntrl->syserr_worker);
		} else if (mhi_state != mhi_cntrl->dev_state) {
			MHI_LOG("MHISTATUS %s -> %s\n", TO_MHI_STATE_STR(mhi_cntrl->dev_state), TO_MHI_STATE_STR(mhi_state));
			wake_up(&mhi_cntrl->state_event);
		}

		er_ctxt = mhi_cntrl->mhi_ctxt->er_ctxt;
		mhi_event = mhi_cntrl->data->mhi_event;
		for (i = 0; i < NUM_MHI_EVT_RINGS; i++, er_ctxt++, mhi_event++) {
			struct mhi_ring *ev_ring = &mhi_event->ring;
			void *dev_rp = mhi_to_virtual(ev_ring, le64_to_cpu(er_ctxt->rp));

			if (ev_ring->rp != dev_rp) {
				MHI_VERB("local_rp=%p vs dev_rp=%p\n", ev_ring->rp, dev_rp);
                            if (mhi_event->priority == MHI_ER_PRIORITY_HIGH)
                            {
                                tasklet_hi_schedule(&mhi_event->task);
                            }
                            else
                            {
				    tasklet_schedule(&mhi_event->task);
                            }
			}
		}
		
		return IRQ_HANDLED;
	}

	/* confirm ER has pending events to process before scheduling work */
	if (ev_ring->rp == dev_rp)
		return IRQ_HANDLED;

	/* client managed event ring, notify pending data */
	if (mhi_event->cl_manage) {
		struct mhi_chan *mhi_chan = mhi_event->mhi_chan;
		struct mhi_device *mhi_dev = mhi_chan->mhi_dev;

		if (mhi_dev)
			mhi_dev->status_cb(mhi_dev, MHI_CB_PENDING_DATA);
	} 
       else
       {
	    if (mhi_event->priority == MHI_ER_PRIORITY_HIGH)
           {
               tasklet_hi_schedule(&mhi_event->task);
           }
           else
           {
		tasklet_schedule(&mhi_event->task);
           }
       }

	return IRQ_HANDLED;
}

/* this is the threaded fn */
irqreturn_t mhi_intvec_threaded_handlr(int irq_number, void *dev)
{
	struct mhi_controller *mhi_cntrl = dev;
	enum MHI_STATE state = MHI_STATE_MAX;
	enum MHI_PM_STATE pm_state = 0;
	
	MHI_VERB("Enter\n");

	write_lock_irq(&mhi_cntrl->pm_lock);
	if (MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state))
		state = mhi_get_m_state(mhi_cntrl);
	if (state == MHI_STATE_SYS_ERR) {
		MHI_ERR("MHI system error detected\n");
		pm_state = mhi_tryset_pm_state(mhi_cntrl,
					       MHI_PM_SYS_ERR_DETECT);
	}
	write_unlock_irq(&mhi_cntrl->pm_lock);
	if (pm_state == MHI_PM_SYS_ERR_DETECT)
		schedule_work(&mhi_cntrl->syserr_worker);

	MHI_VERB("Exit\n");

	return IRQ_HANDLED;
}

irqreturn_t mhi_intvec_handlr(int irq_number, void *dev)
{

	struct mhi_controller *mhi_cntrl = dev;

	/* wake up any events waiting for state change */
	MHI_VERB("Enter\n");
	wake_up(&mhi_cntrl->state_event);
	MHI_VERB("Exit\n");

	return IRQ_WAKE_THREAD;
}

static int mhi_send_cmd(struct mhi_controller *mhi_cntrl,
			struct mhi_chan *mhi_chan,
			enum MHI_CMD cmd)
{
	struct mhi_tre *cmd_tre = NULL;
	struct mhi_cmd *mhi_cmd = &mhi_cntrl->mhi_cmd[PRIMARY_CMD_RING];
	struct mhi_ring *ring = &mhi_cmd->ring;
	int chan = mhi_chan->chan;

	MHI_VERB("Entered, MHI pm_state:%s dev_state:%s ee:%s\n",
		 to_mhi_pm_state_str(mhi_cntrl->pm_state),
		 TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		 TO_MHI_EXEC_STR(mhi_cntrl->ee));

	/* MHI host currently handles RESET and START cmd */
	if (cmd != MHI_CMD_START_CHAN && cmd != MHI_CMD_RESET_CHAN)
		return -EINVAL;

	spin_lock_bh(&mhi_cmd->lock);
	if (!get_nr_avail_ring_elements(mhi_cntrl, ring)) {
		spin_unlock_bh(&mhi_cmd->lock);
		return -ENOMEM;
	}

	/* prepare the cmd tre */
	cmd_tre = ring->wp;
	if (cmd == MHI_CMD_START_CHAN) {
		cmd_tre->ptr = MHI_TRE_CMD_START_PTR;
		cmd_tre->dword[0] = MHI_TRE_CMD_START_DWORD0;
		cmd_tre->dword[1] = MHI_TRE_CMD_START_DWORD1(chan);
	} else {
		cmd_tre->ptr = MHI_TRE_CMD_RESET_PTR;
		cmd_tre->dword[0] = MHI_TRE_CMD_RESET_DWORD0;
		cmd_tre->dword[1] = MHI_TRE_CMD_RESET_DWORD1(chan);
	}

	MHI_VERB("WP:0x%llx TRE: 0x%llx 0x%08x 0x%08x\n",
		 (u64)mhi_to_physical(ring, cmd_tre), le64_to_cpu(cmd_tre->ptr),
		 le32_to_cpu(cmd_tre->dword[0]), le32_to_cpu(cmd_tre->dword[1]));

	/* queue to hardware */
	mhi_add_ring_element(mhi_cntrl, ring);
	read_lock_bh(&mhi_cntrl->pm_lock);
	if (likely(MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state)))
		mhi_ring_cmd_db(mhi_cntrl, mhi_cmd);
	read_unlock_bh(&mhi_cntrl->pm_lock);
	spin_unlock_bh(&mhi_cmd->lock);

	return 0;
}

static int __mhi_prepare_channel(struct mhi_controller *mhi_cntrl,
				 struct mhi_chan *mhi_chan)
{
	int ret = 0;

	MHI_LOG("Entered: preparing channel:%d\n", mhi_chan->chan);

	if (mhi_cntrl->ee != mhi_chan->ee) {
		MHI_ERR("Current EE:%s Required EE:%s for chan:%s\n",
			TO_MHI_EXEC_STR(mhi_cntrl->ee),
			TO_MHI_EXEC_STR(mhi_chan->ee),
			mhi_chan->name);
		return -ENOTCONN;
	}

	mutex_lock(&mhi_chan->mutex);
	/* client manages channel context for offload channels */
	if (!mhi_chan->offload_ch) {
		ret = mhi_init_chan_ctxt(mhi_cntrl, mhi_chan);
		if (ret) {
			MHI_ERR("Error with init chan\n");
			goto error_init_chan;
		}
	}

	reinit_completion(&mhi_chan->completion);
	read_lock_bh(&mhi_cntrl->pm_lock);
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("MHI host is not in active state\n");
		read_unlock_bh(&mhi_cntrl->pm_lock);
		ret = -EIO;
		goto error_pm_state;
	}

	mhi_cntrl->wake_get(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->runtime_get(mhi_cntrl, mhi_cntrl->priv_data);
	mhi_cntrl->runtime_put(mhi_cntrl, mhi_cntrl->priv_data);

	ret = mhi_send_cmd(mhi_cntrl, mhi_chan, MHI_CMD_START_CHAN);
	if (ret) {
		MHI_ERR("Failed to send start chan cmd\n");
		goto error_send_cmd;
	}

	ret = wait_for_completion_timeout(&mhi_chan->completion,
				msecs_to_jiffies(mhi_cntrl->timeout_ms));
	if (!ret || mhi_chan->ccs != MHI_EV_CC_SUCCESS) {
		MHI_ERR("Failed to receive cmd completion for chan:%d\n",
			mhi_chan->chan);
		ret = -EIO;
		goto error_send_cmd;
	}

	write_lock_irq(&mhi_chan->lock);
	mhi_chan->ch_state = MHI_CH_STATE_ENABLED;
	write_unlock_irq(&mhi_chan->lock);

	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	/* pre allocate buffer for xfer ring */
	if (mhi_chan->pre_alloc) {
		struct mhi_device *mhi_dev = mhi_chan->mhi_dev;
		int nr_el = get_nr_avail_ring_elements(mhi_cntrl,
						       &mhi_chan->tre_ring);

		while (nr_el--) {
			void *buf;

			buf = kmalloc(MHI_MAX_MTU, GFP_KERNEL);
			if (!buf) {
				ret = -ENOMEM;
				goto error_pre_alloc;
			}

			ret = mhi_queue_buf(mhi_dev, mhi_chan, buf, MHI_MAX_MTU,
					    MHI_EOT);
			if (ret) {
				MHI_ERR("Chan:%d error queue buffer\n",
					mhi_chan->chan);
				kfree(buf);
				goto error_pre_alloc;
			}
		}
	}

	mutex_unlock(&mhi_chan->mutex);

	MHI_LOG("Chan:%d successfully moved to start state\n", mhi_chan->chan);

	return 0;

error_send_cmd:
	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

error_pm_state:
	if (!mhi_chan->offload_ch)
		mhi_deinit_chan_ctxt(mhi_cntrl, mhi_chan);

error_init_chan:
	mutex_unlock(&mhi_chan->mutex);

	return ret;

error_pre_alloc:
	mutex_unlock(&mhi_chan->mutex);
	__mhi_unprepare_channel(mhi_cntrl, mhi_chan);

	return ret;
}

void mhi_reset_chan(struct mhi_controller *mhi_cntrl, struct mhi_chan *mhi_chan)
{
	struct mhi_tre *dev_rp, *local_rp;
	struct mhi_event_ctxt *er_ctxt;
	struct mhi_event *mhi_event;
	struct mhi_ring *ev_ring, *buf_ring, *tre_ring;
	unsigned long flags;
	int chan = mhi_chan->chan;
	struct mhi_result result;

	/* nothing to reset, client don't queue buffers */
	if (mhi_chan->offload_ch)
		return;

	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_event = &mhi_cntrl->mhi_event[mhi_chan->er_index];
	ev_ring = &mhi_event->ring;
	er_ctxt = &mhi_cntrl->mhi_ctxt->er_ctxt[mhi_chan->er_index];

	MHI_LOG("Marking all events for chan:%d as stale\n", chan);

	/* mark all stale events related to channel as STALE event */
	spin_lock_irqsave(&mhi_event->lock, flags);
	dev_rp = mhi_to_virtual(ev_ring, le64_to_cpu(er_ctxt->rp));
	if (!mhi_event->mhi_chan) {
		local_rp = ev_ring->rp;
		while (dev_rp != local_rp) {
			if (MHI_TRE_GET_EV_TYPE(local_rp) ==
			    MHI_PKT_TYPE_TX_EVENT &&
			    chan == MHI_TRE_GET_EV_CHID(local_rp))
				local_rp->dword[1] = MHI_TRE_EV_DWORD1(chan,
						MHI_PKT_TYPE_STALE_EVENT);
			local_rp++;
			if (local_rp == (ev_ring->base + ev_ring->len))
				local_rp = ev_ring->base;
		}
	} else {
		/* dedicated event ring so move the ptr to end */
		ev_ring->rp = dev_rp;
		ev_ring->wp = ev_ring->rp - ev_ring->el_size;
		if (ev_ring->wp < ev_ring->base)
			ev_ring->wp = ev_ring->base + ev_ring->len -
				ev_ring->el_size;
		if (likely(MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state)))
			mhi_ring_er_db(mhi_event);
	}

	MHI_LOG("Finished marking events as stale events\n");
	spin_unlock_irqrestore(&mhi_event->lock, flags);

	/* reset any pending buffers */
	buf_ring = &mhi_chan->buf_ring;
	tre_ring = &mhi_chan->tre_ring;
	result.transaction_status = -ENOTCONN;
	result.bytes_xferd = 0;
	while (tre_ring->rp != tre_ring->wp) {
		struct mhi_buf_info *buf_info = buf_ring->rp;

		if (mhi_chan->dir == DMA_TO_DEVICE)
			mhi_cntrl->wake_put(mhi_cntrl, false);

		dma_unmap_single(mhi_cntrl->dev, buf_info->p_addr,
				 buf_info->len, buf_info->dir);
		mhi_del_ring_element(mhi_cntrl, buf_ring);
		mhi_del_ring_element(mhi_cntrl, tre_ring);

		if (mhi_chan->pre_alloc) {
			kfree(buf_info->cb_buf);
		} else {
			result.buf_addr = buf_info->cb_buf;
			mhi_chan->xfer_cb(mhi_chan->mhi_dev, &result);
		}
	}

	read_unlock_bh(&mhi_cntrl->pm_lock);
	MHI_LOG("Reset complete.\n");
}

static void __mhi_unprepare_channel(struct mhi_controller *mhi_cntrl,
				    struct mhi_chan *mhi_chan)
{
	int ret;

	MHI_LOG("Entered: unprepare channel:%d\n", mhi_chan->chan);

	/* no more processing events for this channel */
	mutex_lock(&mhi_chan->mutex);
	write_lock_irq(&mhi_chan->lock);
	if (mhi_chan->ch_state != MHI_CH_STATE_ENABLED) {
		MHI_LOG("chan:%d is already disabled\n", mhi_chan->chan);
		write_unlock_irq(&mhi_chan->lock);
		mutex_unlock(&mhi_chan->mutex);
		return;
	}

	mhi_chan->ch_state = MHI_CH_STATE_DISABLED;
	write_unlock_irq(&mhi_chan->lock);

	reinit_completion(&mhi_chan->completion);
	read_lock_bh(&mhi_cntrl->pm_lock);
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		read_unlock_bh(&mhi_cntrl->pm_lock);
		goto error_invalid_state;
	}

	mhi_cntrl->wake_get(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	mhi_cntrl->runtime_get(mhi_cntrl, mhi_cntrl->priv_data);
	mhi_cntrl->runtime_put(mhi_cntrl, mhi_cntrl->priv_data);
	ret = mhi_send_cmd(mhi_cntrl, mhi_chan, MHI_CMD_RESET_CHAN);
	if (ret) {
		MHI_ERR("Failed to send reset chan cmd\n");
		goto error_completion;
	}

	/* even if it fails we will still reset */
	ret = wait_for_completion_timeout(&mhi_chan->completion,
				msecs_to_jiffies(mhi_cntrl->timeout_ms));
	if (!ret || mhi_chan->ccs != MHI_EV_CC_SUCCESS)
		MHI_ERR("Failed to receive cmd completion, still resetting\n");

error_completion:
	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

error_invalid_state:
	if (!mhi_chan->offload_ch) {
		mhi_reset_chan(mhi_cntrl, mhi_chan);
		mhi_deinit_chan_ctxt(mhi_cntrl, mhi_chan);
	}
	MHI_LOG("chan:%d successfully resetted\n", mhi_chan->chan);
	mutex_unlock(&mhi_chan->mutex);
}

int mhi_debugfs_mhi_states_show(struct seq_file *m, void *d)
{
	struct mhi_controller *mhi_cntrl = m->private;
	u32 reset=-1, ready=-1;
	int ret;
	
	ret = mhi_read_reg_field(mhi_cntrl, mhi_cntrl->regs, MHICTRL,
		      MHICTRL_RESET_MASK, MHICTRL_RESET_SHIFT, &reset);
	ret = mhi_read_reg_field(mhi_cntrl, mhi_cntrl->regs, MHISTATUS,
		      MHISTATUS_READY_MASK, MHISTATUS_READY_SHIFT, &ready);
	if (!ret)
	seq_printf(m,
		"Device current EE:%s, M:%s, RESET:%d, READY:%d\n",
		TO_MHI_EXEC_STR(mhi_get_exec_env(mhi_cntrl)),
		TO_MHI_STATE_STR(mhi_get_m_state(mhi_cntrl)),
		reset, ready);
   
	seq_printf(m,
		   "pm_state:%s dev_state:%s EE:%s M0:%u M1:%u M2:%u M3:%u wake:%d dev_wake:%u alloc_size:%u\n",
		   to_mhi_pm_state_str(mhi_cntrl->pm_state),
		   TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		   TO_MHI_EXEC_STR(mhi_cntrl->ee),
		   mhi_cntrl->M0, mhi_cntrl->M1, mhi_cntrl->M2, mhi_cntrl->M3,
		   mhi_cntrl->wake_set,
		   atomic_read(&mhi_cntrl->dev_wake),
		   atomic_read(&mhi_cntrl->alloc_size));

	return 0;
}

int mhi_debugfs_mhi_event_show(struct seq_file *m, void *d)
{
	struct mhi_controller *mhi_cntrl = m->private;
	struct mhi_event *mhi_event;
	struct mhi_event_ctxt *er_ctxt;

	int i;

	er_ctxt = mhi_cntrl->mhi_ctxt->er_ctxt;
	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, er_ctxt++,
		     mhi_event++) {
		struct mhi_ring *ring = &mhi_event->ring;

		if (mhi_event->offload_ev) {
			seq_printf(m, "Index:%d offload event ring\n", i);
		} else {
			seq_printf(m,
				   "Index:%d modc:%d modt:%d base:0x%0llx len:0x%llx",
				   i, er_ctxt->intmodc, er_ctxt->intmodt,
				   er_ctxt->rbase, er_ctxt->rlen);
			seq_printf(m,
				   " rp:0x%llx wp:0x%llx local_rp:0x%llx db:0x%llx\n",
				   er_ctxt->rp, er_ctxt->wp,
				   (u64)mhi_to_physical(ring, ring->rp),
				   (u64)mhi_event->db_cfg.db_val);
			{
				struct mhi_tre *tre = (struct mhi_tre *)ring->base;
				size_t i;
				for (i = 0; i < ring->elements; i++, tre++) {
					seq_printf(m,
						"%llx, %x, %x\n",
						tre->ptr, tre->dword[0], tre->dword[1]);
				}
			}
		}
	}

	return 0;
}

int mhi_debugfs_mhi_chan_show(struct seq_file *m, void *d)
{
	struct mhi_controller *mhi_cntrl = m->private;
	struct mhi_chan *mhi_chan;
	struct mhi_chan_ctxt *chan_ctxt;
	int i;

	mhi_chan = mhi_cntrl->mhi_chan;
	chan_ctxt = mhi_cntrl->mhi_ctxt->chan_ctxt;
	for (i = 0; i < mhi_cntrl->max_chan; i++, chan_ctxt++, mhi_chan++) {
		struct mhi_ring *ring = &mhi_chan->tre_ring;

		if (mhi_chan->offload_ch) {
			seq_printf(m, "%s(%u) offload channel\n",
				   mhi_chan->name, mhi_chan->chan);
		} else if (mhi_chan->mhi_dev) {
			seq_printf(m,
				   "%s(%u) state:0x%x brstmode:0x%x pllcfg:0x%x type:0x%x erindex:%u",
				   mhi_chan->name, mhi_chan->chan,
				   chan_ctxt->chstate, chan_ctxt->brstmode,
				   chan_ctxt->pollcfg, chan_ctxt->chtype,
				   chan_ctxt->erindex);
			seq_printf(m,
				   " base:0x%llx len:0x%llx wp:0x%llx local_rp:0x%llx local_wp:0x%llx db:0x%llx full:%d\n",
				   chan_ctxt->rbase, chan_ctxt->rlen,
				   chan_ctxt->wp,
				   (u64)mhi_to_physical(ring, ring->rp),
				   (u64)mhi_to_physical(ring, ring->wp),
				   (u64)mhi_chan->db_cfg.db_val, mhi_chan->full);
		}
	}

	return 0;
}

/* move channel to start state */
int mhi_prepare_for_transfer(struct mhi_device *mhi_dev)
{
	int ret, dir;
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_chan *mhi_chan;

	for (dir = 0; dir < 2; dir++) {
		mhi_chan = dir ? mhi_dev->ul_chan : mhi_dev->dl_chan;

		if (!mhi_chan)
			continue;

		ret = __mhi_prepare_channel(mhi_cntrl, mhi_chan);
		if (ret) {
			MHI_ERR("Error moving chan %s,%d to START state\n",
				mhi_chan->name, mhi_chan->chan);
			goto error_open_chan;
		}
	}

	return 0;

error_open_chan:
	for (--dir; dir >= 0; dir--) {
		mhi_chan = dir ? mhi_dev->ul_chan : mhi_dev->dl_chan;

		if (!mhi_chan)
			continue;

		__mhi_unprepare_channel(mhi_cntrl, mhi_chan);
	}

	return ret;
}
EXPORT_SYMBOL(mhi_prepare_for_transfer);

void mhi_unprepare_from_transfer(struct mhi_device *mhi_dev)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_chan *mhi_chan;
	int dir;

	for (dir = 0; dir < 2; dir++) {
		mhi_chan = dir ? mhi_dev->ul_chan : mhi_dev->dl_chan;

		if (!mhi_chan)
			continue;

		__mhi_unprepare_channel(mhi_cntrl, mhi_chan);
	}
}
EXPORT_SYMBOL(mhi_unprepare_from_transfer);

int mhi_get_no_free_descriptors(struct mhi_device *mhi_dev,
				enum dma_data_direction dir)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_chan *mhi_chan = (dir == DMA_TO_DEVICE) ?
		mhi_dev->ul_chan : mhi_dev->dl_chan;
	struct mhi_ring *tre_ring = &mhi_chan->tre_ring;

	return get_nr_avail_ring_elements(mhi_cntrl, tre_ring);
}
EXPORT_SYMBOL(mhi_get_no_free_descriptors);

struct mhi_controller *mhi_bdf_to_controller(u32 domain,
					     u32 bus,
					     u32 slot,
					     u32 dev_id)
{
	struct mhi_controller *itr, *tmp;

	list_for_each_entry_safe(itr, tmp, &mhi_bus.controller_list, node)
		if (itr->domain == domain && itr->bus == bus &&
		    itr->slot == slot && itr->dev_id == dev_id)
			return itr;

	return NULL;
}
EXPORT_SYMBOL(mhi_bdf_to_controller);

int mhi_poll(struct mhi_device *mhi_dev,
	     u32 budget)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	struct mhi_chan *mhi_chan = mhi_dev->dl_chan;
	struct mhi_event *mhi_event = &mhi_cntrl->mhi_event[mhi_chan->er_index];
	int ret;

	spin_lock_bh(&mhi_event->lock);
	ret = mhi_process_event_ring(mhi_cntrl, mhi_event, budget);
	spin_unlock_bh(&mhi_event->lock);

	return ret;
}
EXPORT_SYMBOL(mhi_poll);
