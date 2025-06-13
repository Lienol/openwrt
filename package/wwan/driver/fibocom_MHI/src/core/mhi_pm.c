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
#include <linux/interrupt.h>
#include <linux/list.h>
#include <linux/of.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/sched.h>
#include <linux/wait.h>
#include "mhi.h"
#include "mhi_internal.h"

/*
 * Not all MHI states transitions are sync transitions. Linkdown, SSR, and
 * shutdown can happen anytime asynchronously. This function will transition to
 * new state only if we're allowed to transitions.
 *
 * Priority increase as we go down, example while in any states from L0, start
 * state from L1, L2, or L3 can be set.  Notable exception to this rule is state
 * DISABLE.  From DISABLE state we can transition to only POR or state.  Also
 * for example while in L2 state, user cannot jump back to L1 or L0 states.
 * Valid transitions:
 * L0: DISABLE <--> POR
 *     POR <--> POR
 *     POR -> M0 -> M1 -> M1_M2 -> M2 --> M0
 *     POR -> FW_DL_ERR
 *     FW_DL_ERR <--> FW_DL_ERR
 *     M0 -> FW_DL_ERR
 *     M1_M2 -> M0 (Device can trigger it)
 *     M0 -> M3_ENTER -> M3 -> M3_EXIT --> M0
 *     M1 -> M3_ENTER --> M3
 * L1: SYS_ERR_DETECT -> SYS_ERR_PROCESS --> POR
 * L2: SHUTDOWN_PROCESS -> DISABLE
 * L3: LD_ERR_FATAL_DETECT <--> LD_ERR_FATAL_DETECT
 *     LD_ERR_FATAL_DETECT -> SHUTDOWN_PROCESS
 */
static struct mhi_pm_transitions const mhi_state_transitions[] = {
	/* L0 States */
	{
		MHI_PM_DISABLE,
		MHI_PM_POR
	},
	{
		MHI_PM_POR,
		MHI_PM_POR | MHI_PM_DISABLE | MHI_PM_M0 |
		MHI_PM_SYS_ERR_DETECT | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT | MHI_PM_FW_DL_ERR
	},
	{
		MHI_PM_M0,
		MHI_PM_M1 | MHI_PM_M3_ENTER | MHI_PM_SYS_ERR_DETECT |
		MHI_PM_SHUTDOWN_PROCESS | MHI_PM_LD_ERR_FATAL_DETECT |
		MHI_PM_FW_DL_ERR
	},
	{
		MHI_PM_M1,
		MHI_PM_M1_M2_TRANSITION | MHI_PM_M3_ENTER |
		MHI_PM_SYS_ERR_DETECT | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_M1_M2_TRANSITION,
		MHI_PM_M2 | MHI_PM_M0 | MHI_PM_SYS_ERR_DETECT |
		MHI_PM_SHUTDOWN_PROCESS | MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_M2,
		MHI_PM_M0 | MHI_PM_SYS_ERR_DETECT | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_M3_ENTER,
		MHI_PM_M3 | MHI_PM_SYS_ERR_DETECT | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_M3,
		MHI_PM_M3_EXIT | MHI_PM_SYS_ERR_DETECT |
		MHI_PM_SHUTDOWN_PROCESS | MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_M3_EXIT,
		MHI_PM_M0 | MHI_PM_SYS_ERR_DETECT | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_FW_DL_ERR,
		MHI_PM_FW_DL_ERR | MHI_PM_SYS_ERR_DETECT |
		MHI_PM_SHUTDOWN_PROCESS | MHI_PM_LD_ERR_FATAL_DETECT
	},
	/* L1 States */
	{
		MHI_PM_SYS_ERR_DETECT,
		MHI_PM_SYS_ERR_PROCESS | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT
	},
	{
		MHI_PM_SYS_ERR_PROCESS,
		MHI_PM_POR | MHI_PM_SHUTDOWN_PROCESS |
		MHI_PM_LD_ERR_FATAL_DETECT
	},
	/* L2 States */
	{
		MHI_PM_SHUTDOWN_PROCESS,
		MHI_PM_DISABLE | MHI_PM_LD_ERR_FATAL_DETECT
	},
	/* L3 States */
	{
		MHI_PM_LD_ERR_FATAL_DETECT,
		MHI_PM_LD_ERR_FATAL_DETECT | MHI_PM_SHUTDOWN_PROCESS
	},
};

enum MHI_PM_STATE __must_check mhi_tryset_pm_state(
				struct mhi_controller *mhi_cntrl,
				enum MHI_PM_STATE state)
{
	unsigned long cur_state = mhi_cntrl->pm_state;
	int index = find_last_bit(&cur_state, 32);

	if (unlikely(index >= ARRAY_SIZE(mhi_state_transitions))) {
		MHI_CRITICAL("cur_state:%s is not a valid pm_state\n",
			     to_mhi_pm_state_str(cur_state));
		return cur_state;
	}

	if (unlikely(mhi_state_transitions[index].from_state != cur_state)) {
		MHI_ERR("index:%u cur_state:%s != actual_state: %s\n",
			index, to_mhi_pm_state_str(cur_state),
			to_mhi_pm_state_str
			(mhi_state_transitions[index].from_state));
		return cur_state;
	}

	if (unlikely(!(mhi_state_transitions[index].to_states & state))) {
		MHI_LOG(
			"Not allowing pm state transition from:%s to:%s state\n",
			to_mhi_pm_state_str(cur_state),
			to_mhi_pm_state_str(state));
		return cur_state;
	}

	MHI_VERB("Transition to pm state from:%s to:%s\n",
		 to_mhi_pm_state_str(cur_state), to_mhi_pm_state_str(state));

	mhi_cntrl->pm_state = state;
	return mhi_cntrl->pm_state;
}

