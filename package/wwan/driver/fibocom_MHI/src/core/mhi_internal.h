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

#ifndef _MHI_INT_H
#define _MHI_INT_H

#include <linux/version.h>
#ifndef writel_relaxed
#define writel_relaxed writel
#endif

#ifndef U32_MAX
#define U32_MAX		((u32)~0U)
#endif

#if (LINUX_VERSION_CODE <= KERNEL_VERSION( 3,10,108 ))
static inline void reinit_completion(struct completion *x)
{
	x->done = 0;
}
#endif

extern struct bus_type mhi_bus_type;

/* MHI mmio register mapping */
#define PCI_INVALID_READ(val) (val == U32_MAX)

#define MHIREGLEN (0x0)
#define MHIREGLEN_MHIREGLEN_MASK (0xFFFFFFFF)
#define MHIREGLEN_MHIREGLEN_SHIFT (0)

#define MHIVER (0x8)
#define MHIVER_MHIVER_MASK (0xFFFFFFFF)
#define MHIVER_MHIVER_SHIFT (0)

#define MHICFG (0x10)
#define MHICFG_NHWER_MASK (0xFF000000)
#define MHICFG_NHWER_SHIFT (24)
#define MHICFG_NER_MASK (0xFF0000)
#define MHICFG_NER_SHIFT (16)
#define MHICFG_NHWCH_MASK (0xFF00)
#define MHICFG_NHWCH_SHIFT (8)
#define MHICFG_NCH_MASK (0xFF)
#define MHICFG_NCH_SHIFT (0)

#define CHDBOFF (0x18)
#define CHDBOFF_CHDBOFF_MASK (0xFFFFFFFF)
#define CHDBOFF_CHDBOFF_SHIFT (0)

#define ERDBOFF (0x20)
#define ERDBOFF_ERDBOFF_MASK (0xFFFFFFFF)
#define ERDBOFF_ERDBOFF_SHIFT (0)

#define BHIOFF (0x28)
#define BHIOFF_BHIOFF_MASK (0xFFFFFFFF)
#define BHIOFF_BHIOFF_SHIFT (0)

#define DEBUGOFF (0x30)
#define DEBUGOFF_DEBUGOFF_MASK (0xFFFFFFFF)
#define DEBUGOFF_DEBUGOFF_SHIFT (0)

#define MHICTRL (0x38)
#define MHICTRL_MHISTATE_MASK (0x0000FF00)
#define MHICTRL_MHISTATE_SHIFT (8)
#define MHICTRL_RESET_MASK (0x2)
#define MHICTRL_RESET_SHIFT (1)

#define MHISTATUS (0x48)
#define MHISTATUS_MHISTATE_MASK (0x0000FF00)
#define MHISTATUS_MHISTATE_SHIFT (8)
#define MHISTATUS_SYSERR_MASK (0x4)
#define MHISTATUS_SYSERR_SHIFT (2)
#define MHISTATUS_READY_MASK (0x1)
#define MHISTATUS_READY_SHIFT (0)

#define CCABAP_LOWER (0x58)
#define CCABAP_LOWER_CCABAP_LOWER_MASK (0xFFFFFFFF)
#define CCABAP_LOWER_CCABAP_LOWER_SHIFT (0)

#define CCABAP_HIGHER (0x5C)
#define CCABAP_HIGHER_CCABAP_HIGHER_MASK (0xFFFFFFFF)
#define CCABAP_HIGHER_CCABAP_HIGHER_SHIFT (0)

#define ECABAP_LOWER (0x60)
#define ECABAP_LOWER_ECABAP_LOWER_MASK (0xFFFFFFFF)
#define ECABAP_LOWER_ECABAP_LOWER_SHIFT (0)

#define ECABAP_HIGHER (0x64)
#define ECABAP_HIGHER_ECABAP_HIGHER_MASK (0xFFFFFFFF)
#define ECABAP_HIGHER_ECABAP_HIGHER_SHIFT (0)

#define CRCBAP_LOWER (0x68)
#define CRCBAP_LOWER_CRCBAP_LOWER_MASK (0xFFFFFFFF)
#define CRCBAP_LOWER_CRCBAP_LOWER_SHIFT (0)

#define CRCBAP_HIGHER (0x6C)
#define CRCBAP_HIGHER_CRCBAP_HIGHER_MASK (0xFFFFFFFF)
#define CRCBAP_HIGHER_CRCBAP_HIGHER_SHIFT (0)

#define CRDB_LOWER (0x70)
#define CRDB_LOWER_CRDB_LOWER_MASK (0xFFFFFFFF)
#define CRDB_LOWER_CRDB_LOWER_SHIFT (0)

#define CRDB_HIGHER (0x74)
#define CRDB_HIGHER_CRDB_HIGHER_MASK (0xFFFFFFFF)
#define CRDB_HIGHER_CRDB_HIGHER_SHIFT (0)

#define MHICTRLBASE_LOWER (0x80)
#define MHICTRLBASE_LOWER_MHICTRLBASE_LOWER_MASK (0xFFFFFFFF)
#define MHICTRLBASE_LOWER_MHICTRLBASE_LOWER_SHIFT (0)

