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

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/if_arp.h>
#include <linux/if_vlan.h>
#include <linux/dma-mapping.h>
#include <linux/debugfs.h>
#include <linux/device.h>
#include <linux/errno.h>
#include <linux/rtnetlink.h>
#include <net/ip.h>
#include <net/ipv6.h>
#include <linux/usb/cdc.h>
#include "../core/mhi.h"
#include "mhi_netdev.h"

struct qmap_hdr {
    u8 cd_rsvd_pad;
    u8 mux_id;
    u16 pkt_len;
} __packed;
#define FIBO_QMAP_MUX_ID 0x81

#ifdef CONFIG_MHI_NETDEV_MBIM
#else
static uint __read_mostly qmap_mode = 1;
module_param(qmap_mode, uint, S_IRUGO);
#endif

#define MHI_NETDEV_DRIVER_NAME "mhi_netdev"
#define WATCHDOG_TIMEOUT (30 * HZ)

#define MSG_VERB(fmt, ...) do { \
	if (mhi_netdev->msg_lvl <= MHI_MSG_LVL_VERBOSE) \
		pr_err("[D][%s] " fmt, __func__, ##__VA_ARGS__);\
} while (0)

#define MHI_ASSERT(cond, msg) do { \
	if (cond) { \
		MSG_ERR(msg); \
		WARN_ON(cond); \
	} \
} while (0)

#define MSG_LOG(fmt, ...) do { \
	if (mhi_netdev->msg_lvl <= MHI_MSG_LVL_INFO) \
		pr_err("[I][%s] " fmt, __func__, ##__VA_ARGS__);\
} while (0)

#define MSG_ERR(fmt, ...) do { \
	if (mhi_netdev->msg_lvl <= MHI_MSG_LVL_ERROR) \
		pr_err("[E][%s] " fmt, __func__, ##__VA_ARGS__); \
} while (0)

struct mhi_stats {
	u32 rx_int;
	u32 tx_full;
	u32 tx_pkts;
	u32 rx_budget_overflow;
	u32 rx_frag;
	u32 alloc_failed;
};

/* important: do not exceed sk_buf->cb (48 bytes) */
struct mhi_skb_priv {
	void *buf;
	size_t size;
	struct mhi_netdev *mhi_netdev;
};

struct mhi_netdev {
	int alias;
	struct mhi_device *mhi_dev;
	spinlock_t rx_lock;
	bool enabled;
	rwlock_t pm_lock; /* state change lock */
	int (*rx_queue)(struct mhi_netdev *mhi_netdev, gfp_t gfp_t);
	struct work_struct alloc_work;
	int wake;

	struct sk_buff_head rx_allocated;

	u32 mru;
	const char *interface_name;
	struct napi_struct napi;
	struct net_device *ndev;
	struct sk_buff *frag_skb;
	bool recycle_buf;

	struct mhi_stats stats;
	struct dentry *dentry;
	enum MHI_DEBUG_LEVEL msg_lvl;
#ifdef CONFIG_MHI_NETDEV_MBIM
	u16 tx_seq;
	u16 rx_seq;
	u32 rx_max;
#endif
};

struct mhi_netdev_priv {
	struct mhi_netdev *mhi_netdev;
};

static struct mhi_driver mhi_netdev_driver;
static void mhi_netdev_create_debugfs(struct mhi_netdev *mhi_netdev);


static struct mhi_netdev * g_mhi_netdev = NULL;

static inline void qmap_hex_dump(const char *tag, unsigned char *data, unsigned len) {
	//#define MHI_NETDEV_DEBUG 
	#ifdef MHI_NETDEV_DEBUG
	if (g_mhi_netdev  && g_mhi_netdev->msg_lvl > MHI_MSG_LVL_CRITICAL)
	{
		int i;
		printk("dump %s,%s:len=%d \n", tag, g_mhi_netdev->ndev->name, len);
		for (i = 0; i < len; i++)
		{
			printk(" 0x%02x", data[i]);
			if (((i+1) % 16) == 0)
			{
				printk("\n");
			}
		}

		printk("\n");
	}
	#endif
}


static int macaddr_check = 0;
static int mhi_netdev_macaddr_check_get(char * buffer, const struct kernel_param * kp)
{
    char mac_str[32];
    
    if (g_mhi_netdev == NULL)
    {   
        return sprintf(buffer, "%s\n", "null");;
    }

    snprintf(mac_str, sizeof(mac_str), "%02x:%02x:%02x:%02x:%02x:%02x\n",
        g_mhi_netdev->ndev->dev_addr[0],
        g_mhi_netdev->ndev->dev_addr[1],
        g_mhi_netdev->ndev->dev_addr[2],
        g_mhi_netdev->ndev->dev_addr[3],
        g_mhi_netdev->ndev->dev_addr[4],
        g_mhi_netdev->ndev->dev_addr[5]);

    return sprintf(buffer, "%s", mac_str);
    	
}


static int mhi_netdev_macaddr_check_set(const char * val, const struct kernel_param * kp)
{
    if (g_mhi_netdev == NULL)
    {
        return 0;
    }

    if (val[0] == '1')
    {
        if (!is_valid_ether_addr(g_mhi_netdev->ndev->dev_addr))
        {      
            eth_random_addr(g_mhi_netdev->ndev->dev_addr);
            g_mhi_netdev->ndev->addr_assign_type = NET_ADDR_RANDOM;

  	    if (!is_valid_ether_addr(g_mhi_netdev->ndev->dev_addr))
            {
                eth_random_addr(g_mhi_netdev->ndev->dev_addr);
            }
            else
            {
                printk("invalid ether addr\n");
            }
        }

        return 0;
    }

    return -EINVAL;
}