void mhi_set_mhi_state(struct mhi_controller *mhi_cntrl, enum MHI_STATE state)
{
	if (state == MHI_STATE_RESET) {
		mhi_write_reg_field(mhi_cntrl, mhi_cntrl->regs, MHICTRL,
				    MHICTRL_RESET_MASK, MHICTRL_RESET_SHIFT, 1);
	} else {
		mhi_write_reg_field(mhi_cntrl, mhi_cntrl->regs, MHICTRL,
			MHICTRL_MHISTATE_MASK, MHICTRL_MHISTATE_SHIFT, state);
	}
}

/* set device wake */
void mhi_assert_dev_wake(struct mhi_controller *mhi_cntrl, bool force)
{
	unsigned long flags;

	/* if set, regardless of count set the bit if not set */
	if (unlikely(force)) {
		spin_lock_irqsave(&mhi_cntrl->wlock, flags);
		atomic_inc(&mhi_cntrl->dev_wake);
		if (MHI_WAKE_DB_ACCESS_VALID(mhi_cntrl->pm_state) &&
		    !mhi_cntrl->wake_set) {
			mhi_write_db(mhi_cntrl, mhi_cntrl->wake_db, 1);
			mhi_cntrl->wake_set = true;
		}
		spin_unlock_irqrestore(&mhi_cntrl->wlock, flags);
	} else {
		/* if resources requested already, then increment and exit */
		if (likely(atomic_add_unless(&mhi_cntrl->dev_wake, 1, 0)))
			return;

		spin_lock_irqsave(&mhi_cntrl->wlock, flags);
		if ((atomic_inc_return(&mhi_cntrl->dev_wake) == 1) &&
		    MHI_WAKE_DB_ACCESS_VALID(mhi_cntrl->pm_state) &&
		    !mhi_cntrl->wake_set) {
			mhi_write_db(mhi_cntrl, mhi_cntrl->wake_db, 1);
			mhi_cntrl->wake_set = true;
		}
		spin_unlock_irqrestore(&mhi_cntrl->wlock, flags);
	}
}

/* clear device wake */
void mhi_deassert_dev_wake(struct mhi_controller *mhi_cntrl, bool override)
{
	unsigned long flags;

	if (atomic_read(&mhi_cntrl->dev_wake) == 0) {
		MHI_LOG("%s 00000\n", __func__);
		return;
	}

	MHI_ASSERT(atomic_read(&mhi_cntrl->dev_wake) == 0, "dev_wake == 0");

	/* resources not dropping to 0, decrement and exit */
	if (likely(atomic_add_unless(&mhi_cntrl->dev_wake, -1, 1)))
		return;

	spin_lock_irqsave(&mhi_cntrl->wlock, flags);
	if ((atomic_dec_return(&mhi_cntrl->dev_wake) == 0) &&
	    MHI_WAKE_DB_ACCESS_VALID(mhi_cntrl->pm_state) && !override &&
	    mhi_cntrl->wake_set) {
		mhi_write_db(mhi_cntrl, mhi_cntrl->wake_db, 0);
		mhi_cntrl->wake_set = false;
	}
	spin_unlock_irqrestore(&mhi_cntrl->wlock, flags);
}

int mhi_ready_state_transition(struct mhi_controller *mhi_cntrl)
{
	void __iomem *base = mhi_cntrl->regs;
	u32 reset = 1, ready = 0;
	struct mhi_event *mhi_event;
	enum MHI_PM_STATE cur_state;
	int ret, i;

	MHI_LOG("Waiting to enter READY state\n");

	MHI_LOG("Device current EE:%s, M:%s\n",
		TO_MHI_EXEC_STR(mhi_get_exec_env(mhi_cntrl)),
		TO_MHI_STATE_STR(mhi_get_m_state(mhi_cntrl)));

	/* wait for RESET to be cleared and READY bit to be set */
	for (i = 0; i < mhi_cntrl->timeout_ms; i += 25) { //maybe miss msi interrupt?
		ready = 0;
		wait_event_timeout(mhi_cntrl->state_event,
				   MHI_PM_IN_FATAL_STATE(mhi_cntrl->pm_state) ||
				   mhi_read_reg_field(mhi_cntrl, base, MHICTRL,
						      MHICTRL_RESET_MASK,
						      MHICTRL_RESET_SHIFT, &reset) ||
				   mhi_read_reg_field(mhi_cntrl, base, MHISTATUS,
						      MHISTATUS_READY_MASK,
						      MHISTATUS_READY_SHIFT, &ready) ||
				   (!reset && ready),
				   msecs_to_jiffies(25));

		/* device enter into error state */
		if (MHI_PM_IN_FATAL_STATE(mhi_cntrl->pm_state)) {
			MHI_LOG("reset=0x%x, ready=0x%x, pm_state=0x%x\n", reset, reset, mhi_cntrl->pm_state);
			return -EIO;
		}

		if (!reset && ready)
			break;
	}

	/* device did not transition to ready state */
	if (reset || !ready) {
		MHI_LOG("reset=0x%x, ready=0x%x, pm_state=0x%x\n", reset, reset, mhi_cntrl->pm_state);
		return -ETIMEDOUT;
	}

	MHI_LOG("Device in READY State\n");
	write_lock_irq(&mhi_cntrl->pm_lock);
	cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_POR);
	mhi_cntrl->dev_state = MHI_STATE_READY;
	write_unlock_irq(&mhi_cntrl->pm_lock);

	if (cur_state != MHI_PM_POR) {
		MHI_ERR("Error moving to state %s from %s\n",
			to_mhi_pm_state_str(MHI_PM_POR),
			to_mhi_pm_state_str(cur_state));
		return -EIO;
	}
	read_lock_bh(&mhi_cntrl->pm_lock);
	if (!MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state))
		goto error_mmio;

	ret = mhi_init_mmio(mhi_cntrl);
	if (ret) {
		MHI_ERR("Error programming mmio registers\n");
		goto error_mmio;
	}

	/* add elements to all sw event rings */
	MHI_LOG("mhi_db_sw_ring\n");
	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		struct mhi_ring *ring = &mhi_event->ring;

		if (mhi_event->offload_ev || mhi_event->hw_ring)
			continue;

		ring->wp = ring->base + ring->len - ring->el_size;
		*ring->ctxt_wp = cpu_to_le64(ring->iommu_base + ring->len - ring->el_size);
		/* needs to update to all cores */
		smp_wmb();

		/* ring the db for event rings */
		spin_lock_irq(&mhi_event->lock);
		mhi_ring_er_db(mhi_event);
		spin_unlock_irq(&mhi_event->lock);
	}

	/* set device into M0 state */
	mhi_set_mhi_state(mhi_cntrl, MHI_STATE_M0);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	return 0;