#define MHICTRLBASE_HIGHER (0x84)
#define MHICTRLBASE_HIGHER_MHICTRLBASE_HIGHER_MASK (0xFFFFFFFF)
#define MHICTRLBASE_HIGHER_MHICTRLBASE_HIGHER_SHIFT (0)

#define MHICTRLLIMIT_LOWER (0x88)
#define MHICTRLLIMIT_LOWER_MHICTRLLIMIT_LOWER_MASK (0xFFFFFFFF)
#define MHICTRLLIMIT_LOWER_MHICTRLLIMIT_LOWER_SHIFT (0)

#define MHICTRLLIMIT_HIGHER (0x8C)
#define MHICTRLLIMIT_HIGHER_MHICTRLLIMIT_HIGHER_MASK (0xFFFFFFFF)
#define MHICTRLLIMIT_HIGHER_MHICTRLLIMIT_HIGHER_SHIFT (0)

#define MHIDATABASE_LOWER (0x98)
#define MHIDATABASE_LOWER_MHIDATABASE_LOWER_MASK (0xFFFFFFFF)
#define MHIDATABASE_LOWER_MHIDATABASE_LOWER_SHIFT (0)

#define MHIDATABASE_HIGHER (0x9C)
#define MHIDATABASE_HIGHER_MHIDATABASE_HIGHER_MASK (0xFFFFFFFF)
#define MHIDATABASE_HIGHER_MHIDATABASE_HIGHER_SHIFT (0)

#define MHIDATALIMIT_LOWER (0xA0)
#define MHIDATALIMIT_LOWER_MHIDATALIMIT_LOWER_MASK (0xFFFFFFFF)
#define MHIDATALIMIT_LOWER_MHIDATALIMIT_LOWER_SHIFT (0)

#define MHIDATALIMIT_HIGHER (0xA4)
#define MHIDATALIMIT_HIGHER_MHIDATALIMIT_HIGHER_MASK (0xFFFFFFFF)
#define MHIDATALIMIT_HIGHER_MHIDATALIMIT_HIGHER_SHIFT (0)

/* MHI BHI offfsets */
#define BHI_BHIVERSION_MINOR (0x00)
#define BHI_BHIVERSION_MAJOR (0x04)
#define BHI_IMGADDR_LOW (0x08)
#define BHI_IMGADDR_HIGH (0x0C)
#define BHI_IMGSIZE (0x10)
#define BHI_RSVD1 (0x14)
#define BHI_IMGTXDB (0x18)
#define BHI_TXDB_SEQNUM_BMSK (0x3FFFFFFF)
#define BHI_TXDB_SEQNUM_SHFT (0)
#define BHI_RSVD2 (0x1C)
#define BHI_INTVEC (0x20)
#define BHI_RSVD3 (0x24)
#define BHI_EXECENV (0x28)
#define BHI_STATUS (0x2C)
#define BHI_ERRCODE (0x30)
#define BHI_ERRDBG1 (0x34)
#define BHI_ERRDBG2 (0x38)
#define BHI_ERRDBG3 (0x3C)
#define BHI_SERIALNUM ( 0x40 )
#define BHI_SERIALNU (0x40)
#define BHI_SBLANTIROLLVER (0x44)
#define BHI_NUMSEG (0x48)
#define BHI_MSMHWID(n) (0x4C + (0x4 * n))
#define BHI_OEMPKHASH(n) (0x64 + (0x4 * n))
#define BHI_RSVD5 (0xC4)
#define BHI_STATUS_MASK (0xC0000000)
#define BHI_STATUS_SHIFT (30)
#define BHI_STATUS_ERROR (3)
#define BHI_STATUS_SUCCESS (2)
#define BHI_STATUS_RESET (0)