module_param_call(macaddr_check, mhi_netdev_macaddr_check_set, mhi_netdev_macaddr_check_get, &macaddr_check, 0644);



static void mhi_netdev_skb_destructor(struct sk_buff *skb)
{
	struct mhi_skb_priv *skb_priv = (struct mhi_skb_priv *)(skb->cb);
	struct mhi_netdev *mhi_netdev = skb_priv->mhi_netdev;

	skb->data = skb->head;
	skb_reset_tail_pointer(skb);
	skb->len = 0;
	MHI_ASSERT(skb->data != skb_priv->buf, "incorrect buf");
	skb_queue_tail(&mhi_netdev->rx_allocated, skb);
}

static int mhi_netdev_alloc_skb(struct mhi_netdev *mhi_netdev, gfp_t gfp_t)
{
	u32 cur_mru = mhi_netdev->mru;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	struct mhi_skb_priv *skb_priv;
	int ret;
	struct sk_buff *skb;
	int no_tre = mhi_get_no_free_descriptors(mhi_dev, DMA_FROM_DEVICE);
	int i;

	for (i = 0; i < no_tre; i++) {
		skb = alloc_skb(cur_mru + ETH_HLEN, gfp_t);
		if (!skb)
			return -ENOMEM;

              skb_reserve(skb, ETH_HLEN);

		read_lock_bh(&mhi_netdev->pm_lock);
		if (unlikely(!mhi_netdev->enabled)) {
			MSG_ERR("Interface not enabled\n");
			ret = -EIO;
			goto error_queue;
		}

		skb_priv = (struct mhi_skb_priv *)skb->cb;
		skb_priv->buf = skb->data;
		skb_priv->size = cur_mru;
		skb_priv->mhi_netdev = mhi_netdev;
		skb->dev = mhi_netdev->ndev;

		if (mhi_netdev->recycle_buf)
			skb->destructor = mhi_netdev_skb_destructor;

		spin_lock_bh(&mhi_netdev->rx_lock);
		ret = mhi_queue_transfer(mhi_dev, DMA_FROM_DEVICE, skb,
					 skb_priv->size, MHI_EOT);
		spin_unlock_bh(&mhi_netdev->rx_lock);

		if (ret) {
			MSG_ERR("Failed to queue skb, ret:%d\n", ret);
			ret = -EIO;
			goto error_queue;
		}

		read_unlock_bh(&mhi_netdev->pm_lock);
	}

	return 0;

error_queue:
	skb->destructor = NULL;
	read_unlock_bh(&mhi_netdev->pm_lock);
	dev_kfree_skb_any(skb);

	return ret;
}

static void mhi_netdev_alloc_work(struct work_struct *work)
{
	struct mhi_netdev *mhi_netdev = container_of(work, struct mhi_netdev,
						   alloc_work);
	/* sleep about 1 sec and retry, that should be enough time
	 * for system to reclaim freed memory back.
	 */
	const int sleep_ms =  1000;
	int retry = 60;
	int ret;

	MSG_LOG("Entered\n");
	do {
		ret = mhi_netdev_alloc_skb(mhi_netdev, GFP_KERNEL);
		/* sleep and try again */
		if (ret == -ENOMEM) {
			msleep(sleep_ms);
			retry--;
		}
	} while (ret == -ENOMEM && retry);

	MSG_LOG("Exit with status:%d retry:%d\n", ret, retry);
}

/* we will recycle buffers */
static int mhi_netdev_skb_recycle(struct mhi_netdev *mhi_netdev, gfp_t gfp_t)
{
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	int no_tre;
	int ret = 0;
	struct sk_buff *skb;
	struct mhi_skb_priv *skb_priv;

	read_lock_bh(&mhi_netdev->pm_lock);
	if (!mhi_netdev->enabled) {
		read_unlock_bh(&mhi_netdev->pm_lock);
		return -EIO;
	}

	no_tre = mhi_get_no_free_descriptors(mhi_dev, DMA_FROM_DEVICE);

	spin_lock_bh(&mhi_netdev->rx_lock);
	while (no_tre) {
		skb = skb_dequeue(&mhi_netdev->rx_allocated);

		/* no free buffers to recycle, reschedule work */
		if (!skb) {
			ret = -ENOMEM;
			goto error_queue;
		}

		skb_priv = (struct mhi_skb_priv *)(skb->cb);
		ret = mhi_queue_transfer(mhi_dev, DMA_FROM_DEVICE, skb,
					 skb_priv->size, MHI_EOT);

		/* failed to queue buffer */
		if (ret) {
			MSG_ERR("Failed to queue skb, ret:%d\n", ret);
			skb_queue_tail(&mhi_netdev->rx_allocated, skb);
			goto error_queue;
		}

		no_tre--;
	}

error_queue:
	spin_unlock_bh(&mhi_netdev->rx_lock);
	read_unlock_bh(&mhi_netdev->pm_lock);

	return ret;
}

static void mhi_netdev_dealloc(struct mhi_netdev *mhi_netdev)
{
	struct sk_buff *skb;

	skb = skb_dequeue(&mhi_netdev->rx_allocated);
	while (skb) {
		skb->destructor = NULL;
		kfree_skb(skb);
		skb = skb_dequeue(&mhi_netdev->rx_allocated);
	}
}

