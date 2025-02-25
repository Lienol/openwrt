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
#ifndef _MHI_H_
#define _MHI_H_

#include <linux/miscdevice.h>

typedef u64 uint64;
typedef u32 uint32;

typedef enum
{
   MHI_CLIENT_LOOPBACK_OUT     = 0,
   MHI_CLIENT_LOOPBACK_IN      = 1,
   MHI_CLIENT_SAHARA_OUT       = 2,
   MHI_CLIENT_SAHARA_IN        = 3,
   MHI_CLIENT_DIAG_OUT         = 4,
   MHI_CLIENT_DIAG_IN          = 5,
   MHI_CLIENT_SSR_OUT          = 6,
   MHI_CLIENT_SSR_IN           = 7,
   MHI_CLIENT_QDSS_OUT         = 8,
   MHI_CLIENT_QDSS_IN          = 9,
   MHI_CLIENT_EFS_OUT          = 10,
   MHI_CLIENT_EFS_IN           = 11,
   MHI_CLIENT_MBIM_OUT         = 12,
   MHI_CLIENT_MBIM_IN          = 13,
   MHI_CLIENT_QMI_OUT          = 14,
   MHI_CLIENT_QMI_IN           = 15,
   MHI_CLIENT_QMI_2_OUT        = 16,
   MHI_CLIENT_QMI_2_IN         = 17,
   MHI_CLIENT_IP_CTRL_1_OUT    = 18,
   MHI_CLIENT_IP_CTRL_1_IN     = 19,
   MHI_CLIENT_IPCR_OUT         = 20,
   MHI_CLIENT_IPCR_IN          = 21,
   MHI_CLIENT_TEST_FW_OUT      = 22,
   MHI_CLIENT_TEST_FW_IN       = 23,
   MHI_CLIENT_RESERVED_0       = 24,
   MHI_CLIENT_BOOT_LOG_IN      = 25,
   MHI_CLIENT_DCI_OUT          = 26,
   MHI_CLIENT_DCI_IN           = 27,
   MHI_CLIENT_QBI_OUT          = 28,
   MHI_CLIENT_QBI_IN           = 29,
   MHI_CLIENT_RESERVED_1_LOWER = 30,
   MHI_CLIENT_RESERVED_1_UPPER = 31,
   MHI_CLIENT_DUN_OUT          = 32,
   MHI_CLIENT_DUN_IN           = 33,
   MHI_CLIENT_EDL_OUT          = 34,
   MHI_CLIENT_EDL_IN           = 35,
   MHI_CLIENT_ADB_FB_OUT       = 36,
   MHI_CLIENT_ADB_FB_IN        = 37,
   MHI_CLIENT_RESERVED_2_LOWER = 38,
   MHI_CLIENT_RESERVED_2_UPPER = 41,
   MHI_CLIENT_CSVT_OUT         = 42,
   MHI_CLIENT_CSVT_IN          = 43,
   MHI_CLIENT_SMCT_OUT         = 44,
   MHI_CLIENT_SMCT_IN          = 45,
   MHI_CLIENT_IP_SW_0_OUT      = 46,
   MHI_CLIENT_IP_SW_0_IN       = 47,
   MHI_CLIENT_IP_SW_1_OUT      = 48,
   MHI_CLIENT_IP_SW_1_IN       = 49,
   MHI_CLIENT_GNSS_OUT         = 50,
   MHI_CLIENT_GNSS_IN          = 51,
   MHI_CLIENT_AUDIO_OUT        = 52,
   MHI_CLIENT_AUDIO_IN         = 53,
   MHI_CLIENT_RESERVED_3_LOWER = 54,
   MHI_CLIENT_RESERVED_3_UPPER = 59,
   MHI_CLIENT_TEST_0_OUT       = 60,
   MHI_CLIENT_TEST_0_IN        = 61,
   MHI_CLIENT_TEST_1_OUT       = 62,
   MHI_CLIENT_TEST_1_IN        = 63,
   MHI_CLIENT_TEST_2_OUT       = 64,
   MHI_CLIENT_TEST_2_IN        = 65,
   MHI_CLIENT_TEST_3_OUT       = 66,
   MHI_CLIENT_TEST_3_IN        = 67,
   MHI_CLIENT_RESERVED_4_LOWER = 68,
   MHI_CLIENT_RESERVED_4_UPPER = 91,
   MHI_CLIENT_OEM_0_OUT        = 92,
   MHI_CLIENT_OEM_0_IN         = 93,
   MHI_CLIENT_OEM_1_OUT        = 94,
   MHI_CLIENT_OEM_1_IN         = 95,
   MHI_CLIENT_OEM_2_OUT        = 96,
   MHI_CLIENT_OEM_2_IN         = 97,
   MHI_CLIENT_OEM_3_OUT        = 98,
   MHI_CLIENT_OEM_3_IN         = 99,
   MHI_CLIENT_IP_HW_0_OUT      = 100,
   MHI_CLIENT_IP_HW_0_IN       = 101,
   MHI_CLIENT_ADPL             = 102,
   MHI_CLIENT_RESERVED_5_LOWER = 103,
   MHI_CLIENT_RESERVED_5_UPPER = 127,
   MHI_MAX_CHANNELS            = 128
}MHI_CLIENT_CHANNEL_TYPE;

