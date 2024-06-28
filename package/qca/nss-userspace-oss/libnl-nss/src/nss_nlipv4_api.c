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

#include <nss_nlbase.h>
#include <nss_nlsock_api.h>
#include <nss_nlipv4_api.h>

/*
 * nss_nlipv4_sock_cb()
 *	NSS NL IPv4 callback
 */
int nss_nlipv4_sock_cb(struct nl_msg *msg, void *arg)
{
	pid_t pid = getpid();

	struct nss_nlipv4_ctx *ctx = (struct nss_nlipv4_ctx *)arg;
	struct nss_nlsock_ctx *sock = &ctx->sock;

	struct nss_nlipv4_rule *rule = nss_nlsock_get_data(msg);
	if (!rule) {
		nss_nlsock_log_error("%d:failed to get NSS NL IPv4 header\n", pid);
		return NL_SKIP;
	}

	uint8_t cmd = nss_nlcmn_get_cmd(&rule->cm);

	switch (cmd) {
	case NSS_IPV4_TX_CREATE_RULE_MSG:
	case NSS_IPV4_TX_DESTROY_RULE_MSG:
	{
		void *cb_data = nss_nlcmn_get_cb_data(&rule->cm, sock->family_id);
		if (!cb_data) {
			return NL_SKIP;
		}

		/*
		 * Note: The callback user can modify the CB content so it
		 * needs to locally save the response data for further use
		 * after the callback is completed
		 */
		struct nss_nlipv4_resp resp;
		memcpy(&resp, cb_data, sizeof(struct nss_nlipv4_resp));

		/*
		 * clear the ownership of the CB so that callback user can
		 * use it if needed
		 */
		nss_nlcmn_clr_cb_owner(&rule->cm);

		if (!resp.cb) {
			nss_nlsock_log_info("%d:no IPv4 response callback for cmd(%d)\n", pid, cmd);
			return NL_SKIP;
		}

		resp.cb(sock->user_ctx, rule, resp.data);

		return NL_OK;
	}

	case NSS_IPV4_RX_CONN_STATS_SYNC_MSG:
	{
		nss_nlipv4_event_t event = ctx->event;

		assert(event);
		event(sock->user_ctx, rule);

		return NL_OK;
	}

	default:
		nss_nlsock_log_error("%d:unsupported message cmd type(%d)\n", pid, cmd);
		return NL_SKIP;
	}
}

/*
 * nss_nlipv4_sock_open()
 *	this opens the NSS IPv4 NL socket for usage
 */
int nss_nlipv4_sock_open(struct nss_nlipv4_ctx *ctx, void *user_ctx, nss_nlipv4_event_t event_cb)
{
	pid_t pid = getpid();
	int error;

	if (!ctx) {
		nss_nlsock_log_error("%d: invalid parameters passed\n", pid);
		return -EINVAL;
	}

	memset(ctx, 0, sizeof(*ctx));

	nss_nlsock_set_family(&ctx->sock, NSS_NLIPV4_FAMILY);
	nss_nlsock_set_user_ctx(&ctx->sock, user_ctx);

	/*
	 * try opening the socket with Linux
	 */
	error = nss_nlsock_open(&ctx->sock, nss_nlipv4_sock_cb);
	if (error) {
		nss_nlsock_log_error("%d:unable to open NSS IPv4 socket, error(%d)\n", pid, error);
		goto fail;
	}

	return 0;
fail:
	memset(ctx, 0, sizeof(*ctx));
	return error;
}

/*
 * nss_nlipv4_sock_close()
 *	close the NSS IPv4 NL socket
 */
void nss_nlipv4_sock_close(struct nss_nlipv4_ctx *ctx)
{
	nss_nlsock_close(&ctx->sock);
}

/*
 * nss_nlipv4_sock_send()
 *	register callback and send the IPv4 message synchronously through the socket
 */
int nss_nlipv4_sock_send(struct nss_nlipv4_ctx *ctx, struct nss_nlipv4_rule *rule, nss_nlipv4_resp_t cb, void *data)
{
	int32_t family_id = ctx->sock.family_id;
	struct nss_nlipv4_resp *resp;
	pid_t pid = getpid();
	bool has_resp = false;
	int error;

	if (!rule) {
		nss_nlsock_log_error("%d:invalid NSS IPv4 rule\n", pid);
		return -ENOMEM;
	}

	if (cb) {
		nss_nlcmn_set_cb_owner(&rule->cm, family_id);

		resp = nss_nlcmn_get_cb_data(&rule->cm, family_id);
		assert(resp);

		resp->data = data;
		resp->cb = cb;
		has_resp = true;
	}

	error = nss_nlsock_send(&ctx->sock, &rule->cm, rule, has_resp);
	if (error) {
		nss_nlsock_log_error("%d:failed to send NSS IPv4 rule, error(%d)\n", pid, error);
		return error;
	}

	return 0;
}

/*
 * nss_nlipv4_init_rule()
 *	init the rule message
 */
void nss_nlipv4_init_rule(struct nss_nlipv4_rule *rule, enum nss_ipv4_message_types type)
{
	nss_nlipv4_rule_init(rule, type);
}