static int mhi_netdev_poll(struct napi_struct *napi, int budget)
{
	struct net_device *dev = napi->dev;
	struct mhi_netdev_priv *mhi_netdev_priv = netdev_priv(dev);
	struct mhi_netdev *mhi_netdev = mhi_netdev_priv->mhi_netdev;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	int rx_work = 0;
	int ret;

	MSG_VERB("Entered\n");

	read_lock_bh(&mhi_netdev->pm_lock);

	if (!mhi_netdev->enabled) {
		MSG_LOG("interface is disabled!\n");
		napi_complete(napi);
		read_unlock_bh(&mhi_netdev->pm_lock);
		return 0;
	}

	mhi_device_get(mhi_dev);

	rx_work = mhi_poll(mhi_dev, budget);
	if (rx_work < 0) {
		MSG_ERR("Error polling ret:%d\n", rx_work);
		rx_work = 0;
		napi_complete(napi);
		goto exit_poll;
	}

	/* queue new buffers */
	ret = mhi_netdev->rx_queue(mhi_netdev, GFP_ATOMIC);
	if (ret == -ENOMEM) {
		MSG_LOG("out of tre, queuing bg worker\n");
		mhi_netdev->stats.alloc_failed++;
		schedule_work(&mhi_netdev->alloc_work);
	}

	/* complete work if # of packet processed less than allocated budget */
	if (rx_work < budget)
		napi_complete(napi);
	else
		mhi_netdev->stats.rx_budget_overflow++;

exit_poll:
	mhi_device_put(mhi_dev);
	read_unlock_bh(&mhi_netdev->pm_lock);

	MSG_VERB("polled %d pkts\n", rx_work);

	return rx_work;
}

static int mhi_netdev_open(struct net_device *dev)
{
	struct mhi_netdev_priv *mhi_netdev_priv = netdev_priv(dev);
	struct mhi_netdev *mhi_netdev = mhi_netdev_priv->mhi_netdev;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;

	MSG_LOG("Opened net dev interface\n");

	/* tx queue may not necessarily be stopped already
	 * so stop the queue if tx path is not enabled
	 */
	if (!mhi_dev->ul_chan)
		netif_stop_queue(dev);
	else
		netif_start_queue(dev);

	return 0;

}

static int mhi_netdev_change_mtu(struct net_device *dev, int new_mtu)
{
	struct mhi_netdev_priv *mhi_netdev_priv = netdev_priv(dev);
	struct mhi_netdev *mhi_netdev = mhi_netdev_priv->mhi_netdev;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;

	if (new_mtu < 0 || mhi_dev->mtu < new_mtu)
		return -EINVAL;

	dev->mtu = new_mtu;
	return 0;
}

#ifdef CONFIG_MHI_NETDEV_MBIM
static struct sk_buff *mhi_mbim_tx_fixup(struct mhi_netdev *mhi_netdev, struct sk_buff *skb, struct net_device *dev) {
	struct usb_cdc_ncm_nth16 *nth16;
	struct usb_cdc_ncm_ndp16 *ndp16;
	__le32 sign;
	u8 *c;
	u16 tci = 0;
	unsigned int skb_len;

       qmap_hex_dump(__func__, skb->data, skb->len);

	if (skb->len > VLAN_ETH_HLEN && __vlan_get_tag(skb, &tci) == 0) 
        {
		skb_pull(skb, VLAN_ETH_HLEN);
	} 
       else 
       {
		skb_pull(skb, ETH_HLEN);
	}

       skb_len = skb->len;

	if (skb_headroom(skb) < sizeof(struct usb_cdc_ncm_nth16)) {
		printk("skb_headroom small!\n");
		return NULL;
	}

	if (skb_tailroom(skb) < (sizeof(struct usb_cdc_ncm_ndp16) + sizeof(struct usb_cdc_ncm_dpe16) * 2)) {
		if (skb_pad(skb, (sizeof(struct usb_cdc_ncm_ndp16) + sizeof(struct usb_cdc_ncm_dpe16) * 2))) {
			printk("skb_tailroom small!\n");
			return NULL;
		}
	}

	skb_push(skb, sizeof(struct usb_cdc_ncm_nth16));
	skb_put(skb, sizeof(struct usb_cdc_ncm_ndp16) + sizeof(struct usb_cdc_ncm_dpe16) * 2);

	nth16 = (struct usb_cdc_ncm_nth16 *)skb->data;
	nth16->dwSignature = cpu_to_le32(USB_CDC_NCM_NTH16_SIGN);
	nth16->wHeaderLength = cpu_to_le16(sizeof(struct usb_cdc_ncm_nth16));
	nth16->wSequence = cpu_to_le16(mhi_netdev->tx_seq++);
	nth16->wBlockLength = cpu_to_le16(skb->len);
	nth16->wNdpIndex = cpu_to_le16(sizeof(struct usb_cdc_ncm_nth16) + skb_len);

	sign = cpu_to_le32(USB_CDC_MBIM_NDP16_IPS_SIGN);
	c = (u8 *)&sign;
	//tci = 0;
	c[3] = tci;

	ndp16 = (struct usb_cdc_ncm_ndp16 *)(skb->data + nth16->wNdpIndex);
	ndp16->dwSignature = sign;
	ndp16->wLength = cpu_to_le16(sizeof(struct usb_cdc_ncm_ndp16) + sizeof(struct usb_cdc_ncm_dpe16) * 2);
	ndp16->wNextNdpIndex = 0;

	ndp16->dpe16[0].wDatagramIndex = sizeof(struct usb_cdc_ncm_nth16);
	ndp16->dpe16[0].wDatagramLength = skb_len;

	ndp16->dpe16[1].wDatagramIndex = 0;
	ndp16->dpe16[1].wDatagramLength = 0;

	return skb;
}