#define MHI_VERSION                  0x01000000
#define MHIREGLEN_VALUE              0x100 /* **** WRONG VALUE *** */
#define MHI_MSI_INDEX                1
#define MAX_NUM_MHI_DEVICES          1
#define NUM_MHI_XFER_RINGS           128
#define NUM_MHI_EVT_RINGS            3
#define PRIMARY_EVENT_RING           0
#define IPA_OUT_EVENT_RING           1
#define IPA_IN_EVENT_RING            2
#define NUM_MHI_XFER_RING_ELEMENTS   16
#define NUM_MHI_EVT_RING_ELEMENTS    256
#define NUM_MHI_IPA_OUT_EVT_RING_ELEMENTS    2048
#define NUM_MHI_IPA_IN_EVT_RING_ELEMENTS       1024
#define NUM_MHI_IPA_IN_RING_ELEMENTS    256
#define NUM_MHI_IPA_OUT_RING_ELEMENTS    256
#define NUM_MHI_DIAG_IN_RING_ELEMENTS    128
#define NUM_MHI_CHAN_RING_ELEMENTS    8
#define MHI_EVT_CMD_QUEUE_SIZE       160
#define MHI_EVT_STATE_QUEUE_SIZE     128
#define MHI_EVT_XFER_QUEUE_SIZE      1024
#define MHI_ALIGN_4BYTE_OFFSET       0x3
#define MHI_ALIGN_4K_OFFSET          0xFFF
#define MAX_TRB_DATA_SIZE            0xFFFF
#define RESERVED_VALUE_64            0xFFFFFFFFFFFFFFFF
#define RESERVED_VALUE               0xFFFFFFFF
#define PCIE_LINK_DOWN               0xFFFFFFFF
#define SECONDS                      1000
#define MINUTES                      60000

#define MHI_FILE_MHI                 0x4D4849
#define MHI_FILE_INIT                0x494E4954
#define MHI_FILE_MSI                 0x4D5349
#define MHI_FILE_OS                  0x4F53
#define MHI_FILE_SM                  0x534D
#define MHI_FILE_THREADS             0x54485245
#define MHI_FILE_TRANSFER            0x5452414E
#define MHI_FILE_UTILS               0x5554494C


#define MHI_ER_PRIORITY_HIGH            0
#define MHI_ER_PRIORITY_MEDIUM       1
#define MHI_ER_PRIORITY_SPECIAL       2

#undef FALSE
#undef TRUE
#define FALSE    0
#define TRUE     1

typedef struct MHI_DEV_CTXT MHI_DEV_CTXT;
typedef struct PCI_CORE_INFO PCI_CORE_INFO;
typedef struct PCIE_DEV_INFO PCIE_DEV_INFO;

/* Memory Segment Properties */
typedef struct _MHI_MEM_PROPS
{
   uint64 VirtAligned;
   uint64 VirtUnaligned;
   uint64 PhysAligned;
   uint64 PhysUnaligned;
   uint64 Size;
   void *Handle;
}MHI_MEM_PROPS, *PMHI_MEM_PROPS;

/* Device Power State Type */
typedef enum
{
   POWER_DEVICE_INVALID      = 0,
   POWER_DEVICE_D0           = 1,
   POWER_DEVICE_D1           = 2,
   POWER_DEVICE_D2           = 3,
   POWER_DEVICE_D3           = 4,
   POWER_DEVICE_D3FINAL      = 5,  // System shutting down
   POWER_DEVICE_HIBARNATION  = 6,  // Entering system state S4
   POWER_DEVICE_MAX          = 7
}PWR_STATE_TYPE;