error_mmio:
	read_unlock_bh(&mhi_cntrl->pm_lock);

	return -EIO;
}

int mhi_pm_m0_transition(struct mhi_controller *mhi_cntrl)
{
	enum MHI_PM_STATE cur_state;
	struct mhi_chan *mhi_chan;
	int i;

	MHI_LOG("Entered With State:%s PM_STATE:%s\n",
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		to_mhi_pm_state_str(mhi_cntrl->pm_state));

	write_lock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->dev_state = MHI_STATE_M0;
	cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M0);
	write_unlock_irq(&mhi_cntrl->pm_lock);
	if (unlikely(cur_state != MHI_PM_M0)) {
		MHI_ERR("Failed to transition to state %s from %s\n",
			to_mhi_pm_state_str(MHI_PM_M0),
			to_mhi_pm_state_str(cur_state));
		return -EIO;
	}
	mhi_cntrl->M0++;
	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_get(mhi_cntrl, true);

	/* ring all event rings and CMD ring only if we're in AMSS */
	if (mhi_cntrl->ee == MHI_EE_AMSS) {
		//struct mhi_event *mhi_event = mhi_cntrl->mhi_event;
		struct mhi_cmd *mhi_cmd =
			&mhi_cntrl->mhi_cmd[PRIMARY_CMD_RING];

		MHI_LOG("mhi_db_all_ring\n");

		/* only ring primary cmd ring */
		spin_lock_irq(&mhi_cmd->lock);
		if (mhi_cmd->ring.rp != mhi_cmd->ring.wp)
			mhi_ring_cmd_db(mhi_cntrl, mhi_cmd);
		spin_unlock_irq(&mhi_cmd->lock);
	}

	/* ring channel db registers */
	mhi_chan = mhi_cntrl->mhi_chan;
	for (i = 0; i < mhi_cntrl->max_chan; i++, mhi_chan++) {
		struct mhi_ring *tre_ring = &mhi_chan->tre_ring;

		write_lock_irq(&mhi_chan->lock);
		if (mhi_chan->db_cfg.reset_req)
			mhi_chan->db_cfg.db_mode = true;

		/* only ring DB if ring is not empty */
		if (tre_ring->base && tre_ring->wp  != tre_ring->rp)
			mhi_ring_chan_db(mhi_cntrl, mhi_chan);
		write_unlock_irq(&mhi_chan->lock);
	}

	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);
	wake_up(&mhi_cntrl->state_event);
	MHI_VERB("Exited\n");

	return 0;
}

void mhi_pm_m1_worker(struct work_struct *work)
{
	enum MHI_PM_STATE cur_state;
	struct mhi_controller *mhi_cntrl;

	mhi_cntrl = container_of(work, struct mhi_controller, m1_worker);

	MHI_LOG("M1 state transition from dev_state:%s pm_state:%s\n",
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		to_mhi_pm_state_str(mhi_cntrl->pm_state));

	mutex_lock(&mhi_cntrl->pm_mutex);
	write_lock_irq(&mhi_cntrl->pm_lock);

	/* we either Entered M3 or we did M3->M0 Exit */
	if (mhi_cntrl->pm_state != MHI_PM_M1)
		goto invalid_pm_state;

	MHI_LOG("Transitioning to M2 Transition\n");
	cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M1_M2_TRANSITION);
	if (unlikely(cur_state != MHI_PM_M1_M2_TRANSITION)) {
		MHI_ERR("Failed to transition to state %s from %s\n",
			to_mhi_pm_state_str(MHI_PM_M1_M2_TRANSITION),
			to_mhi_pm_state_str(cur_state));
		goto invalid_pm_state;
	}

	mhi_cntrl->dev_state = MHI_STATE_M2;
	mhi_set_mhi_state(mhi_cntrl, MHI_STATE_M2);
	write_unlock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->M2++;

	/* during M2 transition we cannot access DB registers must sleep */
	usleep_range(MHI_M2_DEBOUNCE_TMR_US, MHI_M2_DEBOUNCE_TMR_US + 50);
	write_lock_irq(&mhi_cntrl->pm_lock);

	/* during de-bounce time could be receiving M0 Event */
	if (mhi_cntrl->pm_state == MHI_PM_M1_M2_TRANSITION) {
		MHI_LOG("Entered M2 State\n");
		cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M2);
		if (unlikely(cur_state != MHI_PM_M2)) {
			MHI_ERR("Failed to transition to state %s from %s\n",
				to_mhi_pm_state_str(MHI_PM_M2),
				to_mhi_pm_state_str(cur_state));
			goto invalid_pm_state;
		}
	}
	write_unlock_irq(&mhi_cntrl->pm_lock);

	/* transfer pending, exit M2 */
	if (unlikely(atomic_read(&mhi_cntrl->dev_wake))) {
		MHI_VERB("Exiting M2 Immediately, count:%d\n",
			atomic_read(&mhi_cntrl->dev_wake));
		read_lock_bh(&mhi_cntrl->pm_lock);
		mhi_cntrl->wake_get(mhi_cntrl, true);
		mhi_cntrl->wake_put(mhi_cntrl, false);
		read_unlock_bh(&mhi_cntrl->pm_lock);
	} else
		mhi_cntrl->status_cb(mhi_cntrl, mhi_cntrl->priv_data,
				     MHI_CB_IDLE);

	mutex_unlock(&mhi_cntrl->pm_mutex);
	return;