static int mhi_mbim_rx_fixup(struct mhi_netdev *mhi_netdev, struct sk_buff *skb_in, struct net_device *dev) {
	struct usb_cdc_ncm_nth16 *nth16;
	int ndpoffset, len;
	u16 wSequence;
	struct mhi_netdev *ctx = mhi_netdev;

	if (skb_in->len < (sizeof(struct usb_cdc_ncm_nth16) + sizeof(struct usb_cdc_ncm_ndp16))) {
		MSG_ERR("frame too short\n");
		goto error;
	}

	nth16 = (struct usb_cdc_ncm_nth16 *)skb_in->data;

	if (nth16->dwSignature != cpu_to_le32(USB_CDC_NCM_NTH16_SIGN)) {
		MSG_ERR("invalid NTH16 signature <%#010x>\n", le32_to_cpu(nth16->dwSignature));
		goto error;
	}

	len = le16_to_cpu(nth16->wBlockLength);
	if (len > ctx->rx_max) {
		MSG_ERR("unsupported NTB block length %u/%u\n", len, ctx->rx_max);
		goto error;
	}

	wSequence = le16_to_cpu(nth16->wSequence);
	if (ctx->rx_seq !=  wSequence) {
		MSG_ERR("sequence number glitch prev=%d curr=%d\n", ctx->rx_seq, wSequence);
	}
	ctx->rx_seq = wSequence + 1;

	ndpoffset = nth16->wNdpIndex;

	while (ndpoffset > 0) {
		struct usb_cdc_ncm_ndp16 *ndp16 ;
		struct usb_cdc_ncm_dpe16 *dpe16;
		int nframes, x;
		u8 *c;
		u16 tci = 0;

		if (skb_in->len < (ndpoffset + sizeof(struct usb_cdc_ncm_ndp16))) {
			MSG_ERR("invalid NDP offset  <%u>\n", ndpoffset);
			goto error;
		}

		ndp16 = (struct usb_cdc_ncm_ndp16 *)(skb_in->data + ndpoffset);

		if (le16_to_cpu(ndp16->wLength) < 0x10) {
			MSG_ERR("invalid DPT16 length <%u>\n", le16_to_cpu(ndp16->wLength));
			goto error;
		}

		nframes = ((le16_to_cpu(ndp16->wLength) - sizeof(struct usb_cdc_ncm_ndp16)) / sizeof(struct usb_cdc_ncm_dpe16));

		if (skb_in->len < (sizeof(struct usb_cdc_ncm_ndp16) + nframes * (sizeof(struct usb_cdc_ncm_dpe16)))) {
			MSG_ERR("Invalid nframes = %d\n", nframes);
			goto error;
		}

		switch (ndp16->dwSignature & cpu_to_le32(0x00ffffff)) {
			case cpu_to_le32(USB_CDC_MBIM_NDP16_IPS_SIGN):
				c = (u8 *)&ndp16->dwSignature;
				tci = c[3];
				/* tag IPS<0> packets too if MBIM_IPS0_VID exists */
				//if (!tci && info->flags & FLAG_IPS0_VLAN)
				//	tci = MBIM_IPS0_VID;
			break;
			case cpu_to_le32(USB_CDC_MBIM_NDP16_DSS_SIGN):
				c = (u8 *)&ndp16->dwSignature;
				tci = c[3] + 256;
			break;
			default:
				MSG_ERR("unsupported NDP signature <0x%08x>\n", le32_to_cpu(ndp16->dwSignature));
			goto error;
		}

              #if 0
		if (tci != 0) {
			MSG_ERR("unsupported tci %d by now\n", tci);
			goto error;
		}
              #endif

		dpe16 = ndp16->dpe16;

		for (x = 0; x < nframes; x++, dpe16++) {
			int offset = le16_to_cpu(dpe16->wDatagramIndex);
			int skb_len = le16_to_cpu(dpe16->wDatagramLength);
			struct sk_buff *skb;

			if (offset == 0 || skb_len == 0) {
				break;
			}

			/* sanity checking */
			if (((offset + skb_len) > skb_in->len) || (skb_len > ctx->rx_max)) {
				MSG_ERR("invalid frame detected (ignored) x=%d, offset=%d, skb_len=%u\n", x, offset, skb_len);
				goto error;
			}

			skb = skb_clone(skb_in, GFP_ATOMIC);
			if (!skb) {
				MSG_ERR("skb_clone fail\n");
				goto error;
			}

			skb_pull(skb, offset);
			skb_trim(skb, skb_len);
			switch (skb->data[0] & 0xf0) {
				case 0x40:
					skb->protocol = htons(ETH_P_IP);
				break;
				case 0x60:
					skb->protocol = htons(ETH_P_IPV6);
				break;
				default:
					MSG_ERR("unknow skb->protocol %02x\n", skb->data[0]);
					goto error;
			}
			skb_reset_mac_header(skb);
            
                     /* map MBIM session to VLAN */
	              if (tci)
		           __vlan_hwaccel_put_tag(skb, htons(ETH_P_8021Q), tci);
    
			netif_receive_skb(skb);
		}

		/* are there more NDPs to process? */
		ndpoffset = le16_to_cpu(ndp16->wNextNdpIndex);
	}

	return 1;
error:
	MSG_ERR("%s error\n", __func__);
	return 0;
}
#else
static struct sk_buff *mhi_qmap_tx_fixup(struct mhi_netdev *mhi_netdev, struct sk_buff *skb, struct net_device *dev) {
	struct qmap_hdr *qhdr;
       u16 tci = 0;

	if (skb->len > VLAN_ETH_HLEN && __vlan_get_tag(skb, &tci) == 0) 
        {
		skb_pull(skb, VLAN_ETH_HLEN);
	} 
       else 
       {
		skb_pull(skb, ETH_HLEN);
	}

	if (skb_headroom(skb) < sizeof(struct qmap_hdr)) {
		printk("skb_headroom small!\n");
		return NULL;
	}

