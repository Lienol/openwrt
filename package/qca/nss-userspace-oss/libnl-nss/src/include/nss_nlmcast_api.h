/*
 **************************************************************************
 * Copyright (c) 2020-2021, The Linux Foundation. All rights reserved.
 * Permission to use, copy, modify, and/or distribute this software for
 * any purpose with or without fee is hereby granted, provided that the
 * above copyright notice and this permission notice appear in all copies.
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
 * OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 **************************************************************************
 */

#ifndef __NSS_NLMCAST_API_H__
#define __NSS_NLMCAST_API_H__

/** @addtogroup chapter_nlmcast
 This chapter describes multicast APIs in the user space.
 These APIs are wrapper functions for multicast specific operations.
*/

/** @addtogroup nss_nlmcast_datatypes @{ */

/**
 * Event callback for multicast.
 *
 * @param[in] cmd Command received in generic Netlink header.
 * @param[in] data Data received in Netlink message.
 */
typedef void (*nss_nlmcast_event_t)(int cmd, void *data);

/**
 * NSS multicast context.
 */
struct nss_nlmcast_ctx {
	struct nss_nlsock_ctx sock;     /**< NSS socket context. */
	nss_nlmcast_event_t event;       /**< NSS event callback function. */
};

/** @} *//* end_addtogroup nss_nlmcast_datatypes */
/** @addtogroup nss_nlmcast_functions @{ */

/**
 * Listens to NSS NL multicast event data.
 *
 * @param[in] ctx Multicast context.
 *
 * @return
 * Listen status.
 */
int nss_nlmcast_sock_listen(struct nss_nlmcast_ctx *ctx);

/**
 * Subscribe the multicast group to receive responses.
 *
 * @param[in] ctx Multicast context.
 * @param[in] grp_name NSS NL group name.
 *
 * @return
 * Subscription status.
 */
int nss_nlmcast_sock_join_grp(struct nss_nlmcast_ctx *ctx, char *grp_name);

/**
 * Unsubscribe the multicast group to stop receiving responses.
 *
 * @param[in] ctx Multicast context.
 * @param[in] grp_name NSS NL group name.
 *
 * @return
 * Status of the operation.
 */
int nss_nlmcast_sock_leave_grp(struct nss_nlmcast_ctx *ctx, char *grp_name);

/**
 * Opens a socket for listening to NSS NL event data.
 *
 * @param[in] ctx Multicast context.
 * @param[in] cb Callback function.
 * @param[in] family_name NSS NL family name.
 *
 * @return
 * Status of the operation.
 */
int nss_nlmcast_sock_open(struct nss_nlmcast_ctx *ctx, nss_nlmcast_event_t cb, const char *family_name);

/**
 * Closes socket.
 *
 * @param[in] ctx Multicast context.
 *
 * @return
 * None.
 */
void nss_nlmcast_sock_close(struct nss_nlmcast_ctx *ctx);

/** @} *//* end_addtogroup nss_nlmcast_functions */

#endif /* __NSS_NLMCAST_API_H__ */