invalid_pm_state:
	write_unlock_irq(&mhi_cntrl->pm_lock);
	mutex_unlock(&mhi_cntrl->pm_mutex);
}

void mhi_pm_m1_transition(struct mhi_controller *mhi_cntrl)
{
	enum MHI_PM_STATE state;

	write_lock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->dev_state = mhi_get_m_state(mhi_cntrl);
	if (mhi_cntrl->dev_state == MHI_STATE_M1) {
		state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M1);

		/* schedule M1->M2 transition */
		if (state == MHI_PM_M1) {
			schedule_work(&mhi_cntrl->m1_worker);
			mhi_cntrl->M1++;
		}
	}
	write_unlock_irq(&mhi_cntrl->pm_lock);
}

int mhi_pm_m3_transition(struct mhi_controller *mhi_cntrl)
{
	enum MHI_PM_STATE state;

	write_lock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->dev_state = MHI_STATE_M3;
	state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M3);
	write_unlock_irq(&mhi_cntrl->pm_lock);
	if (state != MHI_PM_M3) {
		MHI_ERR("Failed to transition to state %s from %s\n",
			to_mhi_pm_state_str(MHI_PM_M3),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}
	wake_up(&mhi_cntrl->state_event);
	mhi_cntrl->M3++;

	MHI_LOG("Entered mhi_state:%s pm_state:%s\n",
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		to_mhi_pm_state_str(mhi_cntrl->pm_state));
	return 0;
}

static int mhi_pm_amss_transition(struct mhi_controller *mhi_cntrl)
{
	int i;
	struct mhi_event *mhi_event;

	MHI_LOG("Processing AMSS Transition\n");

	write_lock_irq(&mhi_cntrl->pm_lock);
	mhi_cntrl->ee = MHI_EE_AMSS;
	write_unlock_irq(&mhi_cntrl->pm_lock);
	wake_up(&mhi_cntrl->state_event);

	/* add elements to all HW event rings */
	read_lock_bh(&mhi_cntrl->pm_lock);
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		read_unlock_bh(&mhi_cntrl->pm_lock);
		return -EIO;
	}

	MHI_LOG("mhi_db_hw_ring\n");
	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		struct mhi_ring *ring = &mhi_event->ring;

		if (mhi_event->offload_ev || !mhi_event->hw_ring)
			continue;

		ring->wp = ring->base + ring->len - ring->el_size;
		*ring->ctxt_wp = cpu_to_le64(ring->iommu_base + ring->len - ring->el_size);
		/* all ring updates must get updated immediately */
		smp_wmb();

		spin_lock_irq(&mhi_event->lock);
		if (MHI_DB_ACCESS_VALID(mhi_cntrl->pm_state))
			mhi_ring_er_db(mhi_event);
		spin_unlock_irq(&mhi_event->lock);

	}
	read_unlock_bh(&mhi_cntrl->pm_lock);

	MHI_LOG("Adding new devices\n");

	/* add supported devices */
	mhi_create_devices(mhi_cntrl);

	MHI_LOG("Exited\n");

	return 0;
}

/* handles both sys_err and shutdown transitions */
static void mhi_pm_disable_transition(struct mhi_controller *mhi_cntrl,
				      enum MHI_PM_STATE transition_state)
{
	enum MHI_PM_STATE cur_state, prev_state;
	struct mhi_event *mhi_event;
	struct mhi_cmd_ctxt *cmd_ctxt;
	struct mhi_cmd *mhi_cmd;
	struct mhi_event_ctxt *er_ctxt;
	int ret = 0, i;
	u32 regVal;

	MHI_LOG("Enter with from pm_state:%s MHI_STATE:%s to pm_state:%s\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state),
		to_mhi_pm_state_str(transition_state));

	mutex_lock(&mhi_cntrl->pm_mutex);
	write_lock_irq(&mhi_cntrl->pm_lock);
	prev_state = mhi_cntrl->pm_state;
	cur_state = mhi_tryset_pm_state(mhi_cntrl, transition_state);
	if (cur_state == transition_state) {
		mhi_cntrl->ee = MHI_EE_DISABLE_TRANSITION;
		mhi_cntrl->dev_state = MHI_STATE_RESET;
	}
	write_unlock_irq(&mhi_cntrl->pm_lock);

	/* not handling sys_err, could be middle of shut down */
	if (cur_state != transition_state) {
		MHI_LOG("Failed to transition to state:0x%x from:0x%x\n",
			transition_state, cur_state);
		mutex_unlock(&mhi_cntrl->pm_mutex);
		return;
	}

	/* trigger MHI RESET so device will not access host ddr */
	if (MHI_REG_ACCESS_VALID(prev_state)) {
		u32 in_reset = -1;
		u32 i;

		MHI_LOG("Trigger device into MHI_RESET\n");
		mhi_set_mhi_state(mhi_cntrl, MHI_STATE_RESET);

		/* wait for reset to be cleared */
		for (i = 0; i < mhi_cntrl->timeout_ms; i += 25) { //maybe miss msi interrupt
			in_reset = -1;
			ret = wait_event_timeout(mhi_cntrl->state_event,
						 mhi_read_reg_field(mhi_cntrl,
							mhi_cntrl->regs, MHICTRL,
							MHICTRL_RESET_MASK,
							MHICTRL_RESET_SHIFT, &in_reset)
							|| !in_reset, msecs_to_jiffies(25));
			if (in_reset == 0)
				break;
		}

		if ((!ret || in_reset) && cur_state == MHI_PM_SYS_ERR_PROCESS) {
			MHI_CRITICAL("Device failed to exit RESET state\n");
			mutex_unlock(&mhi_cntrl->pm_mutex);
			return;
		}

		/* Set the numbers of Event Rings supported */
		ret = mhi_read_reg_field(mhi_cntrl, mhi_cntrl->regs, MHICFG, MHICFG_NCH_MASK, MHICFG_NCH_SHIFT, &regVal);
		MHI_LOG("%d channels, ret=%d\n", regVal, ret);

		mhi_write_reg_field(mhi_cntrl, mhi_cntrl->regs, MHICFG, MHICFG_NER_MASK, MHICFG_NER_SHIFT, NUM_MHI_EVT_RINGS);
		/*
		 * device cleares INTVEC as part of RESET processing,
		 * re-program it
		 */
		mhi_write_reg(mhi_cntrl, mhi_cntrl->bhi, BHI_INTVEC, 0);
	}

