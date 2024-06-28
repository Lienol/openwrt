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

#include <nss_nlbase.h>
#include <nss_nlsock_api.h>
#include <nss_nlmcast_api.h>

/*
 * nss_nlmcast_sock_cb()
 *	NSS NL mcast callback.
 */
static int nss_nlmcast_sock_cb(struct nl_msg *msg, void *arg)
{
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)arg;
	struct genlmsghdr *genl_hdr = nlmsg_data((nlmsg_hdr(msg)));
	uint8_t cmd = genl_hdr->cmd;

	void *data = nss_nlsock_get_data(msg);
	if (!data) {
		nss_nlsock_log_error("%d:failed to get NSS NL msg header\n", getpid());
		return NL_SKIP;
	}

	nss_nlmcast_event_t event = ctx->event;
	assert(event);
	event(cmd, data);
	return NL_OK;
}

/*
 * nss_nlmcast_sock_open()
 *	Open the NL socket for listening to MCAST events from kernel.
 */
int nss_nlmcast_sock_open(struct nss_nlmcast_ctx *ctx, nss_nlmcast_event_t event_cb, const char *family_name)
{
	int error;

	if (!ctx || !event_cb) {
		nss_nlsock_log_error("Invalid parameters passed\n");
		return -EINVAL;
	}

	memset(ctx, 0, sizeof(*ctx));

	nss_nlsock_set_family(&ctx->sock, family_name);

	/*
	 * Subscribe to the NSS NL Multicast group.
	 */
	error = nss_nlsock_open_mcast(&ctx->sock, nss_nlmcast_sock_cb);
	if (error) {
		nss_nlsock_log_error("Unable to create socket, error(%d)\n", error);
		return error;
	}

	ctx->event = event_cb;
	return 0;
}

/*
 * nss_nlmcast_sock_close()
 *      Close the NL socket.
 */
void nss_nlmcast_sock_close(struct nss_nlmcast_ctx *ctx)
{
	nss_nlsock_close(&ctx->sock);
}

/*
 * nss_nlmcast_sock_join_grp()
 *	Subscribe for MCAST group from kernel.
 */
int nss_nlmcast_sock_join_grp(struct nss_nlmcast_ctx *ctx, char *grp_name)
{
	int error;

	if (!ctx || !grp_name) {
		nss_nlsock_log_error("Invalid parameters passed\n");
		return -EINVAL;
	}

	error = nss_nlsock_join_grp(&ctx->sock, grp_name);
	if (error) {
		nss_nlsock_log_error("Unable to subscribe for mcast group, error(%d)\n", error);
		return error;
	}

	return 0;
}

/*
 * nss_nlmcast_sock_leave_grp()
 *      Unsubscribe for MCAST group from kernel.
 */
int nss_nlmcast_sock_leave_grp(struct nss_nlmcast_ctx *ctx, char *grp_name)
{
	int error;

	if (!ctx || !grp_name) {
		nss_nlsock_log_error("Invalid parameters passed\n");
		return -EINVAL;
	}

	error = nss_nlsock_leave_grp(&ctx->sock, grp_name);
	if (error) {
		nss_nlsock_log_error("Unable to unsubscribe for mcast group, error(%d)\n", error);
		return error;
	}

	return 0;
}

/*
 * nss_nlmcast_sock_listen()
 *	Listen for MCAST events from kernel
 */
int nss_nlmcast_sock_listen(struct nss_nlmcast_ctx *ctx)
{
	int error;

	if (!ctx) {
		nss_nlsock_log_error("Invalid parameters passed\n");
		return -EINVAL;
	}

	error = nss_nlsock_listen(&ctx->sock);
	if (error) {
		nss_nlsock_log_error("Unable to listen to mcast events, error(%d)\n", error);
		return error;
	}

	return 0;
}