/* Channel State */
typedef enum
{
   CHAN_STATE_DISABLED = 0,
   CHAN_STATE_ENABLED = 1,
   CHAN_STATE_RUNNING = 2,
   CHAN_STATE_SUSPENDED = 3,
   CHAN_STATE_STOPPED = 4,
   CHAN_STATE_ERROR = 5,

   CHAN_STATE_OTHER = RESERVED_VALUE
}CHAN_STATE_TYPE;

/* Channel Type */
typedef enum
{
   INVALID_CHAN = 0,
   OUTBOUND_CHAN = 1,
   INBOUND_CHAN = 2,

   OTHER_CHAN = RESERVED_VALUE
}CHAN_TYPE;

/* Ring Type */
typedef enum
{
   CMD_RING = 0,
   XFER_RING = 1,
   EVT_RING = 2,
}MHI_RING_TYPE;

/* Event Ring */
typedef enum
{
   EVT_RING_INVALID = 0x0,
   EVT_RING_VALID = 0x1,
   EVT_RING_RESERVED = RESERVED_VALUE
}MHI_EVENT_RING_TYPE;

#pragma pack(push,1)

/* MHI Ring Context */
typedef /*_ALIGN(1)*/ struct _MHI_RING_CTXT_TYPE
{
   uint32 Info;
   uint32 Type;
   uint32 Index;
   uint64 Base;
   uint64 Length;
   volatile uint64 RP;
   uint64 WP;
}MHI_RING_CTXT_TYPE, *PMHI_RING_CTXT_TYPE;

/* MHI Ring Element */
typedef /*_ALIGN(1)*/ struct _MHI_ELEMENT_TYPE
{
   uint64 Ptr;
   uint32 Status;
   uint32 Control;
}MHI_ELEMENT_TYPE, *PMHI_ELEMENT_TYPE;

#pragma pack(pop)

/* Command Ring Element Type */
typedef enum
{
   CMD_NONE = 0,
   CMD_NOOP = 1,
   CMD_RESET_CHAN = 16,
   CMD_STOP_CHAN = 17,
   CMD_START_CHAN = 18,
   CMD_CANCEL_CHAN_XFERS = 21
}MHI_CMD_TYPE;

/* Event Ring Element Type */
typedef enum
{
   STATE_CHANGE_EVT = 32,
   CMD_COMPLETION_EVT = 33,
   XFER_COMPLETION_EVT = 34,
   EE_STATE_CHANGE_EVT = 64
} MHI_EVT_TYPE;

/* Ring Status Type */
typedef enum
{
   RING_EMPTY = 0,
   RING_FULL = 1,
   RING_QUEUED = 2,
} MHI_RING_STATUS_TYPE;

/* XFER Ring Element Type */
#define XFER_RING_ELEMENT_TYPE  2

/* Event Ring Completion Status */
typedef enum
{
   EVT_COMPLETION_INVALID = 0,
   EVT_COMPLETION_SUCCESS = 1,
   EVT_COMPLETION_EOT = 2,
   EVT_COMPLETION_OVERFLOW = 3,
   EVT_COMPLETION_EOB = 4,
   EVT_COMPLETION_OOB = 5, /* Out-Of-Buffer */
   EVT_COMPLETION_DB_MODE = 6,
   EVT_COMPLETION_UNDEFINED = 16,
   EVT_COMPLETION_MALFORMED = 17,

   EVT_COMPLETION_OTHER = RESERVED_VALUE
}EVT_COMPLETION_STATUS_TYPE;

/* *********************************************************************************************** */
/*                                               Macros                                            */
/* *********************************************************************************************** */
#define ADVANCE_RING_PTR(RingCtxt, Ptr, Size)                                                     \
   *Ptr = ((*Ptr - RingCtxt->Base)/sizeof(MHI_ELEMENT_TYPE) == (Size - 1))?      \
   RingCtxt->Base: (*Ptr + sizeof(MHI_ELEMENT_TYPE))

#define GET_VIRT_ADDR(MhiCtxt, PhysAddr)                                                          \
      ((MhiCtxt)->CtrlSegProps.VirtAligned + ((PhysAddr) - (MhiCtxt)->CtrlSegProps.PhysAligned))  \

#define GET_PHYS_ADDR(MhiCtxt, VirtAddr)                                                          \
      ((MhiCtxt)->CtrlSegProps.PhysAligned + ((VirtAddr) - (MhiCtxt)->CtrlSegProps.VirtAligned))  \