/* MHI BHIE offsets */
#define BHIE_OFFSET (0x0124) /* BHIE register space offset from BHI base */
#define BHIE_MSMSOCID_OFFS (BHIE_OFFSET + 0x0000)
#define BHIE_TXVECADDR_LOW_OFFS (BHIE_OFFSET + 0x002C)
#define BHIE_TXVECADDR_HIGH_OFFS (BHIE_OFFSET + 0x0030)
#define BHIE_TXVECSIZE_OFFS (BHIE_OFFSET + 0x0034)
#define BHIE_TXVECDB_OFFS (BHIE_OFFSET + 0x003C)
#define BHIE_TXVECDB_SEQNUM_BMSK (0x3FFFFFFF)
#define BHIE_TXVECDB_SEQNUM_SHFT (0)
#define BHIE_TXVECSTATUS_OFFS (BHIE_OFFSET + 0x0044)
#define BHIE_TXVECSTATUS_SEQNUM_BMSK (0x3FFFFFFF)
#define BHIE_TXVECSTATUS_SEQNUM_SHFT (0)
#define BHIE_TXVECSTATUS_STATUS_BMSK (0xC0000000)
#define BHIE_TXVECSTATUS_STATUS_SHFT (30)
#define BHIE_TXVECSTATUS_STATUS_RESET (0x00)
#define BHIE_TXVECSTATUS_STATUS_XFER_COMPL (0x02)
#define BHIE_TXVECSTATUS_STATUS_ERROR (0x03)
#define BHIE_RXVECADDR_LOW_OFFS (BHIE_OFFSET + 0x0060)
#define BHIE_RXVECADDR_HIGH_OFFS (BHIE_OFFSET + 0x0064)
#define BHIE_RXVECSIZE_OFFS (BHIE_OFFSET + 0x0068)
#define BHIE_RXVECDB_OFFS (BHIE_OFFSET + 0x0070)
#define BHIE_RXVECDB_SEQNUM_BMSK (0x3FFFFFFF)
#define BHIE_RXVECDB_SEQNUM_SHFT (0)
#define BHIE_RXVECSTATUS_OFFS (BHIE_OFFSET + 0x0078)
#define BHIE_RXVECSTATUS_SEQNUM_BMSK (0x3FFFFFFF)
#define BHIE_RXVECSTATUS_SEQNUM_SHFT (0)
#define BHIE_RXVECSTATUS_STATUS_BMSK (0xC0000000)
#define BHIE_RXVECSTATUS_STATUS_SHFT (30)
#define BHIE_RXVECSTATUS_STATUS_RESET (0x00)
#define BHIE_RXVECSTATUS_STATUS_XFER_COMPL (0x02)
#define BHIE_RXVECSTATUS_STATUS_ERROR (0x03)

struct __packed mhi_event_ctxt {
	u32 reserved : 8;
	u32 intmodc : 8;
	u32 intmodt : 16;
	u32 ertype;
	u32 msivec;
	u64 rbase;
	u64 rlen;
	u64 rp;
	u64 wp;
};

struct __packed mhi_chan_ctxt {
	u32 chstate : 8;
	u32 brstmode : 2;
	u32 pollcfg : 6;
	u32 reserved : 16;
	u32 chtype;
	u32 erindex;
	u64 rbase;
	u64 rlen;
	u64 rp;
	u64 wp;
};

struct __packed mhi_cmd_ctxt {
	u32 reserved0;
	u32 reserved1;
	u32 reserved2;
	u64 rbase;
	u64 rlen;
	u64 rp;
	u64 wp;
};

struct __packed mhi_tre {
	u64 ptr;
	u32 dword[2];
};

struct __packed bhi_vec_entry {
	u64 dma_addr;
	u64 size;
};

/* no operation command */
#define MHI_TRE_CMD_NOOP_PTR cpu_to_le64(0)
#define MHI_TRE_CMD_NOOP_DWORD0 cpu_to_le32(0)
#define MHI_TRE_CMD_NOOP_DWORD1 cpu_to_le32(1 << 16)

/* channel reset command */
#define MHI_TRE_CMD_RESET_PTR cpu_to_le64(0)
#define MHI_TRE_CMD_RESET_DWORD0 cpu_to_le32(0)
#define MHI_TRE_CMD_RESET_DWORD1(chid) cpu_to_le32((chid << 24) | (16 << 16))

/* channel stop command */
#define MHI_TRE_CMD_STOP_PTR cpu_to_le64(0)
#define MHI_TRE_CMD_STOP_DWORD0 cpu_to_le32(0)
#define MHI_TRE_CMD_STOP_DWORD1(chid) cpu_to_le32((chid << 24) | (17 << 16))

/* channel start command */
#define MHI_TRE_CMD_START_PTR cpu_to_le64(0)
#define MHI_TRE_CMD_START_DWORD0 cpu_to_le32(0)
#define MHI_TRE_CMD_START_DWORD1(chid) cpu_to_le32((chid << 24) | (18 << 16))

#define MHI_TRE_GET_CMD_CHID(tre) ((le32_to_cpu((tre)->dword[1]) >> 24) & 0xFF)

/* event descriptor macros */
//#define MHI_TRE_EV_PTR(ptr) (ptr)
//#define MHI_TRE_EV_DWORD0(code, len) ((code << 24) | len)
#define MHI_TRE_EV_DWORD1(chid, type) cpu_to_le32((chid << 24) | (type << 16))
#define MHI_TRE_GET_EV_PTR(tre) le64_to_cpu((tre)->ptr)
#define MHI_TRE_GET_EV_CODE(tre) ((le32_to_cpu((tre)->dword[0]) >> 24) & 0xFF)
#define MHI_TRE_GET_EV_LEN(tre) (le32_to_cpu((tre)->dword[0]) & 0xFFFF)
#define MHI_TRE_GET_EV_CHID(tre) ((le32_to_cpu((tre)->dword[1]) >> 24) & 0xFF)
#define MHI_TRE_GET_EV_TYPE(tre) ((le32_to_cpu((tre)->dword[1]) >> 16) & 0xFF)
#define MHI_TRE_GET_EV_STATE(tre) ((le32_to_cpu((tre)->dword[0]) >> 24) & 0xFF)
#define MHI_TRE_GET_EV_EXECENV(tre) ((le32_to_cpu((tre)->dword[0]) >> 24) & 0xFF)


