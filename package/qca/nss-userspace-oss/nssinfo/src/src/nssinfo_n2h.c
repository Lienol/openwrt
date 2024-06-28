/*
 **************************************************************************
 * Copyright (c) 2021, The Linux Foundation. All rights reserved.
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

/*
 * @file NSSINFO n2h handler
 */
#include "nssinfo.h"
#include <nss_n2h.h>
#include <nss_nln2h_if.h>

static pthread_mutex_t n2h_lock;
static uint64_t drv_stats[NSS_STATS_DRV_MAX];
static struct nssinfo_stats_info nssinfo_n2h_stats_str[NSS_N2H_STATS_MAX];

/*
 * nssinfo_n2h_stats_display()
 *	N2H display callback function.
 */
static void nssinfo_n2h_stats_display(int core, char *input)
{
	struct node *n2h_node;
	char str_rx[NSSINFO_STR_LEN], str_tx[NSSINFO_STR_LEN];

	if (input && strncmp(input, nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].subsystem_name, strlen(input))) {
		++invalid_input;
		nssinfo_trace("Invalid node name: %s\n", input);
		return;
	}

	pthread_mutex_lock(&n2h_lock);
	n2h_node = nodes[core][NSS_N2H_INTERFACE];
	if (!n2h_node) {
		pthread_mutex_unlock(&n2h_lock);
		return;
	}

	if (display_all_stats) {
		nssinfo_print_all("n2h", "n2h Stats", nssinfo_n2h_stats_str, NSS_N2H_STATS_MAX, (uint64_t *)n2h_node->node_stats);
		pthread_mutex_unlock(&n2h_lock);
		return;
	}

	nssinfo_print_summary("n2h", (uint64_t *)n2h_node->node_stats, NULL, 0);

	if (core == (NSS_MAX_CORES - 1)) {

		char *format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_RX_CMD_RESP]);
		strlcpy(str_rx, format_stats, sizeof(str_rx));
		format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_TX_CMD_REQ]);
		strlcpy(str_tx, format_stats, sizeof(str_tx));
		nssinfo_stats_print(nssinfo_summary_fmt, " buf_cmd", str_rx, str_tx, "", "");

		memset(str_rx, 0, sizeof(str_rx));
		memset(str_tx, 0, sizeof(str_tx));
		format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_RX_EMPTY]);
		strlcpy(str_rx, format_stats, sizeof(str_rx));
		format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_TX_EMPTY]);
		strlcpy(str_tx, format_stats, sizeof(str_tx));
		nssinfo_stats_print(nssinfo_summary_fmt, " buf_emty", str_rx, str_tx, "", "");

		memset(str_rx, 0, sizeof(str_rx));
		memset(str_tx, 0, sizeof(str_tx));
		format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_RX_PACKET]);
		strlcpy(str_rx, format_stats, sizeof(str_rx));
		format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_TX_PACKET]);
		strlcpy(str_tx, format_stats, sizeof(str_tx));
		nssinfo_stats_print(nssinfo_summary_fmt, " buf_pkt", str_rx, str_tx, "", "");

		memset(str_rx, 0, sizeof(str_rx));
		format_stats = nssinfo_format_stats(drv_stats[NSS_STATS_DRV_RX_STATUS]);
		strlcpy(str_rx, format_stats, sizeof(str_rx));
		nssinfo_stats_print(nssinfo_summary_fmt, " status_sync", str_rx, "", "", "");
	}
	pthread_mutex_unlock(&n2h_lock);
}

/*
 * nssinfo_n2h_stats_notify()
 *	N2H stats notify callback function.
 */
static void nssinfo_n2h_stats_notify(void *data)
{
	uint64_t *node_stats;
	struct nss_n2h_stats_notification *nss_stats = (struct nss_n2h_stats_notification *)data;
	struct node *n2h_node;
	struct node **n2h_ptr;

	if (!nssinfo_coreid_ifnum_valid(nss_stats->core_id, NSS_N2H_INTERFACE)) {
		return;
	}

	pthread_mutex_lock(&n2h_lock);
	n2h_ptr = &nodes[nss_stats->core_id][NSS_N2H_INTERFACE];
	n2h_node = *n2h_ptr;
	if (n2h_node) {
		memcpy(n2h_node->node_stats, &nss_stats->n2h_stats, sizeof(nss_stats->n2h_stats));
		memcpy(drv_stats, &nss_stats->drv_stats, sizeof(nss_stats->drv_stats));
		pthread_mutex_unlock(&n2h_lock);
		return;
	}
	pthread_mutex_unlock(&n2h_lock);

	n2h_node = (struct node *)calloc(1, sizeof(struct node));
	if (!n2h_node) {
		nssinfo_warn("Failed to allocate memory for N2H node\n");
		return;
	}

	node_stats = (uint64_t *)malloc(sizeof(nss_stats->n2h_stats));
	if (!node_stats) {
		nssinfo_warn("Failed to allocate memory for n2h node stats\n");
		goto n2h_node_free;
	}

	memcpy(node_stats, &nss_stats->n2h_stats, sizeof(nss_stats->n2h_stats));
	memcpy(drv_stats, &nss_stats->drv_stats, sizeof(nss_stats->drv_stats));
	n2h_node->node_stats = node_stats;
	n2h_node->subsystem_id = NSS_NLCMN_SUBSYS_N2H;

	/*
	 * Notify is guaranteed to be single threaded via Netlink listen callback
	 */
	pthread_mutex_lock(&n2h_lock);
	*n2h_ptr = n2h_node;
	pthread_mutex_unlock(&n2h_lock);
	return;

n2h_node_free:
	free(n2h_node);
}

/*
 * nssinfo_n2h_destroy()
 *	Destroy N2H node.
 */
static void nssinfo_n2h_destroy(uint32_t core_id, uint32_t if_num)
{
	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].is_inited) {
		nssinfo_node_stats_destroy(&n2h_lock, core_id, NSS_N2H_INTERFACE);
	}
}

/*
 * nssinfo_n2h_deinit()
 *	Deinitialize n2h module.
 */
void nssinfo_n2h_deinit(void *data)
{
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].is_inited) {
		pthread_mutex_destroy(&n2h_lock);
		nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].is_inited = false;
	}

	nss_nlmcast_sock_leave_grp(ctx, NSS_NLN2H_MCAST_GRP);
}

/*
 * nssinfo_n2h_init()
 *	Initialize N2H module.
 */
int nssinfo_n2h_init(void *data)
{
	int error;
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	/*
	 * Subscribe for N2H MCAST group.
	 */
	nss_nlsock_set_family(&ctx->sock, NSS_NLN2H_FAMILY);
	error = nss_nlmcast_sock_join_grp(ctx, NSS_NLN2H_MCAST_GRP);
	if (error) {
		nssinfo_warn("Unable to join N2H mcast group.\n");
		return error;
	}

	if (nssinfo_stats_info_init(nssinfo_n2h_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/n2h") != 0) {
		goto fail;
	}

	if (pthread_mutex_init(&n2h_lock, NULL) != 0) {
		nssinfo_warn("Mutex init has failed for n2h\n");
		goto fail;
	}

	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].display = nssinfo_n2h_stats_display;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].notify = nssinfo_n2h_stats_notify;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].destroy = nssinfo_n2h_destroy;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_N2H].is_inited = true;
	return 0;
fail:
	nss_nlmcast_sock_leave_grp(ctx, NSS_NLN2H_MCAST_GRP);
	return -1;
}