#define GET_RING_ELEMENT_INDEX(RingBase, Element)                                                 \
                           (((Element) - (RingBase))/sizeof(MHI_ELEMENT_TYPE))

#define VALID_RING_PTR(Ring, Ptr)                                                                 \
                           (((Ptr) >= (Ring)->Base) &&                                            \
                            ((Ptr) <= ((Ring)->Base + (Ring)->Length - sizeof(MHI_ELEMENT_TYPE))))

#define CHAN_INBOUND(_x)   ((_x)%2)

#define CHAN_SBL(_x)       (((_x) == MHI_CLIENT_SAHARA_OUT)   ||  \
                            ((_x) == MHI_CLIENT_SAHARA_IN)    ||  \
                            ((_x) == MHI_CLIENT_BOOT_LOG_IN))

#define CHAN_EDL(_x)       (((_x) == MHI_CLIENT_EDL_OUT)   ||  \
                            ((_x) == MHI_CLIENT_EDL_IN))
                            
#define RESERVED_CHAN(_x)  (((_x) == MHI_CLIENT_RESERVED_0)                                               ||  \
                            ((_x) >= MHI_CLIENT_RESERVED_1_LOWER && (_x) <= MHI_CLIENT_RESERVED_1_UPPER)  ||  \
                            ((_x) >= MHI_CLIENT_RESERVED_2_LOWER && (_x) <= MHI_CLIENT_RESERVED_2_UPPER)  ||  \
                            ((_x) >= MHI_CLIENT_RESERVED_3_LOWER && (_x) <= MHI_CLIENT_RESERVED_3_UPPER)  ||  \
                            ((_x) >= MHI_CLIENT_RESERVED_4_LOWER && (_x) <= MHI_CLIENT_RESERVED_4_UPPER)  ||  \
                            ((_x) >= MHI_CLIENT_RESERVED_5_LOWER))

#define VALID_CHAN(_x)      ((((_x) >= 0) && ((_x) < MHI_MAX_CHANNELS)))

#define MHI_HW_CHAN(_x)    ((_x) == MHI_CLIENT_IP_HW_0_OUT  ||  \
                            (_x) == MHI_CLIENT_IP_HW_0_IN   ||  \
                            (_x) == MHI_CLIENT_ADPL)

#define MIN(_x,_y)		   ((_x) < (_y) ? (_x): (_y))

struct mhi_chan;
struct mhi_event;
struct mhi_ctxt;
struct mhi_cmd;
struct image_info;
struct bhi_vec_entry;
struct mhi_cntrl_data;

/**
 * enum MHI_CB - MHI callback
 * @MHI_CB_IDLE: MHI entered idle state
 * @MHI_CB_PENDING_DATA: New data available for client to process
 * @MHI_CB_LPM_ENTER: MHI host entered low power mode
 * @MHI_CB_LPM_EXIT: MHI host about to exit low power mode
 * @MHI_CB_EE_RDDM: MHI device entered RDDM execution enviornment
 */
enum MHI_CB {
	MHI_CB_IDLE,
	MHI_CB_PENDING_DATA,
	MHI_CB_LPM_ENTER,
	MHI_CB_LPM_EXIT,
	MHI_CB_EE_RDDM,
};

/**
 * enum MHI_DEBUG_LEVL - various debugging level
 */
enum MHI_DEBUG_LEVEL {
	MHI_MSG_LVL_VERBOSE,
	MHI_MSG_LVL_INFO,
	MHI_MSG_LVL_ERROR,
	MHI_MSG_LVL_CRITICAL,
	MHI_MSG_LVL_MASK_ALL,
};

/**
 * enum MHI_FLAGS - Transfer flags
 * @MHI_EOB: End of buffer for bulk transfer
 * @MHI_EOT: End of transfer
 * @MHI_CHAIN: Linked transfer
 */
enum MHI_FLAGS {
	MHI_EOB,
	MHI_EOT,
	MHI_CHAIN,
};

/**
 * struct image_info - firmware and rddm table table
 * @mhi_buf - Contain device firmware and rddm table
 * @entries - # of entries in table
 */
struct image_info {
	struct mhi_buf *mhi_buf;
	struct bhi_vec_entry *bhi_vec;
	u32 entries;
};