/* transfer descriptor macros */
#define MHI_TRE_DATA_PTR(ptr) cpu_to_le64(ptr)
#define MHI_TRE_DATA_DWORD0(len) cpu_to_le32(len & MHI_MAX_MTU)
#define MHI_TRE_DATA_DWORD1(bei, ieot, ieob, chain) cpu_to_le32((2 << 16) | (bei << 10) \
	| (ieot << 9) | (ieob << 8) | chain)

enum MHI_CMD {
	MHI_CMD_NOOP = 0x0,
	MHI_CMD_RESET_CHAN = 0x1,
	MHI_CMD_STOP_CHAN = 0x2,
	MHI_CMD_START_CHAN = 0x3,
	MHI_CMD_RESUME_CHAN = 0x4,
};

enum MHI_PKT_TYPE {
	MHI_PKT_TYPE_INVALID = 0x0,
	MHI_PKT_TYPE_NOOP_CMD = 0x1,
	MHI_PKT_TYPE_TRANSFER = 0x2,
	MHI_PKT_TYPE_RESET_CHAN_CMD = 0x10,
	MHI_PKT_TYPE_STOP_CHAN_CMD = 0x11,
	MHI_PKT_TYPE_START_CHAN_CMD = 0x12,
	MHI_PKT_TYPE_STATE_CHANGE_EVENT = 0x20,
	MHI_PKT_TYPE_CMD_COMPLETION_EVENT = 0x21,
	MHI_PKT_TYPE_TX_EVENT = 0x22,
	MHI_PKT_TYPE_EE_EVENT = 0x40,
	MHI_PKT_TYPE_STALE_EVENT, /* internal event */
};

/* MHI transfer completion events */
enum MHI_EV_CCS {
	MHI_EV_CC_INVALID = 0x0,
	MHI_EV_CC_SUCCESS = 0x1,
	MHI_EV_CC_EOT = 0x2,
	MHI_EV_CC_OVERFLOW = 0x3,
	MHI_EV_CC_EOB = 0x4,
	MHI_EV_CC_OOB = 0x5,
	MHI_EV_CC_DB_MODE = 0x6,
	MHI_EV_CC_UNDEFINED_ERR = 0x10,
	MHI_EV_CC_BAD_TRE = 0x11,
};

enum MHI_CH_STATE {
	MHI_CH_STATE_DISABLED = 0x0,
	MHI_CH_STATE_ENABLED = 0x1,
	MHI_CH_STATE_RUNNING = 0x2,
	MHI_CH_STATE_SUSPENDED = 0x3,
	MHI_CH_STATE_STOP = 0x4,
	MHI_CH_STATE_ERROR = 0x5,
};

enum MHI_CH_CFG {
	MHI_CH_CFG_CHAN_ID = 0,
	MHI_CH_CFG_ELEMENTS = 1,
	MHI_CH_CFG_ER_INDEX = 2,
	MHI_CH_CFG_DIRECTION = 3,
	MHI_CH_CFG_BRSTMODE = 4,
	MHI_CH_CFG_POLLCFG = 5,
	MHI_CH_CFG_EE = 6,
	MHI_CH_CFG_XFER_TYPE = 7,
	MHI_CH_CFG_BITCFG = 8,
	MHI_CH_CFG_MAX
};

#define MHI_CH_CFG_BIT_LPM_NOTIFY BIT(0) /* require LPM notification */
#define MHI_CH_CFG_BIT_OFFLOAD_CH BIT(1) /* satellite mhi devices */
#define MHI_CH_CFG_BIT_DBMODE_RESET_CH BIT(2) /* require db mode to reset */
#define MHI_CH_CFG_BIT_PRE_ALLOC BIT(3) /* host allocate buffers for DL */

enum MHI_EV_CFG {
	MHI_EV_CFG_ELEMENTS = 0,
	MHI_EV_CFG_INTMOD = 1,
	MHI_EV_CFG_MSI = 2,
	MHI_EV_CFG_CHAN = 3,
	MHI_EV_CFG_PRIORITY = 4,
	MHI_EV_CFG_BRSTMODE = 5,
	MHI_EV_CFG_BITCFG = 6,
	MHI_EV_CFG_MAX
};

#define MHI_EV_CFG_BIT_HW_EV BIT(0) /* hw event ring */
#define MHI_EV_CFG_BIT_CL_MANAGE BIT(1) /* client manages the event ring */
#define MHI_EV_CFG_BIT_OFFLOAD_EV BIT(2) /* satellite driver manges it */
#define MHI_EV_CFG_BIT_CTRL_EV BIT(3) /* ctrl event ring */

enum MHI_BRSTMODE {
	MHI_BRSTMODE_DISABLE = 0x2,
	MHI_BRSTMODE_ENABLE = 0x3,
};

#define MHI_INVALID_BRSTMODE(mode) (mode != MHI_BRSTMODE_DISABLE && \
				    mode != MHI_BRSTMODE_ENABLE)