	MHI_LOG("Waiting for all pending event ring processing to complete\n");
	mhi_event = mhi_cntrl->mhi_event;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		if (mhi_event->offload_ev)
			continue;
		tasklet_kill(&mhi_event->task);
	}

	MHI_LOG("Reset all active channels and remove mhi devices\n");
	device_for_each_child(mhi_cntrl->dev, NULL, mhi_destroy_device);

	MHI_LOG("Finish resetting channels\n");

	/* release lock and wait for all pending thread to complete */
	mutex_unlock(&mhi_cntrl->pm_mutex);
	MHI_LOG("Waiting for all pending threads to complete\n");
	wake_up(&mhi_cntrl->state_event);
	flush_work(&mhi_cntrl->m1_worker);
	flush_work(&mhi_cntrl->st_worker);
	flush_work(&mhi_cntrl->fw_worker);

	mutex_lock(&mhi_cntrl->pm_mutex);

	MHI_ASSERT(atomic_read(&mhi_cntrl->dev_wake), "dev_wake != 0");

	/* reset the ev rings and cmd rings */
	MHI_LOG("Resetting EV CTXT and CMD CTXT\n");
	mhi_cmd = mhi_cntrl->mhi_cmd;
	cmd_ctxt = mhi_cntrl->mhi_ctxt->cmd_ctxt;
	for (i = 0; i < NR_OF_CMD_RINGS; i++, mhi_cmd++, cmd_ctxt++) {
		struct mhi_ring *ring = &mhi_cmd->ring;

		ring->rp = ring->base;
		ring->wp = ring->base;
		cmd_ctxt->rp = cmd_ctxt->rbase;
		cmd_ctxt->wp = cmd_ctxt->rbase;
	}

	mhi_event = mhi_cntrl->mhi_event;
	er_ctxt = mhi_cntrl->mhi_ctxt->er_ctxt;
	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, er_ctxt++,
		     mhi_event++) {
		struct mhi_ring *ring = &mhi_event->ring;

		/* do not touch offload er */
		if (mhi_event->offload_ev)
			continue;

		ring->rp = ring->base;
		ring->wp = ring->base;
		er_ctxt->rp = er_ctxt->rbase;
		er_ctxt->wp = er_ctxt->rbase;
	}

	if (cur_state == MHI_PM_SYS_ERR_PROCESS) {
		mhi_ready_state_transition(mhi_cntrl);
	} else {
		/* move to disable state */
		write_lock_irq(&mhi_cntrl->pm_lock);
		cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_DISABLE);
		write_unlock_irq(&mhi_cntrl->pm_lock);
		if (unlikely(cur_state != MHI_PM_DISABLE))
			MHI_ERR("Error moving from pm state:%s to state:%s\n",
				to_mhi_pm_state_str(cur_state),
				to_mhi_pm_state_str(MHI_PM_DISABLE));
	}

	MHI_LOG("Exit with pm_state:%s mhi_state:%s\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state));

	mutex_unlock(&mhi_cntrl->pm_mutex);
}

int mhi_debugfs_trigger_reset(void *data, u64 val)
{
	struct mhi_controller *mhi_cntrl = data;
	enum MHI_PM_STATE cur_state;
	int ret;

	MHI_LOG("Trigger MHI Reset\n");

	/* exit lpm first */
	mhi_cntrl->runtime_get(mhi_cntrl, mhi_cntrl->priv_data);
	mhi_cntrl->runtime_put(mhi_cntrl, mhi_cntrl->priv_data);

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->dev_state == MHI_STATE_M0 ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("Did not enter M0 state, cur_state:%s pm_state:%s\n",
			TO_MHI_STATE_STR(mhi_cntrl->dev_state),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}

	write_lock_irq(&mhi_cntrl->pm_lock);
	cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_SYS_ERR_DETECT);
	write_unlock_irq(&mhi_cntrl->pm_lock);

	if (cur_state == MHI_PM_SYS_ERR_DETECT)
		schedule_work(&mhi_cntrl->syserr_worker);

	return 0;
}

/* queue a new work item and scheduler work */
int mhi_queue_state_transition(struct mhi_controller *mhi_cntrl,
			       enum MHI_ST_TRANSITION state)
{
	struct state_transition *item = kmalloc(sizeof(*item), GFP_ATOMIC);
	unsigned long flags;

	if (!item)
		return -ENOMEM;

	item->state = state;
	spin_lock_irqsave(&mhi_cntrl->transition_lock, flags);
	list_add_tail(&item->node, &mhi_cntrl->transition_list);
	spin_unlock_irqrestore(&mhi_cntrl->transition_lock, flags);

	schedule_work(&mhi_cntrl->st_worker);

	return 0;
}