	qhdr = (struct qmap_hdr *)skb_push(skb, sizeof(struct qmap_hdr));
	qhdr->cd_rsvd_pad = 0;
	qhdr->mux_id = FIBO_QMAP_MUX_ID + tci;
	qhdr->pkt_len = cpu_to_be16(skb->len - sizeof(struct qmap_hdr));

	return skb;
}

static int mhi_qmap_rx_fixup(struct mhi_netdev *mhi_netdev, struct sk_buff *skb_in, struct net_device *dev) 
{
    while (skb_in->len > sizeof(struct qmap_hdr)) 
    {
        struct qmap_hdr *qhdr = (struct qmap_hdr *)skb_in->data;
        struct sk_buff *skb = NULL;
        int pkt_len = be16_to_cpu(qhdr->pkt_len);
        u16 tci = qhdr->mux_id - FIBO_QMAP_MUX_ID;
        int skb_len;
        int ret;

        if (skb_in->len < (pkt_len + sizeof(struct qmap_hdr))) 
        {
            MSG_ERR("drop qmap unknow pkt, len=%d, pkt_len=%d\n", skb_in->len, pkt_len);
            goto error;
        }

        if (qhdr->cd_rsvd_pad & 0x80) 
        {
            MSG_ERR("drop qmap command packet %x\n", qhdr->cd_rsvd_pad);
            skb_pull(skb_in, pkt_len + sizeof(struct qmap_hdr));
            continue;
        }

        skb_len = pkt_len - (qhdr->cd_rsvd_pad&0x3F);

        skb = netdev_alloc_skb_ip_align(dev,  skb_len + ETH_HLEN);
        if (!skb)
        {   
            MSG_ERR("netdev_alloc_skb_ip_align fail\n");
            goto error;
        }

        switch (skb_in->data[sizeof(struct qmap_hdr)] & 0xf0) 
        {
            case 0x40:
            {
                skb->protocol = htons(ETH_P_IP);
                break;
            }
            
            case 0x60:
            {
                skb->protocol = htons(ETH_P_IPV6);
                break;
            }
            
            default:
            {
                MSG_ERR("unknow skb->protocol %02x\n", skb->data[0]);
                kfree_skb(skb);
            goto error;
            }
        }

        /* add an ethernet header */
        skb_put(skb, ETH_HLEN);
        skb_reset_mac_header(skb);
        eth_hdr(skb)->h_proto = skb->protocol;;
        eth_zero_addr(eth_hdr(skb)->h_source);
        memcpy(eth_hdr(skb)->h_dest, dev->dev_addr, ETH_ALEN);

        /* add datagram */
        #if (LINUX_VERSION_CODE < KERNEL_VERSION( 4,15,0 ))
        fibo_skb_put_data(skb, skb_in->data + sizeof(struct qmap_hdr), skb_len);
        #else
        skb_put_data(skb, skb_in->data + sizeof(struct qmap_hdr), skb_len);
        #endif

        skb_pull(skb, ETH_HLEN);

        /* map MBIM session to VLAN */
        if (tci)
            __vlan_hwaccel_put_tag(skb, htons(ETH_P_8021Q), tci);

        ret = netif_receive_skb(skb);

        skb_pull(skb_in, pkt_len + sizeof(struct qmap_hdr));
    }

    return 1;
    
error:
    MSG_ERR("%s error\n", __func__);
    return 0;
}
#endif

static int mhi_netdev_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct mhi_netdev_priv *mhi_netdev_priv = netdev_priv(dev);
	struct mhi_netdev *mhi_netdev = mhi_netdev_priv->mhi_netdev;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	int res = 0;
	struct mhi_skb_priv *tx_priv;

	MSG_VERB("Entered\n");

	tx_priv = (struct mhi_skb_priv *)(skb->cb);
	tx_priv->mhi_netdev = mhi_netdev;
	read_lock_bh(&mhi_netdev->pm_lock);

	if (unlikely(!mhi_netdev->enabled)) {
		/* Only reason interface could be disabled and we get data
		 * is due to an SSR. We do not want to stop the queue and
		 * return error. Instead we will flush all the uplink packets
		 * and return successful
		 */
		res = NETDEV_TX_OK;
		dev_kfree_skb_any(skb);
		goto mhi_xmit_exit;
	}

#ifdef CONFIG_MHI_NETDEV_MBIM
	if (mhi_mbim_tx_fixup(mhi_netdev, skb, dev) == NULL) {
		res = NETDEV_TX_OK;
		dev_kfree_skb_any(skb);
		goto mhi_xmit_exit;
	}
#else
	if (qmap_mode) {
		if (mhi_qmap_tx_fixup(mhi_netdev, skb, dev) == NULL) {
			res = NETDEV_TX_OK;
			dev_kfree_skb_any(skb);
			goto mhi_xmit_exit;
		}
	}
#endif

	qmap_hex_dump(__func__, skb->data, skb->len);

	res = mhi_queue_transfer(mhi_dev, DMA_TO_DEVICE, skb, skb->len,
				 MHI_EOT);
	if (res) {
		MSG_VERB("Failed to queue with reason:%d\n", res);
		netif_stop_queue(dev);
		mhi_netdev->stats.tx_full++;
		res = NETDEV_TX_BUSY;
		goto mhi_xmit_exit;
	}

	mhi_netdev->stats.tx_pkts++;

mhi_xmit_exit:
	read_unlock_bh(&mhi_netdev->pm_lock);
	MSG_VERB("Exited\n");

	return res;
}

static const struct net_device_ops mhi_netdev_ops_ip = {
	.ndo_open = mhi_netdev_open,
	.ndo_start_xmit = mhi_netdev_xmit,
	.ndo_change_mtu = mhi_netdev_change_mtu,
	.ndo_set_mac_address = eth_mac_addr,
	.ndo_validate_addr = eth_validate_addr,
};