enum MHI_EE {
   MHI_EE_PBL  = 0x0,            /* Primary Boot Loader                                                */
   MHI_EE_SBL  = 0x1,            /* Secondary Boot Loader                                              */
   MHI_EE_AMSS = 0x2,            /* AMSS Firmware                                                      */
   MHI_EE_RDDM = 0x3,            /* WIFI Ram Dump Debug Module                                         */
   MHI_EE_WFW  = 0x4,            /* WIFI (WLAN) Firmware                                               */
   MHI_EE_PT   = 0x5,            /* PassThrough, Non PCIe BOOT (PCIe is BIOS locked, not used for boot */
   MHI_EE_EDL  = 0x6,            /* PCIe enabled in PBL for emergency download (Non PCIe BOOT)         */
   MHI_EE_FP   = 0x7,            /* FlashProg, Flash Programmer Environment                            */
   MHI_EE_BHIE = MHI_EE_FP,
   MHI_EE_UEFI = 0x8,            /* UEFI                                                               */

   MHI_EE_DISABLE_TRANSITION = 0x9,
   MHI_EE_MAX
};

extern const char * const mhi_ee_str[MHI_EE_MAX];
#define TO_MHI_EXEC_STR(ee) (((ee) >= MHI_EE_MAX) ? \
			     "INVALID_EE" : mhi_ee_str[ee])

#define MHI_IN_PBL(ee) (ee == MHI_EE_PBL || ee == MHI_EE_PT || ee == MHI_EE_EDL)

enum MHI_ST_TRANSITION {
	MHI_ST_TRANSITION_PBL,
	MHI_ST_TRANSITION_READY,
	MHI_ST_TRANSITION_SBL,
	MHI_ST_TRANSITION_AMSS,
	MHI_ST_TRANSITION_FP,
	MHI_ST_TRANSITION_BHIE = MHI_ST_TRANSITION_FP,
	MHI_ST_TRANSITION_MAX,
};

extern const char * const mhi_state_tran_str[MHI_ST_TRANSITION_MAX];
#define TO_MHI_STATE_TRANS_STR(state) (((state) >= MHI_ST_TRANSITION_MAX) ? \
				"INVALID_STATE" : mhi_state_tran_str[state])

enum MHI_STATE {
	MHI_STATE_RESET = 0x0,
	MHI_STATE_READY = 0x1,
	MHI_STATE_M0 = 0x2,
	MHI_STATE_M1 = 0x3,
	MHI_STATE_M2 = 0x4,
	MHI_STATE_M3 = 0x5,
	MHI_STATE_D3 = 0x6,
	MHI_STATE_BHI  = 0x7,
	MHI_STATE_SYS_ERR  = 0xFF,
	MHI_STATE_MAX,
};

extern const char * const mhi_state_str[MHI_STATE_MAX];
#define TO_MHI_STATE_STR(state) ((state >= MHI_STATE_MAX || \
				  !mhi_state_str[state]) ? \
				"INVALID_STATE" : mhi_state_str[state])

/* internal power states */
enum MHI_PM_STATE {
	MHI_PM_DISABLE = BIT(0), /* MHI is not enabled */
	MHI_PM_POR = BIT(1), /* reset state */
	MHI_PM_M0 = BIT(2),
	MHI_PM_M1 = BIT(3),
	MHI_PM_M1_M2_TRANSITION = BIT(4), /* register access not allowed */
	MHI_PM_M2 = BIT(5),
	MHI_PM_M3_ENTER = BIT(6),
	MHI_PM_M3 = BIT(7),
	MHI_PM_M3_EXIT = BIT(8),
	MHI_PM_FW_DL_ERR = BIT(9), /* firmware download failure state */
	MHI_PM_SYS_ERR_DETECT = BIT(10),
	MHI_PM_SYS_ERR_PROCESS = BIT(11),
	MHI_PM_SHUTDOWN_PROCESS = BIT(12),
	MHI_PM_LD_ERR_FATAL_DETECT = BIT(13), /* link not accessible */
};

#define MHI_REG_ACCESS_VALID(pm_state) ((pm_state & (MHI_PM_POR | MHI_PM_M0 | \
		MHI_PM_M1 | MHI_PM_M2 | MHI_PM_M3_ENTER | MHI_PM_M3_EXIT | \
		MHI_PM_SYS_ERR_DETECT | MHI_PM_SYS_ERR_PROCESS | \
		MHI_PM_SHUTDOWN_PROCESS | MHI_PM_FW_DL_ERR)))
#define MHI_PM_IN_ERROR_STATE(pm_state) (pm_state >= MHI_PM_FW_DL_ERR)
#define MHI_PM_IN_FATAL_STATE(pm_state) (pm_state == MHI_PM_LD_ERR_FATAL_DETECT)
#define MHI_DB_ACCESS_VALID(pm_state) (pm_state & (MHI_PM_M0 | MHI_PM_M1))
#define MHI_WAKE_DB_ACCESS_VALID(pm_state) (pm_state & (MHI_PM_M0 | \
							MHI_PM_M1 | MHI_PM_M2))
#define MHI_EVENT_ACCESS_INVALID(pm_state) (pm_state == MHI_PM_DISABLE || \
					    MHI_PM_IN_ERROR_STATE(pm_state))
#define MHI_PM_IN_SUSPEND_STATE(pm_state) (pm_state & \
					   (MHI_PM_M3_ENTER | MHI_PM_M3))