void mhi_pm_sys_err_worker(struct work_struct *work)
{
	struct mhi_controller *mhi_cntrl = container_of(work,
							struct mhi_controller,
							syserr_worker);

	MHI_LOG("Enter with pm_state:%s MHI_STATE:%s\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state));

	mhi_pm_disable_transition(mhi_cntrl, MHI_PM_SYS_ERR_PROCESS);
}

void mhi_pm_st_worker(struct work_struct *work)
{
	struct state_transition *itr, *tmp;
	LIST_HEAD(head);
	struct mhi_controller *mhi_cntrl = container_of(work,
							struct mhi_controller,
							st_worker);
	spin_lock_irq(&mhi_cntrl->transition_lock);
	list_splice_tail_init(&mhi_cntrl->transition_list, &head);
	spin_unlock_irq(&mhi_cntrl->transition_lock);

	list_for_each_entry_safe(itr, tmp, &head, node) {
		list_del(&itr->node);
		MHI_LOG("Transition to state:%s\n",
			TO_MHI_STATE_TRANS_STR(itr->state));

		if (mhi_cntrl->ee != mhi_get_exec_env(mhi_cntrl)) {
			MHI_ERR("%s -> %s\n", TO_MHI_EXEC_STR(mhi_cntrl->ee),
				TO_MHI_EXEC_STR(mhi_get_exec_env(mhi_cntrl)));
		}

		switch (itr->state) {
		case MHI_ST_TRANSITION_PBL:
			write_lock_irq(&mhi_cntrl->pm_lock);
			if (MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state))
				mhi_cntrl->ee = mhi_get_exec_env(mhi_cntrl);
			write_unlock_irq(&mhi_cntrl->pm_lock);
			if (MHI_IN_PBL(mhi_cntrl->ee))
				wake_up(&mhi_cntrl->state_event);
			break;
		case MHI_ST_TRANSITION_READY:
			mhi_ready_state_transition(mhi_cntrl);
			break;
		case MHI_ST_TRANSITION_SBL:
			write_lock_irq(&mhi_cntrl->pm_lock);
			mhi_cntrl->ee = MHI_EE_SBL;
			write_unlock_irq(&mhi_cntrl->pm_lock);
			mhi_create_devices(mhi_cntrl);
			break;
		case MHI_ST_TRANSITION_AMSS:
			mhi_pm_amss_transition(mhi_cntrl);
			break;
		case MHI_ST_TRANSITION_FP:
			write_lock_irq(&mhi_cntrl->pm_lock);
			mhi_cntrl->ee = MHI_EE_FP;
			write_unlock_irq(&mhi_cntrl->pm_lock);
			wake_up(&mhi_cntrl->state_event);
			mhi_create_devices(mhi_cntrl);
			break;
		default:
			break;
		}
		kfree(itr);
	}
}

int mhi_async_power_up(struct mhi_controller *mhi_cntrl)
{
	int ret;
	u32 bhi_offset;
	enum MHI_EE current_ee;
	enum MHI_ST_TRANSITION next_state;
	u32 mhi_cfg = 0xFFFFFFFF;
	u32 mhi_timeout = 10;
	enum MHI_STATE mhiDevState;

	MHI_LOG("Requested to power on\n");

//# echo 1 > /sys/module/ep_pcie_core/parameters/debug_mask
//# echo 3 > /sys/kernel/debug/pcie-ep/case
//in sdx20 mimo offset is 0x100
//ep_pcie_reg_dump: 0x0100 00000100 00000000 01000000 b8efc7ae 00010880 ecd23c0b 00000300 00000000
	while (mhi_cfg == 0xFFFFFFFF && mhi_timeout != 0) { //refer to MhiInitNewDev
		ret = mhi_read_reg(mhi_cntrl, mhi_cntrl->regs, MHICFG, &mhi_cfg);
		if (ret) {

		}
		MHI_LOG("mhi_cfg = 0x%x\n", mhi_cfg);
		msleep(50);
		mhi_timeout--;
	}
	if (mhi_cfg == 0xFFFFFFFF)
		return EBUSY;

	mhiDevState = mhi_get_m_state(mhi_cntrl);
	MHI_LOG("mhi_state = %s\n", mhi_state_str[mhiDevState]);

	 if (mhiDevState >= MHI_STATE_M0) {
		MHI_LOG("Trigger device into MHI_RESET\n");
		mhi_set_mhi_state(mhi_cntrl, MHI_STATE_RESET);
		msleep(50);
		mhiDevState = mhi_get_m_state(mhi_cntrl);
		MHI_LOG("mhi_state = %s\n", mhi_state_str[mhiDevState]);
	 }

	/* set to default wake if not set */
	if (!mhi_cntrl->wake_get || !mhi_cntrl->wake_put) {
		mhi_cntrl->wake_get = mhi_assert_dev_wake;
		mhi_cntrl->wake_put = mhi_deassert_dev_wake;
	}

	mutex_lock(&mhi_cntrl->pm_mutex);
	mhi_cntrl->pm_state = MHI_PM_DISABLE;

	if (!mhi_cntrl->pre_init) {
		/* setup device context */
		ret = mhi_init_dev_ctxt(mhi_cntrl);
		if (ret) {
			MHI_ERR("Error setting dev_context\n");
			goto error_dev_ctxt;
		}

		ret = mhi_init_irq_setup(mhi_cntrl);
		if (ret) {
			MHI_ERR("Error setting up irq\n");
			goto error_setup_irq;
		}
	}

	/* setup bhi offset & intvec */
	write_lock_irq(&mhi_cntrl->pm_lock);
	ret = mhi_read_reg(mhi_cntrl, mhi_cntrl->regs, BHIOFF, &bhi_offset);
	if (ret) {
		write_unlock_irq(&mhi_cntrl->pm_lock);
		MHI_ERR("Error getting bhi offset\n");
		goto error_bhi_offset;
	}

	MHI_LOG("bhi_offset = 0x%x\n", bhi_offset); //this should be 0x100, in sdx20, bhi offset is 0x200
	mhi_cntrl->bhi = mhi_cntrl->regs + bhi_offset;
	mhi_write_reg(mhi_cntrl, mhi_cntrl->bhi, BHI_INTVEC, 0);
	mhi_cntrl->pm_state = MHI_PM_POR;

        mhi_timeout = 30;
        while ((current_ee = mhi_get_exec_env(mhi_cntrl)) != MHI_EE_AMSS)
        {
            if (current_ee < MHI_EE_MAX)
            {
                MHI_LOG("wait for ee = %s\n", mhi_ee_str[current_ee]);
            }
            
            msleep(500);
            mhi_timeout--;
            if (0 == mhi_timeout)
            {
                break;
            }
        }
        
	mhi_cntrl->ee = mhi_get_exec_env(mhi_cntrl);
	current_ee = mhi_get_exec_env(mhi_cntrl);
	write_unlock_irq(&mhi_cntrl->pm_lock);

	MHI_LOG("current_ee = %s\n", mhi_ee_str[current_ee]);

	/* confirm device is in valid exec env */
	if (!MHI_IN_PBL(current_ee) && current_ee != MHI_EE_AMSS) {
		MHI_ERR("Not a valid ee for power on\n");
		ret = -EIO;
		goto error_bhi_offset;
	}

	/* transition to next state */
	next_state = MHI_IN_PBL(current_ee) ?
		MHI_ST_TRANSITION_PBL : MHI_ST_TRANSITION_READY;

	mhi_queue_state_transition(mhi_cntrl, next_state);

	mhi_init_debugfs(mhi_cntrl);
	mhi_cntrl_register_miscdev(mhi_cntrl);

	mutex_unlock(&mhi_cntrl->pm_mutex);

	MHI_LOG("Power on setup success\n");


	return 0;

error_bhi_offset:
	if (!mhi_cntrl->pre_init)
		mhi_deinit_free_irq(mhi_cntrl);

error_setup_irq:
	if (!mhi_cntrl->pre_init)
		mhi_deinit_dev_ctxt(mhi_cntrl);

error_dev_ctxt:
	mutex_unlock(&mhi_cntrl->pm_mutex);

	return ret;
}
EXPORT_SYMBOL(mhi_async_power_up);