/**
 * struct mhi_controller - Master controller structure for external modem
 * @dev: Device associated with this controller
 * @of_node: DT that has MHI configuration information
 * @regs: Points to base of MHI MMIO register space
 * @bhi: Points to base of MHI BHI register space
 * @wake_db: MHI WAKE doorbell register address
 * @dev_id: PCIe device id of the external device
 * @domain: PCIe domain the device connected to
 * @bus: PCIe bus the device assigned to
 * @slot: PCIe slot for the modem
 * @iova_start: IOMMU starting address for data
 * @iova_stop: IOMMU stop address for data
 * @fw_image: Firmware image name for normal booting
 * @edl_image: Firmware image name for emergency download mode
 * @fbc_download: MHI host needs to do complete image transfer
 * @rddm_size: RAM dump size that host should allocate for debugging purpose
 * @sbl_size: SBL image size
 * @seg_len: BHIe vector size
 * @fbc_image: Points to firmware image buffer
 * @rddm_image: Points to RAM dump buffer
 * @max_chan: Maximum number of channels controller support
 * @mhi_chan: Points to channel configuration table
 * @lpm_chans: List of channels that require LPM notifications
 * @total_ev_rings: Total # of event rings allocated
 * @hw_ev_rings: Number of hardware event rings
 * @sw_ev_rings: Number of software event rings
 * @msi_required: Number of msi required to operate
 * @msi_allocated: Number of msi allocated by bus master
 * @irq: base irq # to request
 * @mhi_event: MHI event ring configurations table
 * @mhi_cmd: MHI command ring configurations table
 * @mhi_ctxt: MHI device context, shared memory between host and device
 * @timeout_ms: Timeout in ms for state transitions
 * @pm_state: Power management state
 * @ee: MHI device execution environment
 * @dev_state: MHI STATE
 * @status_cb: CB function to notify various power states to but master
 * @link_status: Query link status in case of abnormal value read from device
 * @runtime_get: Async runtime resume function
 * @runtimet_put: Release votes
 * @priv_data: Points to bus master's private data
 */
struct mhi_controller {
	struct list_head node;

	/* device node for iommu ops */
	struct device *dev;
	struct pci_dev *pci_dev;

	/* mmio base */
	void __iomem *regs;
	void __iomem *bhi;
	void __iomem *wake_db;

	/* device topology */
	u32 dev_id;
	u32 domain;
	u32 bus;
	u32 slot;

	/* addressing window */
	dma_addr_t iova_start;
	dma_addr_t iova_stop;

	/* fw images */
	const char *fw_image;
	const char *edl_image;

	/* mhi host manages downloading entire fbc images */
	bool fbc_download;
	size_t rddm_size;
	size_t sbl_size;
	size_t seg_len;
	u32 session_id;
	u32 sequence_id;
	struct image_info *fbc_image;
	struct image_info *rddm_image;

	/* physical channel config data */
	u32 max_chan;
	struct mhi_chan *mhi_chan;
	struct list_head lpm_chans; /* these chan require lpm notification */

	/* physical event config data */
	u32 total_ev_rings;
	u32 hw_ev_rings;
	u32 sw_ev_rings;
	u32 msi_required;
	u32 msi_allocated;
	int irq[8]; /* interrupt table */
	struct mhi_event *mhi_event;

	/* cmd rings */
	struct mhi_cmd *mhi_cmd;

	/* mhi context (shared with device) */
	struct mhi_ctxt *mhi_ctxt;

	u32 timeout_ms;

	/* caller should grab pm_mutex for suspend/resume operations */
	struct mutex pm_mutex;
	bool pre_init;
	rwlock_t pm_lock;
	u32 pm_state;
	u32 ee;
	u32 dev_state;
	bool wake_set;
	atomic_t dev_wake;
	atomic_t alloc_size;
	struct list_head transition_list;
	spinlock_t transition_lock;
	spinlock_t wlock;

	/* debug counters */
	u32 M0, M1, M2, M3;

	/* worker for different state transitions */
	struct work_struct st_worker;
	struct work_struct fw_worker;
	struct work_struct m1_worker;
	struct work_struct syserr_worker;
	wait_queue_head_t state_event;

	/* shadow functions */
	void (*status_cb)(struct mhi_controller *mhi_cntrl, void *piv,
			  enum MHI_CB reason);
	int (*link_status)(struct mhi_controller *mhi_cntrl, void *priv);
	void (*wake_get)(struct mhi_controller *mhi_cntrl, bool override);
	void (*wake_put)(struct mhi_controller *mhi_cntrl, bool override);
	int (*runtime_get)(struct mhi_controller *mhi_cntrl, void *priv);
	void (*runtime_put)(struct mhi_controller *mhi_cntrl, void *priv);