static void mhi_netdev_setup(struct net_device *dev)
{
	dev->netdev_ops = &mhi_netdev_ops_ip;
	ether_setup(dev);

	/* set this after calling ether_setup */
	dev->flags = IFF_POINTOPOINT | IFF_NOARP | IFF_MULTICAST;
	dev->watchdog_timeo = WATCHDOG_TIMEOUT;
}

/* enable mhi_netdev netdev, call only after grabbing mhi_netdev.mutex */
static int mhi_netdev_enable_iface(struct mhi_netdev *mhi_netdev)
{
	int ret = 0;
	char ifname[IFNAMSIZ];
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	int no_tre;

	MSG_LOG("Prepare the channels for transfer\n");

	ret = mhi_prepare_for_transfer(mhi_dev);
	if (ret) {
		MSG_ERR("Failed to start TX chan ret %d\n", ret);
		goto mhi_failed_to_start;
	}

	/* first time enabling the node */
	if (!mhi_netdev->ndev) {
		struct mhi_netdev_priv *mhi_netdev_priv;

		snprintf(ifname, sizeof(ifname), "%s%%d",
			 mhi_netdev->interface_name);

		rtnl_lock();
#ifdef NET_NAME_PREDICTABLE
		mhi_netdev->ndev = alloc_netdev(sizeof(*mhi_netdev_priv),
					ifname, NET_NAME_PREDICTABLE,
					mhi_netdev_setup);
#else
		mhi_netdev->ndev = alloc_netdev(sizeof(*mhi_netdev_priv),
					ifname,
					mhi_netdev_setup);
#endif

		if (!mhi_netdev->ndev) {
			ret = -ENOMEM;
			rtnl_unlock();
			goto net_dev_alloc_fail;
		}

		//mhi_netdev->ndev->mtu = mhi_dev->mtu;
		SET_NETDEV_DEV(mhi_netdev->ndev, &mhi_dev->dev);
		mhi_netdev_priv = netdev_priv(mhi_netdev->ndev);
		mhi_netdev_priv->mhi_netdev = mhi_netdev;
		rtnl_unlock();

		netif_napi_add(mhi_netdev->ndev, &mhi_netdev->napi,
			       mhi_netdev_poll, NAPI_POLL_WEIGHT);
		ret = register_netdev(mhi_netdev->ndev);
		if (ret) {
			MSG_ERR("Network device registration failed\n");
			goto net_dev_reg_fail;
		}

		skb_queue_head_init(&mhi_netdev->rx_allocated);
	}

	write_lock_irq(&mhi_netdev->pm_lock);
	mhi_netdev->enabled =  true;
	write_unlock_irq(&mhi_netdev->pm_lock);

	/* queue buffer for rx path */
	no_tre = mhi_get_no_free_descriptors(mhi_dev, DMA_FROM_DEVICE);
	ret = mhi_netdev_alloc_skb(mhi_netdev, GFP_KERNEL);
	if (ret)
		schedule_work(&mhi_netdev->alloc_work);

	/* if we recycle prepare one more set */
	if (mhi_netdev->recycle_buf)
		for (; no_tre >= 0; no_tre--) {
			struct sk_buff *skb = alloc_skb(mhi_netdev->mru + ETH_HLEN,
							GFP_KERNEL);
			struct mhi_skb_priv *skb_priv;

			if (!skb)
				break;

                     skb_reserve(skb, ETH_HLEN);

			skb_priv = (struct mhi_skb_priv *)skb->cb;
			skb_priv->buf = skb->data;
			skb_priv->size = mhi_netdev->mru;
			skb_priv->mhi_netdev = mhi_netdev;
			skb->dev = mhi_netdev->ndev;
			skb->destructor = mhi_netdev_skb_destructor;
			skb_queue_tail(&mhi_netdev->rx_allocated, skb);
		}

	napi_enable(&mhi_netdev->napi);

	MSG_LOG("Exited.\n");

	return 0;

net_dev_reg_fail:
	netif_napi_del(&mhi_netdev->napi);
	free_netdev(mhi_netdev->ndev);
	mhi_netdev->ndev = NULL;

net_dev_alloc_fail:
	mhi_unprepare_from_transfer(mhi_dev);

mhi_failed_to_start:
	MSG_ERR("Exited ret %d.\n", ret);

	return ret;
}

static void mhi_netdev_xfer_ul_cb(struct mhi_device *mhi_dev,
				  struct mhi_result *mhi_result)
{
	struct mhi_netdev *mhi_netdev = mhi_device_get_devdata(mhi_dev);
	struct sk_buff *skb = mhi_result->buf_addr;
	struct net_device *ndev = mhi_netdev->ndev;

	ndev->stats.tx_packets++;
	ndev->stats.tx_bytes += skb->len;
	dev_kfree_skb(skb);

	if (netif_queue_stopped(ndev))
		netif_wake_queue(ndev);
}

static int mhi_netdev_process_fragment(struct mhi_netdev *mhi_netdev,
				      struct sk_buff *skb)
{
	struct sk_buff *temp_skb;

	if (mhi_netdev->frag_skb) {
		/* merge the new skb into the old fragment */
		temp_skb = skb_copy_expand(mhi_netdev->frag_skb, ETH_HLEN, skb->len,
					   GFP_ATOMIC);
		if (!temp_skb) {
			dev_kfree_skb(mhi_netdev->frag_skb);
			mhi_netdev->frag_skb = NULL;
			return -ENOMEM;
		}

		dev_kfree_skb_any(mhi_netdev->frag_skb);
		mhi_netdev->frag_skb = temp_skb;
		memcpy(skb_put(mhi_netdev->frag_skb, skb->len), skb->data,
		       skb->len);
	} else {
		mhi_netdev->frag_skb = skb_copy(skb, GFP_ATOMIC);
		if (!mhi_netdev->frag_skb)
			return -ENOMEM;
	}

