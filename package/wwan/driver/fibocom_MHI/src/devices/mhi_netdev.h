#ifndef _FIBO_MHI_NETDEV_H
#define _FIBO_MHI_NETDEV_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION( 4,15,0 ))
static inline void *fibo_skb_put_data(struct sk_buff *skb, const void *data,
                                 unsigned int len)
{
        void *tmp = skb_put(skb, len);

        memcpy(tmp,data, len);

        return tmp;
}
#endif

#endif