	/* channel to control DTR messaging */
	struct mhi_device *dtr_dev;

	/* kernel log level */
	enum MHI_DEBUG_LEVEL klog_lvl;

	/* private log level controller driver to set */
	enum MHI_DEBUG_LEVEL log_lvl;

	/* controller specific data */
	void *priv_data;
	void *log_buf;
	struct dentry *dentry;
	struct dentry *parent;
	struct mhi_cntrl_data *data;
	
	struct miscdevice miscdev;
};

/**
 * struct mhi_device - mhi device structure associated bind to channel
 * @dev: Device associated with the channels
 * @mtu: Maximum # of bytes controller support
 * @ul_chan_id: MHI channel id for UL transfer
 * @dl_chan_id: MHI channel id for DL transfer
 * @priv: Driver private data
 */
struct mhi_device {
	struct device dev;
	u32 dev_id;
	u32 domain;
	u32 bus;
	u32 slot;
	size_t mtu;
	int ul_chan_id;
	int dl_chan_id;
	int ul_event_id;
	int dl_event_id;
	const struct mhi_device_id *id;
	const char *chan_name;
	struct mhi_controller *mhi_cntrl;
	struct mhi_chan *ul_chan;
	struct mhi_chan *dl_chan;
	atomic_t dev_wake;
	void *priv_data;
	int (*ul_xfer)(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
		       void *buf, size_t len, enum MHI_FLAGS flags);
	int (*dl_xfer)(struct mhi_device *mhi_dev, struct mhi_chan *mhi_chan,
		       void *buf, size_t len, enum MHI_FLAGS flags);
	void (*status_cb)(struct mhi_device *mhi_dev, enum MHI_CB reason);
};

/**
 * struct mhi_result - Completed buffer information
 * @buf_addr: Address of data buffer
 * @dir: Channel direction
 * @bytes_xfer: # of bytes transferred
 * @transaction_status: Status of last trasnferred
 */
struct mhi_result {
	void *buf_addr;
	enum dma_data_direction dir;
	size_t bytes_xferd;
	int transaction_status;
};

/**
 * struct mhi_buf - Describes the buffer
 * @buf: cpu address for the buffer
 * @phys_addr: physical address of the buffer
 * @dma_addr: iommu address for the buffer
 * @len: # of bytes
 * @name: Buffer label, for offload channel configurations name must be:
 * ECA - Event context array data
 * CCA - Channel context array data
 */
struct mhi_buf {
	void *buf;
	phys_addr_t phys_addr;
	dma_addr_t dma_addr;
	size_t len;
	const char *name; /* ECA, CCA */
};

/**
 * struct mhi_driver - mhi driver information
 * @id_table: NULL terminated channel ID names
 * @ul_xfer_cb: UL data transfer callback
 * @dl_xfer_cb: DL data transfer callback
 * @status_cb: Asynchronous status callback
 */
struct mhi_driver {
	const struct mhi_device_id *id_table;
	int (*probe)(struct mhi_device *mhi_dev,
		     const struct mhi_device_id *id);
	void (*remove)(struct mhi_device *mhi_dev);
	void (*ul_xfer_cb)(struct mhi_device *mhi_dev,
			   struct mhi_result *result);
	void (*dl_xfer_cb)(struct mhi_device *mhi_dev,
			   struct mhi_result *result);
	void (*status_cb)(struct mhi_device *mhi_dev, enum MHI_CB mhi_cb);
	struct device_driver driver;
};

#define to_mhi_driver(drv) container_of(drv, struct mhi_driver, driver)
#define to_mhi_device(dev) container_of(dev, struct mhi_device, dev)

static inline void mhi_device_set_devdata(struct mhi_device *mhi_dev,
					  void *priv)
{
	mhi_dev->priv_data = priv;
}

static inline void *mhi_device_get_devdata(struct mhi_device *mhi_dev)
{
	return mhi_dev->priv_data;
}

/**
 * mhi_queue_transfer - Queue a buffer to hardware
 * All transfers are asyncronous transfers
 * @mhi_dev: Device associated with the channels
 * @dir: Data direction
 * @buf: Data buffer (skb for hardware channels)
 * @len: Size in bytes
 * @mflags: Interrupt flags for the device
 */