/* accepted buffer type for the channel */
enum MHI_XFER_TYPE {
	MHI_XFER_BUFFER,
	MHI_XFER_SKB,
	MHI_XFER_SCLIST,
	MHI_XFER_NOP, /* CPU offload channel, host does not accept transfer */
};

#define NR_OF_CMD_RINGS (1)
#define CMD_EL_PER_RING (128)
#define PRIMARY_CMD_RING (0)
#define MHI_DEV_WAKE_DB (127)
#define MHI_M2_DEBOUNCE_TMR_US (10000)
#define MHI_MAX_MTU (0xffff)

enum MHI_ER_TYPE {
	MHI_ER_TYPE_INVALID = 0x0,
	MHI_ER_TYPE_VALID = 0x1,
};

struct db_cfg {
	bool reset_req;
	bool db_mode;
	u32 pollcfg;
	enum MHI_BRSTMODE brstmode;
	dma_addr_t db_val;
	void (*process_db)(struct mhi_controller *mhi_cntrl,
			   struct db_cfg *db_cfg, void __iomem *io_addr,
			   dma_addr_t db_val);
};

struct mhi_pm_transitions {
	enum MHI_PM_STATE from_state;
	u32 to_states;
};

struct state_transition {
	struct list_head node;
	enum MHI_ST_TRANSITION state;
};

/* Control Segment */
struct mhi_ctrl_seg
{
   struct __packed mhi_tre hw_in_chan_ring[NUM_MHI_IPA_IN_RING_ELEMENTS]  __aligned(NUM_MHI_IPA_IN_RING_ELEMENTS*16);
   struct __packed mhi_tre hw_out_chan_ring[NUM_MHI_IPA_OUT_RING_ELEMENTS]  __aligned(NUM_MHI_IPA_OUT_RING_ELEMENTS*16);
   struct __packed mhi_tre diag_in_chan_ring[NUM_MHI_IPA_OUT_RING_ELEMENTS]  __aligned(NUM_MHI_IPA_OUT_RING_ELEMENTS*16);
   struct __packed mhi_tre chan_ring[NUM_MHI_CHAN_RING_ELEMENTS*2*12]  __aligned(NUM_MHI_CHAN_RING_ELEMENTS*16);
   //struct __packed mhi_tre event_ring[NUM_MHI_EVT_RINGS][NUM_MHI_EVT_RING_ELEMENTS]  __aligned(NUM_MHI_EVT_RING_ELEMENTS*16);
   struct __packed mhi_tre event_ring_0[NUM_MHI_EVT_RING_ELEMENTS]  __aligned(NUM_MHI_EVT_RING_ELEMENTS*16);
   struct __packed mhi_tre event_ring_1[NUM_MHI_IPA_OUT_EVT_RING_ELEMENTS]  __aligned(NUM_MHI_IPA_OUT_EVT_RING_ELEMENTS*16);
   struct __packed mhi_tre event_ring_2[NUM_MHI_IPA_IN_EVT_RING_ELEMENTS]  __aligned(NUM_MHI_IPA_IN_EVT_RING_ELEMENTS*16);
   struct __packed mhi_tre cmd_ring[NR_OF_CMD_RINGS][CMD_EL_PER_RING]  __aligned(CMD_EL_PER_RING*16);

   struct mhi_chan_ctxt chan_ctxt[NUM_MHI_XFER_RINGS] __aligned(128);
   struct mhi_event_ctxt er_ctxt[NUM_MHI_EVT_RINGS]  __aligned(128);
   struct mhi_cmd_ctxt cmd_ctxt[NR_OF_CMD_RINGS]  __aligned(128);
} __aligned(4096);

struct mhi_ctxt {
	struct mhi_event_ctxt *er_ctxt;
	struct mhi_chan_ctxt *chan_ctxt;
	struct mhi_cmd_ctxt *cmd_ctxt;
	dma_addr_t er_ctxt_addr;
	dma_addr_t chan_ctxt_addr;
	dma_addr_t cmd_ctxt_addr;
	struct mhi_ctrl_seg *ctrl_seg;
	dma_addr_t ctrl_seg_addr;
};

struct mhi_ring {
	dma_addr_t dma_handle;
	dma_addr_t iommu_base;
	u64 *ctxt_wp; /* point to ctxt wp */
	void *pre_aligned;
	void *base;
	void *rp;
	void *wp;
	size_t el_size;
	size_t len;
	size_t elements;
	size_t alloc_size;
	void __iomem *db_addr;
};

struct mhi_cmd {
	struct mhi_ring ring;
	spinlock_t lock;
};

struct mhi_buf_info {
	dma_addr_t p_addr;
	void *v_addr;
	void *wp;
	size_t len;
	void *cb_buf;
	enum dma_data_direction dir;
};

struct mhi_event {
	u32 er_index;
	u32 intmod;
	u32 msi;
	int chan; /* this event ring is dedicated to a channel */
	u32 priority;
	struct mhi_ring ring;
	struct db_cfg db_cfg;
	bool hw_ring;
	bool cl_manage;
	bool offload_ev; /* managed by a device driver */
	bool ctrl_ev;
	spinlock_t lock;
	struct mhi_chan *mhi_chan; /* dedicated to channel */
	struct tasklet_struct task;
	struct mhi_controller *mhi_cntrl;
};