void mhi_power_down(struct mhi_controller *mhi_cntrl, bool graceful)
{
	enum MHI_PM_STATE cur_state;
	MHI_LOG("enter\n");

	/* if it's not graceful shutdown, force MHI to a linkdown state */
	if (!graceful) {
		mutex_lock(&mhi_cntrl->pm_mutex);
		write_lock_irq(&mhi_cntrl->pm_lock);
		cur_state = mhi_tryset_pm_state(mhi_cntrl,
						MHI_PM_LD_ERR_FATAL_DETECT);
		write_unlock_irq(&mhi_cntrl->pm_lock);
		mutex_unlock(&mhi_cntrl->pm_mutex);
		if (cur_state != MHI_PM_LD_ERR_FATAL_DETECT)
			MHI_ERR("Failed to move to state:%s from:%s\n",
				to_mhi_pm_state_str(MHI_PM_LD_ERR_FATAL_DETECT),
				to_mhi_pm_state_str(mhi_cntrl->pm_state));

		mhi_pm_disable_transition(mhi_cntrl, MHI_PM_SHUTDOWN_PROCESS);
	}
	else {
		device_for_each_child(mhi_cntrl->dev, NULL, mhi_destroy_device);
	}

	mhi_cntrl_deregister_miscdev(mhi_cntrl);
	mhi_deinit_debugfs(mhi_cntrl);

	if (!mhi_cntrl->pre_init) {
		/* free all allocated resources */
		if (mhi_cntrl->fbc_image) {
			mhi_free_bhie_table(mhi_cntrl, mhi_cntrl->fbc_image);
			mhi_cntrl->fbc_image = NULL;
		}
		mhi_deinit_free_irq(mhi_cntrl);
		mhi_deinit_dev_ctxt(mhi_cntrl);
	}

}
EXPORT_SYMBOL(mhi_power_down);

int mhi_sync_power_up(struct mhi_controller *mhi_cntrl)
{
	int ret = mhi_async_power_up(mhi_cntrl);

	if (ret)
		return ret;

	wait_event_timeout(mhi_cntrl->state_event,
			   mhi_cntrl->ee == MHI_EE_AMSS ||
			   MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
			   msecs_to_jiffies(mhi_cntrl->timeout_ms));

	return (mhi_cntrl->ee == MHI_EE_AMSS) ? 0 : -EIO;
}
EXPORT_SYMBOL(mhi_sync_power_up);