static inline int mhi_queue_transfer(struct mhi_device *mhi_dev,
				     enum dma_data_direction dir,
				     void *buf,
				     size_t len,
				     enum MHI_FLAGS mflags)
{
	if (dir == DMA_TO_DEVICE)
		return mhi_dev->ul_xfer(mhi_dev, mhi_dev->ul_chan, buf, len,
					mflags);
	else
		return mhi_dev->dl_xfer(mhi_dev, mhi_dev->dl_chan, buf, len,
					mflags);
}

static inline void *mhi_controller_get_devdata(struct mhi_controller *mhi_cntrl)
{
	return mhi_cntrl->priv_data;
}

static inline void mhi_free_controller(struct mhi_controller *mhi_cntrl)
{
	kfree(mhi_cntrl);
}

/**
 * mhi_driver_register - Register driver with MHI framework
 * @mhi_drv: mhi_driver structure
 */
int mhi_driver_register(struct mhi_driver *mhi_drv);

/**
 * mhi_driver_unregister - Unregister a driver for mhi_devices
 * @mhi_drv: mhi_driver structure
 */
void mhi_driver_unregister(struct mhi_driver *mhi_drv);

/**
 * mhi_device_configure - configure ECA or CCA context
 * For offload channels that client manage, call this
 * function to configure channel context or event context
 * array associated with the channel
 * @mhi_div: Device associated with the channels
 * @dir: Direction of the channel
 * @mhi_buf: Configuration data
 * @elements: # of configuration elements
 */
int mhi_device_configure(struct mhi_device *mhi_div,
			 enum dma_data_direction dir,
			 struct mhi_buf *mhi_buf,
			 int elements);

/**
 * mhi_device_get - disable all low power modes
 * Only disables lpm, does not immediately exit low power mode
 * if controller already in a low power mode
 * @mhi_dev: Device associated with the channels
 */
void mhi_device_get(struct mhi_device *mhi_dev);

/**
 * mhi_device_get_sync - disable all low power modes
 * Synchronously disable all low power, exit low power mode if
 * controller already in a low power state
 * @mhi_dev: Device associated with the channels
 */
int mhi_device_get_sync(struct mhi_device *mhi_dev);

/**
 * mhi_device_put - re-enable low power modes
 * @mhi_dev: Device associated with the channels
 */
void mhi_device_put(struct mhi_device *mhi_dev);

/**
 * mhi_prepare_for_transfer - setup channel for data transfer
 * Moves both UL and DL channel from RESET to START state
 * @mhi_dev: Device associated with the channels
 */
int mhi_prepare_for_transfer(struct mhi_device *mhi_dev);

/**
 * mhi_unprepare_from_transfer -unprepare the channels
 * Moves both UL and DL channels to RESET state
 * @mhi_dev: Device associated with the channels
 */
void mhi_unprepare_from_transfer(struct mhi_device *mhi_dev);

/**
 * mhi_get_no_free_descriptors - Get transfer ring length
 * Get # of TD available to queue buffers
 * @mhi_dev: Device associated with the channels
 * @dir: Direction of the channel
 */
int mhi_get_no_free_descriptors(struct mhi_device *mhi_dev,
				enum dma_data_direction dir);

/**
 * mhi_poll - poll for any available data to consume
 * This is only applicable for DL direction
 * @mhi_dev: Device associated with the channels
 * @budget: In descriptors to service before returning
 */
int mhi_poll(struct mhi_device *mhi_dev, u32 budget);

/**
 * mhi_ioctl - user space IOCTL support for MHI channels
 * Native support for setting  TIOCM
 * @mhi_dev: Device associated with the channels
 * @cmd: IOCTL cmd
 * @arg: Optional parameter, iotcl cmd specific
 */
long mhi_ioctl(struct mhi_device *mhi_dev, unsigned int cmd, unsigned long arg);

/**
 * mhi_alloc_controller - Allocate mhi_controller structure
 * Allocate controller structure and additional data for controller
 * private data. You may get the private data pointer by calling
 * mhi_controller_get_devdata
 * @size: # of additional bytes to allocate
 */
struct mhi_controller *mhi_alloc_controller(size_t size);

/**
 * mhi_register_mhi_controller - Register MHI controller
 * Registers MHI controller with MHI bus framework. DT must be supported
 * @mhi_cntrl: MHI controller to register
 */
int mhi_register_mhi_controller(struct mhi_controller *mhi_cntrl);