struct mhi_chan {
	u32 chan;
	u32 ring;
	const char *name;
	/*
	 * important, when consuming increment tre_ring first, when releasing
	 * decrement buf_ring first. If tre_ring has space, buf_ring
	 * guranteed to have space so we do not need to check both rings.
	 */
	struct mhi_ring buf_ring;
	struct mhi_ring tre_ring;
	u32 er_index;
	u32 intmod;
	u32 tiocm;
	u32 full;
	enum dma_data_direction dir;
	struct db_cfg db_cfg;
	enum MHI_EE ee;
	enum MHI_XFER_TYPE xfer_type;
	enum MHI_CH_STATE ch_state;
	enum MHI_EV_CCS ccs;
	bool lpm_notify;
	bool configured;
	bool offload_ch;
	bool pre_alloc;
	/* functions that generate the transfer ring elements */
	int (*gen_tre)(struct mhi_controller *mhi_cntrl,
		       struct mhi_chan *mhi_chan, void *buf, void *cb,
		       size_t len, enum MHI_FLAGS flags);
	int (*queue_xfer)(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
			  void *buf, size_t len, enum MHI_FLAGS flags);
	/* xfer call back */
	struct mhi_device *mhi_dev;
	void (*xfer_cb)(struct mhi_device *mhi_dev, struct mhi_result *res);
	struct mutex mutex;
	struct completion completion;
	rwlock_t lock;
	struct list_head node;
};

struct mhi_bus {
	struct list_head controller_list;
	struct mutex lock;
	struct dentry *dentry;
};

struct mhi_cntrl_data {
	struct mhi_ctxt mhi_ctxt;
	struct mhi_cmd mhi_cmd[NR_OF_CMD_RINGS];
	struct mhi_event mhi_event[NUM_MHI_EVT_RINGS];
	struct mhi_chan mhi_chan[MHI_MAX_CHANNELS];
};

/* default MHI timeout */
#define MHI_TIMEOUT_MS (3000)
extern struct mhi_bus mhi_bus;

/* debug fs related functions */
int mhi_debugfs_mhi_chan_show(struct seq_file *m, void *d);
int mhi_debugfs_mhi_event_show(struct seq_file *m, void *d);
int mhi_debugfs_mhi_states_show(struct seq_file *m, void *d);
int mhi_debugfs_trigger_reset(void *data, u64 val);

void mhi_deinit_debugfs(struct mhi_controller *mhi_cntrl);
void mhi_init_debugfs(struct mhi_controller *mhi_cntrl);

/* power management apis */
enum MHI_PM_STATE __must_check mhi_tryset_pm_state(
					struct mhi_controller *mhi_cntrl,
					enum MHI_PM_STATE state);
const char *to_mhi_pm_state_str(enum MHI_PM_STATE state);
void mhi_reset_chan(struct mhi_controller *mhi_cntrl,
		    struct mhi_chan *mhi_chan);
enum MHI_EE mhi_get_exec_env(struct mhi_controller *mhi_cntrl);
enum MHI_STATE mhi_get_m_state(struct mhi_controller *mhi_cntrl);
int mhi_queue_state_transition(struct mhi_controller *mhi_cntrl,
			       enum MHI_ST_TRANSITION state);
void mhi_pm_st_worker(struct work_struct *work);
void mhi_fw_load_worker(struct work_struct *work);
void mhi_pm_m1_worker(struct work_struct *work);
void mhi_pm_sys_err_worker(struct work_struct *work);
int mhi_ready_state_transition(struct mhi_controller *mhi_cntrl);
void mhi_ctrl_ev_task(unsigned long data);
int mhi_pm_m0_transition(struct mhi_controller *mhi_cntrl);
void mhi_pm_m1_transition(struct mhi_controller *mhi_cntrl);
int mhi_pm_m3_transition(struct mhi_controller *mhi_cntrl);
void mhi_notify(struct mhi_device *mhi_dev, enum MHI_CB cb_reason);

/* queue transfer buffer */
int mhi_gen_tre(struct mhi_controller *mhi_cntrl, struct mhi_chan *mhi_chan,
		void *buf, void *cb, size_t buf_len, enum MHI_FLAGS flags);
int mhi_queue_buf(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
		  void *buf, size_t len, enum MHI_FLAGS mflags);
int mhi_queue_skb(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
		  void *buf, size_t len, enum MHI_FLAGS mflags);
int mhi_queue_sclist(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
		  void *buf, size_t len, enum MHI_FLAGS mflags);
int mhi_queue_nop(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
		  void *buf, size_t len, enum MHI_FLAGS mflags);


/* register access methods */
void mhi_db_brstmode(struct mhi_controller *mhi_cntrl, struct db_cfg *db_cfg,
		     void __iomem *db_addr, dma_addr_t wp);