int mhi_pm_suspend(struct mhi_controller *mhi_cntrl)
{
	int ret;
	enum MHI_PM_STATE new_state;
	struct mhi_chan *itr, *tmp;

	if (mhi_cntrl->pm_state == MHI_PM_DISABLE)
		return -EINVAL;

	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		return -EIO;

	/* do a quick check to see if any pending data, then exit */
	if (atomic_read(&mhi_cntrl->dev_wake)) {
		MHI_VERB("Busy, aborting M3\n");
		return -EBUSY;
	}

	/* exit MHI out of M2 state */
	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_get(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->dev_state == MHI_STATE_M0 ||
				 mhi_cntrl->dev_state == MHI_STATE_M1 ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR(
			"Did not enter M0||M1 state, cur_state:%s pm_state:%s\n",
			TO_MHI_STATE_STR(mhi_cntrl->dev_state),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}

	write_lock_irq(&mhi_cntrl->pm_lock);

	if (atomic_read(&mhi_cntrl->dev_wake)) {
		MHI_VERB("Busy, aborting M3\n");
		write_unlock_irq(&mhi_cntrl->pm_lock);
		return -EBUSY;
	}

	/* anytime after this, we will resume thru runtime pm framework */
	MHI_LOG("Allowing M3 transition\n");
	new_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M3_ENTER);
	if (new_state != MHI_PM_M3_ENTER) {
		write_unlock_irq(&mhi_cntrl->pm_lock);
		MHI_ERR("Error setting to pm_state:%s from pm_state:%s\n",
			to_mhi_pm_state_str(MHI_PM_M3_ENTER),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}

	/* set dev to M3 and wait for completion */
	mhi_set_mhi_state(mhi_cntrl, MHI_STATE_M3);
	write_unlock_irq(&mhi_cntrl->pm_lock);
	MHI_LOG("Wait for M3 completion\n");

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->dev_state == MHI_STATE_M3 ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("Did not enter M3 state, cur_state:%s pm_state:%s\n",
			TO_MHI_STATE_STR(mhi_cntrl->dev_state),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}

	/* notify any clients we enter lpm */
	list_for_each_entry_safe(itr, tmp, &mhi_cntrl->lpm_chans, node) {
		mutex_lock(&itr->mutex);
		if (itr->mhi_dev)
			mhi_notify(itr->mhi_dev, MHI_CB_LPM_ENTER);
		mutex_unlock(&itr->mutex);
	}

	return 0;
}
EXPORT_SYMBOL(mhi_pm_suspend);

int mhi_pm_resume(struct mhi_controller *mhi_cntrl)
{
	enum MHI_PM_STATE cur_state;
	int ret;
	struct mhi_chan *itr, *tmp;

	MHI_LOG("Entered with pm_state:%s dev_state:%s\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_STATE_STR(mhi_cntrl->dev_state));

	if (mhi_cntrl->pm_state == MHI_PM_DISABLE)
		return 0;

	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		return -EIO;

	MHI_ASSERT(mhi_cntrl->pm_state != MHI_PM_M3, "mhi_pm_state != M3");

	/* notify any clients we enter lpm */
	list_for_each_entry_safe(itr, tmp, &mhi_cntrl->lpm_chans, node) {
		mutex_lock(&itr->mutex);
		if (itr->mhi_dev)
			mhi_notify(itr->mhi_dev, MHI_CB_LPM_EXIT);
		mutex_unlock(&itr->mutex);
	}

	write_lock_irq(&mhi_cntrl->pm_lock);
	cur_state = mhi_tryset_pm_state(mhi_cntrl, MHI_PM_M3_EXIT);
	if (cur_state != MHI_PM_M3_EXIT) {
		write_unlock_irq(&mhi_cntrl->pm_lock);
		MHI_ERR("Error setting to pm_state:%s from pm_state:%s\n",
			to_mhi_pm_state_str(MHI_PM_M3_EXIT),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}

	/* set dev to M0 and wait for completion */
	mhi_set_mhi_state(mhi_cntrl, MHI_STATE_M0);
	write_unlock_irq(&mhi_cntrl->pm_lock);

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->dev_state == MHI_STATE_M0 ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("Did not enter M0 state, cur_state:%s pm_state:%s\n",
			TO_MHI_STATE_STR(mhi_cntrl->dev_state),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		return -EIO;
	}

	return 0;
}

static int __mhi_device_get_sync(struct mhi_controller *mhi_cntrl)
{
	int ret;

	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_get(mhi_cntrl, false);
	if (MHI_PM_IN_SUSPEND_STATE(mhi_cntrl->pm_state)) {
		mhi_cntrl->runtime_get(mhi_cntrl, mhi_cntrl->priv_data);
		mhi_cntrl->runtime_put(mhi_cntrl, mhi_cntrl->priv_data);
	}
	read_unlock_bh(&mhi_cntrl->pm_lock);

	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->dev_state == MHI_STATE_M0 ||
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state),
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));

	if (!ret || MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state)) {
		MHI_ERR("Did not enter M0 state, cur_state:%s pm_state:%s\n",
			TO_MHI_STATE_STR(mhi_cntrl->dev_state),
			to_mhi_pm_state_str(mhi_cntrl->pm_state));
		read_lock_bh(&mhi_cntrl->pm_lock);
		mhi_cntrl->wake_put(mhi_cntrl, false);
		read_unlock_bh(&mhi_cntrl->pm_lock);
		return -EIO;
	}

	return 0;
}

void mhi_device_get(struct mhi_device *mhi_dev)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;

	atomic_inc(&mhi_dev->dev_wake);
	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_get(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);
}
EXPORT_SYMBOL(mhi_device_get);

int mhi_device_get_sync(struct mhi_device *mhi_dev)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;
	int ret;

	ret = __mhi_device_get_sync(mhi_cntrl);
	if (!ret)
		atomic_inc(&mhi_dev->dev_wake);

	return ret;
}
EXPORT_SYMBOL(mhi_device_get_sync);

void mhi_device_put(struct mhi_device *mhi_dev)
{
	struct mhi_controller *mhi_cntrl = mhi_dev->mhi_cntrl;

	atomic_dec(&mhi_dev->dev_wake);
	read_lock_bh(&mhi_cntrl->pm_lock);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	read_unlock_bh(&mhi_cntrl->pm_lock);
}
EXPORT_SYMBOL(mhi_device_put);

int mhi_force_rddm_mode(struct mhi_controller *mhi_cntrl)
{
	int ret;

	MHI_LOG("Enter with pm_state:%s ee:%s\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_EXEC_STR(mhi_cntrl->ee));

	/* before rddm mode, we need to enter M0 state */
	ret = __mhi_device_get_sync(mhi_cntrl);
	if (ret)
		return ret;

	mutex_lock(&mhi_cntrl->pm_mutex);
	write_lock_irq(&mhi_cntrl->pm_lock);
	if (!MHI_REG_ACCESS_VALID(mhi_cntrl->pm_state))
		goto no_reg_access;

	MHI_LOG("Triggering SYS_ERR to force rddm state\n");

	mhi_set_mhi_state(mhi_cntrl, MHI_STATE_SYS_ERR);
	mhi_cntrl->wake_put(mhi_cntrl, false);
	write_unlock_irq(&mhi_cntrl->pm_lock);
	mutex_unlock(&mhi_cntrl->pm_mutex);

	/* wait for rddm event */
	MHI_LOG("Waiting for device to enter RDDM state\n");
	ret = wait_event_timeout(mhi_cntrl->state_event,
				 mhi_cntrl->ee == MHI_EE_RDDM,
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));
	ret = !ret ? 0 : -EIO;

	MHI_LOG("Exiting with pm_state:%s ee:%s ret:%d\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state),
		TO_MHI_EXEC_STR(mhi_cntrl->ee), ret);

	return ret;

no_reg_access:
	mhi_cntrl->wake_put(mhi_cntrl, false);
	write_unlock_irq(&mhi_cntrl->pm_lock);
	mutex_unlock(&mhi_cntrl->pm_mutex);

	return -EIO;
}
EXPORT_SYMBOL(mhi_force_rddm_mode);