	mhi_netdev->stats.rx_frag++;

	return 0;
}

static void mhi_netdev_xfer_dl_cb(struct mhi_device *mhi_dev,
				  struct mhi_result *mhi_result)
{
	struct mhi_netdev *mhi_netdev = mhi_device_get_devdata(mhi_dev);
	struct sk_buff *skb = mhi_result->buf_addr;
	struct net_device *dev = mhi_netdev->ndev;
	int ret = 0;
	static size_t bytes_xferd = 0;

	if (mhi_result->transaction_status == -ENOTCONN) {
		dev_kfree_skb(skb);
		return;
	}

	if (mhi_result->bytes_xferd > bytes_xferd) {
		bytes_xferd = mhi_result->bytes_xferd;
		//printk("%s bytes_xferd=%zd\n", __func__, bytes_xferd);
	}

	skb_put(skb, mhi_result->bytes_xferd);
	dev->stats.rx_packets++;
	dev->stats.rx_bytes += mhi_result->bytes_xferd;

	/* merge skb's together, it's a chain transfer */
	if (mhi_result->transaction_status == -EOVERFLOW ||
	    mhi_netdev->frag_skb) {
		ret = mhi_netdev_process_fragment(mhi_netdev, skb);

		/* recycle the skb */
		if (mhi_netdev->recycle_buf)
			mhi_netdev_skb_destructor(skb);
		else
			dev_kfree_skb(skb);

		if (ret)
			return;
	}

	/* more data will come, don't submit the buffer */
	if (mhi_result->transaction_status == -EOVERFLOW)
		return;

	if (mhi_netdev->frag_skb) {
		skb = mhi_netdev->frag_skb;
		skb->dev = dev;
		mhi_netdev->frag_skb = NULL;
	}

	qmap_hex_dump(__func__, skb->data, skb->len);

#ifdef CONFIG_MHI_NETDEV_MBIM
		mhi_mbim_rx_fixup(mhi_netdev, skb, dev);
		dev_kfree_skb_any(skb);
#else
	if (qmap_mode) {
		mhi_qmap_rx_fixup(mhi_netdev, skb, dev);
		dev_kfree_skb_any(skb);
			}
	else {
		switch (skb->data[0] & 0xf0) {
				case 0x40:
			skb->protocol = htons(ETH_P_IP);
			netif_receive_skb(skb);
				break;
				case 0x60:
			skb->protocol = htons(ETH_P_IPV6);
			netif_receive_skb(skb);
				break;
				default:
			break;
		}
		}
#endif

	mhi_netdev->rx_queue(mhi_netdev, GFP_ATOMIC);
}

static void mhi_netdev_status_cb(struct mhi_device *mhi_dev, enum MHI_CB mhi_cb)
{
	struct mhi_netdev *mhi_netdev = mhi_device_get_devdata(mhi_dev);

	if (mhi_cb != MHI_CB_PENDING_DATA)
		return;

	if (napi_schedule_prep(&mhi_netdev->napi)) {
		__napi_schedule(&mhi_netdev->napi);
		mhi_netdev->stats.rx_int++;
		return;
	}

}

#ifdef CONFIG_DEBUG_FS

struct dentry *mhi_netdev_debugfs_dentry;

static int mhi_netdev_debugfs_trigger_reset(void *data, u64 val)
{
	struct mhi_netdev *mhi_netdev = data;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	int ret;

	MSG_LOG("Triggering channel reset\n");

	/* disable the interface so no data processing */
	write_lock_irq(&mhi_netdev->pm_lock);
	mhi_netdev->enabled = false;
	write_unlock_irq(&mhi_netdev->pm_lock);
	napi_disable(&mhi_netdev->napi);

	/* disable all hardware channels */
	mhi_unprepare_from_transfer(mhi_dev);

	/* clean up all alocated buffers */
	mhi_netdev_dealloc(mhi_netdev);

	MSG_LOG("Restarting iface\n");

	ret = mhi_netdev_enable_iface(mhi_netdev);
	if (ret)
		return ret;

	return 0;
}
DEFINE_SIMPLE_ATTRIBUTE(mhi_netdev_debugfs_trigger_reset_fops, NULL,
			mhi_netdev_debugfs_trigger_reset, "%llu\n");