void mhi_db_brstmode_disable(struct mhi_controller *mhi_cntrl,
			     struct db_cfg *db_mode, void __iomem *db_addr,
			     dma_addr_t wp);
int __must_check mhi_read_reg(struct mhi_controller *mhi_cntrl,
			      void __iomem *base, u32 offset, u32 *out);
int __must_check mhi_read_reg_field(struct mhi_controller *mhi_cntrl,
				    void __iomem *base, u32 offset, u32 mask,
				    u32 shift, u32 *out);
void mhi_write_reg(struct mhi_controller *mhi_cntrl, void __iomem *base,
		   u32 offset, u32 val);
void mhi_write_reg_field(struct mhi_controller *mhi_cntrl, void __iomem *base,
			 u32 offset, u32 mask, u32 shift, u32 val);
void mhi_ring_er_db(struct mhi_event *mhi_event);
void mhi_write_db(struct mhi_controller *mhi_cntrl, void __iomem *db_addr,
		  dma_addr_t wp);
void mhi_ring_cmd_db(struct mhi_controller *mhi_cntrl, struct mhi_cmd *mhi_cmd);
void mhi_ring_chan_db(struct mhi_controller *mhi_cntrl,
		      struct mhi_chan *mhi_chan);
void mhi_set_mhi_state(struct mhi_controller *mhi_cntrl, enum MHI_STATE state);

/* memory allocation methods */

#if (LINUX_VERSION_CODE >= KERNEL_VERSION( 5,3,0 ))
static inline void *dma_zalloc_coherent(struct device *dev, size_t size,
					dma_addr_t *dma_handle, gfp_t flag)
{
	void *ret = dma_alloc_coherent(dev, size, dma_handle,
				       flag | __GFP_ZERO);
	return ret;
}
#endif

static inline void *mhi_alloc_coherent(struct mhi_controller *mhi_cntrl,
				       size_t size,
				       dma_addr_t *dma_handle,
				       gfp_t gfp)
{
	void *buf = dma_zalloc_coherent(mhi_cntrl->dev, size, dma_handle, gfp);

	MHI_LOG("size = %zd, dma_handle = %llx\n", size, (u64)*dma_handle);
	if (buf) {
		//if (*dma_handle < mhi_cntrl->iova_start || 0 == mhi_cntrl->iova_start)
		//	mhi_cntrl->iova_start = (*dma_handle)&0xFFF0000000;
		//if ((*dma_handle + size) > mhi_cntrl->iova_stop || 0 == mhi_cntrl->iova_stop)
		//	mhi_cntrl->iova_stop = ((*dma_handle + size)+0x0FFFFFFF)&0xFFF0000000;
	}
	if (buf)
		atomic_add(size, &mhi_cntrl->alloc_size);

	return buf;
}
static inline void mhi_free_coherent(struct mhi_controller *mhi_cntrl,
				     size_t size,
				     void *vaddr,
				     dma_addr_t dma_handle)
{
	atomic_sub(size, &mhi_cntrl->alloc_size);
	dma_free_coherent(mhi_cntrl->dev, size, vaddr, dma_handle);
}
struct mhi_device *mhi_alloc_device(struct mhi_controller *mhi_cntrl);
static inline void mhi_dealloc_device(struct mhi_controller *mhi_cntrl,
				      struct mhi_device *mhi_dev)
{
	kfree(mhi_dev);
}
int mhi_destroy_device(struct device *dev, void *data);
void mhi_create_devices(struct mhi_controller *mhi_cntrl);
int mhi_alloc_bhie_table(struct mhi_controller *mhi_cntrl,
			 struct image_info **image_info, size_t alloc_size);
void mhi_free_bhie_table(struct mhi_controller *mhi_cntrl,
			 struct image_info *image_info);

/* initialization methods */
int mhi_init_chan_ctxt(struct mhi_controller *mhi_cntrl,
		       struct mhi_chan *mhi_chan);
void mhi_deinit_chan_ctxt(struct mhi_controller *mhi_cntrl,
			  struct mhi_chan *mhi_chan);
int mhi_init_mmio(struct mhi_controller *mhi_cntrl);
int mhi_init_dev_ctxt(struct mhi_controller *mhi_cntrl);
void mhi_deinit_dev_ctxt(struct mhi_controller *mhi_cntrl);
int mhi_init_irq_setup(struct mhi_controller *mhi_cntrl);
void mhi_deinit_free_irq(struct mhi_controller *mhi_cntrl);
int mhi_dtr_init(void);

/* isr handlers */
irqreturn_t mhi_msi_handlr(int irq_number, void *dev);
irqreturn_t mhi_intvec_threaded_handlr(int irq_number, void *dev);
irqreturn_t mhi_intvec_handlr(int irq_number, void *dev);
void mhi_ev_task(unsigned long data);

#ifdef CONFIG_MHI_DEBUG

#define MHI_ASSERT(cond, msg) do { \
	if (cond) \
		panic(msg); \
} while (0)

#else

#define MHI_ASSERT(cond, msg) do { \
	if (cond) { \
		MHI_ERR(msg); \
		WARN_ON(cond); \
	} \
} while (0)

#endif

#endif /* _MHI_INT_H */