void mhi_unregister_mhi_controller(struct mhi_controller *mhi_cntrl);

/**
 * mhi_bdf_to_controller - Look up a registered controller
 * Search for controller based on device identification
 * @domain: RC domain of the device
 * @bus: Bus device connected to
 * @slot: Slot device assigned to
 * @dev_id: Device Identification
 */
struct mhi_controller *mhi_bdf_to_controller(u32 domain, u32 bus, u32 slot,
					     u32 dev_id);

/**
 * mhi_prepare_for_power_up - Do pre-initialization before power up
 * This is optional, call this before power up if controller do not
 * want bus framework to automatically free any allocated memory during shutdown
 * process.
 * @mhi_cntrl: MHI controller
 */
int mhi_prepare_for_power_up(struct mhi_controller *mhi_cntrl);

/**
 * mhi_async_power_up - Starts MHI power up sequence
 * @mhi_cntrl: MHI controller
 */
int mhi_async_power_up(struct mhi_controller *mhi_cntrl);
int mhi_sync_power_up(struct mhi_controller *mhi_cntrl);

/**
 * mhi_power_down - Start MHI power down sequence
 * @mhi_cntrl: MHI controller
 * @graceful: link is still accessible, do a graceful shutdown process otherwise
 * we will shutdown host w/o putting device into RESET state
 */
void mhi_power_down(struct mhi_controller *mhi_cntrl, bool graceful);

/**
 * mhi_unprepare_after_powre_down - free any allocated memory for power up
 * @mhi_cntrl: MHI controller
 */
void mhi_unprepare_after_power_down(struct mhi_controller *mhi_cntrl);

/**
 * mhi_pm_suspend - Move MHI into a suspended state
 * Transition to MHI state M3 state from M0||M1||M2 state
 * @mhi_cntrl: MHI controller
 */
int mhi_pm_suspend(struct mhi_controller *mhi_cntrl);

/**
 * mhi_pm_resume - Resume MHI from suspended state
 * Transition to MHI state M0 state from M3 state
 * @mhi_cntrl: MHI controller
 */
int mhi_pm_resume(struct mhi_controller *mhi_cntrl);

/**
 * mhi_download_rddm_img - Download ramdump image from device for
 * debugging purpose.
 * @mhi_cntrl: MHI controller
 * @in_panic: If we trying to capture image while in kernel panic
 */
int mhi_download_rddm_img(struct mhi_controller *mhi_cntrl, bool in_panic);

/**
 * mhi_force_rddm_mode - Force external device into rddm mode
 * to collect device ramdump. This is useful if host driver assert
 * and we need to see device state as well.
 * @mhi_cntrl: MHI controller
 */
int mhi_force_rddm_mode(struct mhi_controller *mhi_cntrl);

int mhi_cntrl_register_miscdev(struct mhi_controller *mhi_cntrl);
void mhi_cntrl_deregister_miscdev(struct mhi_controller *mhi_cntrl);

extern int mhi_debug_mask;

#define MHI_VERB(fmt, ...) do { \
		if (mhi_cntrl->klog_lvl <= MHI_MSG_LVL_VERBOSE) \
			pr_err("VERBOSE:[D][%s] " fmt, __func__, ##__VA_ARGS__);\
} while (0)

#define MHI_LOG(fmt, ...) do {	\
		if (mhi_cntrl->klog_lvl <= MHI_MSG_LVL_INFO) \
			pr_err("INFO:[I][%s] " fmt, __func__, ##__VA_ARGS__);\
} while (0)

#define MHI_ERR(fmt, ...) do {	\
		if (mhi_cntrl->klog_lvl <= MHI_MSG_LVL_ERROR) \
			pr_err("[E][%s] " fmt, __func__, ##__VA_ARGS__); \
} while (0)

#define MHI_CRITICAL(fmt, ...) do { \
		if (mhi_cntrl->klog_lvl <= MHI_MSG_LVL_CRITICAL) \
			pr_err("ALERT:[C][%s] " fmt, __func__, ##__VA_ARGS__); \
} while (0)

#ifndef MHI_NAME_SIZE
#define MHI_NAME_SIZE 32
/**
 *  * struct mhi_device_id - MHI device identification
 *   * @chan: MHI channel name
 *    * @driver_data: driver data;
 *     */
struct mhi_device_id {
	const char chan[MHI_NAME_SIZE];
	unsigned long driver_data;
};
#endif

#endif /* _MHI_H_ */