static void mhi_netdev_create_debugfs(struct mhi_netdev *mhi_netdev)
{
	char node_name[32];
	int i;
	const umode_t mode = 0600;
	struct dentry *file;
	struct mhi_device *mhi_dev = mhi_netdev->mhi_dev;
	struct dentry *dentry = mhi_netdev_debugfs_dentry;

	const struct {
		char *name;
		u32 *ptr;
	} debugfs_table[] = {
		{
			"rx_int",
			&mhi_netdev->stats.rx_int
		},
		{
			"tx_full",
			&mhi_netdev->stats.tx_full
		},
		{
			"tx_pkts",
			&mhi_netdev->stats.tx_pkts
		},
		{
			"rx_budget_overflow",
			&mhi_netdev->stats.rx_budget_overflow
		},
		{
			"rx_fragmentation",
			&mhi_netdev->stats.rx_frag
		},
		{
			"alloc_failed",
			&mhi_netdev->stats.alloc_failed
		},
		{
			NULL, NULL
		},
	};

	/* Both tx & rx client handle contain same device info */
	snprintf(node_name, sizeof(node_name), "%s_%04x_%02u.%02u.%02u_%u",
		 mhi_netdev->interface_name, mhi_dev->dev_id, mhi_dev->domain,
		 mhi_dev->bus, mhi_dev->slot, mhi_netdev->alias);

	if (IS_ERR_OR_NULL(dentry))
		return;

	mhi_netdev->dentry = debugfs_create_dir(node_name, dentry);
	if (IS_ERR_OR_NULL(mhi_netdev->dentry))
		return;
	/*begin added by tony.du for mantis 0062018 on 2020-11-10*/
	debugfs_create_u32("msg_lvl", mode, mhi_netdev->dentry,
				  (u32 *)&mhi_netdev->msg_lvl);
	/*end added by tony.du for mantis 0062018 on 2020-11-10*/

	/* Add debug stats table */
	for (i = 0; debugfs_table[i].name; i++) {
		/*begin added by tony.du for mantis 0062018 on 2020-11-10*/
		debugfs_create_u32(debugfs_table[i].name, mode,
					  mhi_netdev->dentry,
					  debugfs_table[i].ptr);
		/*end added by tony.du for mantis 0062018 on 2020-11-10*/
	}

	debugfs_create_file("reset", mode, mhi_netdev->dentry, mhi_netdev,
			    &mhi_netdev_debugfs_trigger_reset_fops);
}

static void mhi_netdev_create_debugfs_dir(struct dentry *parent)
{
	mhi_netdev_debugfs_dentry = debugfs_create_dir(MHI_NETDEV_DRIVER_NAME, parent);
}

#else

static void mhi_netdev_create_debugfs(struct mhi_netdev *mhi_netdev)
{
}

static void mhi_netdev_create_debugfs_dir(struct dentry *parent)
{
}

#endif

static void mhi_netdev_remove(struct mhi_device *mhi_dev)
{
	struct mhi_netdev *mhi_netdev = mhi_device_get_devdata(mhi_dev);

	MSG_LOG("Remove notification received\n");

	write_lock_irq(&mhi_netdev->pm_lock);
	mhi_netdev->enabled = false;
	write_unlock_irq(&mhi_netdev->pm_lock);

	napi_disable(&mhi_netdev->napi);
	netif_napi_del(&mhi_netdev->napi);
	mhi_netdev_dealloc(mhi_netdev);
	unregister_netdev(mhi_netdev->ndev);
	free_netdev(mhi_netdev->ndev);
	flush_work(&mhi_netdev->alloc_work);

	if (!IS_ERR_OR_NULL(mhi_netdev->dentry))
		debugfs_remove_recursive(mhi_netdev->dentry);
}

static int mhi_netdev_probe(struct mhi_device *mhi_dev,
			    const struct mhi_device_id *id)
{
	int ret;
	struct mhi_netdev *mhi_netdev;

	mhi_netdev = devm_kzalloc(&mhi_dev->dev, sizeof(*mhi_netdev),
				  GFP_KERNEL);
	if (!mhi_netdev)
		return -ENOMEM;

	mhi_netdev->alias = 0;

	mhi_netdev->mhi_dev = mhi_dev;
	mhi_device_set_devdata(mhi_dev, mhi_netdev);

	mhi_netdev->mru = 0x4000;
	if (mhi_dev->dev_id == 0x0304) { //SDX24
		mhi_netdev->mru = 0x8000;
	}
#ifdef CONFIG_MHI_NETDEV_MBIM
	mhi_netdev->rx_max = 0x8000;
#endif

	if (!strcmp(id->chan, "IP_HW0"))
		mhi_netdev->interface_name = "pcie_mhi";
	else if (!strcmp(id->chan, "IP_SW0"))
		mhi_netdev->interface_name = "pcie_swip";
	else
		mhi_netdev->interface_name = id->chan;

	mhi_netdev->recycle_buf = false;

	mhi_netdev->rx_queue = mhi_netdev->recycle_buf ?
		mhi_netdev_skb_recycle : mhi_netdev_alloc_skb;

	spin_lock_init(&mhi_netdev->rx_lock);
	rwlock_init(&mhi_netdev->pm_lock);
	INIT_WORK(&mhi_netdev->alloc_work, mhi_netdev_alloc_work);

	mhi_netdev->msg_lvl = MHI_MSG_LVL_INFO;

	/* setup network interface */
	ret = mhi_netdev_enable_iface(mhi_netdev);
	if (ret) {
		pr_err("Error mhi_netdev_enable_iface ret:%d\n", ret);
		return ret;
	}

	mhi_netdev_create_debugfs(mhi_netdev);

       g_mhi_netdev = mhi_netdev;

	return 0;
}

static const struct mhi_device_id mhi_netdev_match_table[] = {
	{ .chan = "IP_HW0" },
	{ .chan = "IP_SW0" },
	{ .chan = "IP_HW_ADPL" },
	{ },
};

static struct mhi_driver mhi_netdev_driver = {
	.id_table = mhi_netdev_match_table,
	.probe = mhi_netdev_probe,
	.remove = mhi_netdev_remove,
	.ul_xfer_cb = mhi_netdev_xfer_ul_cb,
	.dl_xfer_cb = mhi_netdev_xfer_dl_cb,
	.status_cb = mhi_netdev_status_cb,
	.driver = {
		.name = "mhi_netdev",
		.owner = THIS_MODULE,
	}
};

int __init mhi_device_netdev_init(struct dentry *parent)
{
	mhi_netdev_create_debugfs_dir(parent);

	return mhi_driver_register(&mhi_netdev_driver);
}

void mhi_device_netdev_exit(void)
{
#ifdef CONFIG_DEBUG_FS
	debugfs_remove_recursive(mhi_netdev_debugfs_dentry);
#endif
	mhi_driver_unregister(&mhi_netdev_driver);
}
