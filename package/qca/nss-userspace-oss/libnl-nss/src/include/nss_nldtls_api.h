/*
 **************************************************************************
 * Copyright (c) 2019-2021, The Linux Foundation. All rights reserved.
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

#ifndef __NSS_NLDTLS_API_H__
#define __NSS_NLDTLS_API_H__

/** @addtogroup chapter_nldtls
 This chapter describes Data Transport Layer Security (DTLS) APIs in the user space.
 These APIs are wrapper functions for DTLS family specific operations.
 */

/** @addtogroup nss_nldtls_datatypes @{ */

/**
 * Response callback for DTLS.
 *
 * @param[in] user_ctx User context (provided at socket open).
 * @param[in] rule DTLS rule.
 * @param[in] resp_ctx User data per callback.
 *
 * @return
 * None.
 */
typedef void (*nss_nldtls_resp_t)(void *user_ctx, struct nss_nldtls_rule *rule, void *resp_ctx);

/**
 * Event callback for DTLS.
 *
 * @param[in] user_ctx User context (provided at socket open).
 * @param[in] rule DTLS rule.
 *
 * @return
 * None.
 */
typedef void (*nss_nldtls_event_t)(void *user_ctx, struct nss_nldtls_rule *rule);

/**
 * NSS NL DTLS response.
 */
struct nss_nldtls_resp {
	void *data;		/**< Response context. */
	nss_nldtls_resp_t cb;	/**< Response callback. */
};

/**
 * NSS NL DTLS context.
 */
struct nss_nldtls_ctx {
	struct nss_nlsock_ctx sock;	/**< NSS socket context. */
	nss_nldtls_event_t event;	/**< NSS event callback function. */
};

/** @} *//* end_addtogroup nss_nldtls_datatypes */
/** @addtogroup nss_nldtls_functions @{ */

/**
 * Opens NSS NL DTLS socket.
 *
 * @param[in] ctx NSS NL socket context allocated by the caller.
 * @param[in] user_ctx User context stored per socket.
 * @param[in] event_cb Event callback handler.
 *
 * @return
 * Status of the open call.
 */
int nss_nldtls_sock_open(struct nss_nldtls_ctx *ctx, void *user_ctx, nss_nldtls_event_t event_cb);

/**
 * Closes NSS NL DTLS socket.
 *
 * @param[in] ctx NSS NL context.
 *
 * @return
 * None.
 */
void nss_nldtls_sock_close(struct nss_nldtls_ctx *ctx);

/**
 * Send a DTLS rule synchronously to NSS NL NETLINK.
 *
 * @param[in] ctx NSS DTLS NL context.
 * @param[in] rule DTLS rule.
 * @param[in] cb Response callback handler.
 * @param[in] data Data received from sender.
 *
 * @return
 * Send status:
 * - 0 -- Success.
 * - Negative version error (-ve) -- Failure.
 */
int nss_nldtls_sock_send(struct nss_nldtls_ctx *ctx, struct nss_nldtls_rule *rule, nss_nldtls_resp_t cb, void *data);

/**
 * Initializes create rule message.
 *
 * @param[in] rule DTLS rule.
 * @param[in] type Type of command.
 *
 * @return
 * None.
 */
void nss_nldtls_init_rule(struct nss_nldtls_rule *rule, enum nss_nldtls_cmd_type type);

/** @} *//* end_addtogroup nss_nldtls_functions */

#endif /* __NSS_NLDTLS_API_H__ */
