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
 * @file NSSINFO lso_rx handler
 */
#include "nssinfo.h"
#include <nss_lso_rx.h>
#include <nss_nllso_rx_if.h>

static pthread_mutex_t lso_rx_lock;
static struct nssinfo_stats_info nss_stats_str_node[NSS_STATS_NODE_MAX];
static struct nssinfo_stats_info nss_lso_rx_stats_str[NSS_LSO_RX_STATS_MAX];

/*
 * nssinfo_lso_rx_stats_display()
 *      LSO Rx display callback function.
 */
static void nssinfo_lso_rx_stats_display(int core, char *input)
{
	struct node *lso_rx_node;

	if (input && strncmp(input, nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].subsystem_name, strlen(input))) {
		++invalid_input;
		nssinfo_trace("Invalid node name: %s\n", input);
		return;
	}

	pthread_mutex_lock(&lso_rx_lock);
	lso_rx_node = nodes[core][NSS_LSO_RX_INTERFACE];
	if (!lso_rx_node) {
		pthread_mutex_unlock(&lso_rx_lock);
		nssinfo_error("%s is not running on the NPU\n", input);
		return;
	}

	if (display_all_stats) {
		nssinfo_print_all("lso_rx", "lso_rx Common Stats", nss_stats_str_node, NSS_STATS_NODE_MAX, (uint64_t *)lso_rx_node->cmn_node_stats);
		nssinfo_print_all("lso_rx", "lso_rx Special Stats", nss_lso_rx_stats_str, NSS_LSO_RX_STATS_MAX, (uint64_t *)lso_rx_node->node_stats);
		pthread_mutex_unlock(&lso_rx_lock);
		return;
	}

	nssinfo_print_summary("lso_rx", (uint64_t *)lso_rx_node->cmn_node_stats, NULL, 0);
	pthread_mutex_unlock(&lso_rx_lock);
}

/*
 * nssinfo_lso_rx_stats_notify()
 * 	LSO Rx stats notify callback function.
 */
static void nssinfo_lso_rx_stats_notify(void *data)
{
	uint64_t *cmn_node_stats, *node_stats;
	struct nss_lso_rx_stats_notification *nss_stats = (struct nss_lso_rx_stats_notification *)data;
	struct node *lso_rx_node;
	struct node **lso_rx_ptr;

	if (!nssinfo_coreid_ifnum_valid(nss_stats->core_id, NSS_LSO_RX_INTERFACE)) {
		return;
	}

	pthread_mutex_lock(&lso_rx_lock);
	lso_rx_ptr = &nodes[nss_stats->core_id][NSS_LSO_RX_INTERFACE];
	lso_rx_node = *lso_rx_ptr;
	if (lso_rx_node) {
		memcpy(lso_rx_node->cmn_node_stats, &nss_stats->cmn_node_stats, sizeof(nss_stats->cmn_node_stats));
		memcpy(lso_rx_node->node_stats, &nss_stats->node_stats, sizeof(nss_stats->node_stats));
		pthread_mutex_unlock(&lso_rx_lock);
		return;
	}
	pthread_mutex_unlock(&lso_rx_lock);

	lso_rx_node = (struct node *)calloc(1, sizeof(struct node));
	if (!lso_rx_node) {
		nssinfo_warn("Failed to allocate memory for lso_rx node\n");
		return;
	}

	cmn_node_stats = (uint64_t *)malloc(sizeof(nss_stats->cmn_node_stats));
	if (!cmn_node_stats) {
		nssinfo_warn("Failed to allocate memory for lso_rx common node statistics\n");
		goto lso_rx_node_free;
	}

	node_stats = (uint64_t *)malloc(sizeof(nss_stats->node_stats));
	if (!node_stats) {
		nssinfo_warn("Failed to allocate memory for lso_rx connection stats\n");
		goto cmn_node_stats_free;
	}

	memcpy(cmn_node_stats, &nss_stats->cmn_node_stats, sizeof(nss_stats->cmn_node_stats));
	memcpy(node_stats, &nss_stats->node_stats, sizeof(nss_stats->node_stats));
	lso_rx_node->cmn_node_stats = cmn_node_stats;
	lso_rx_node->node_stats = node_stats;
	lso_rx_node->subsystem_id = NSS_NLCMN_SUBSYS_LSO_RX;

	/*
	 * Notify is guaranteed to be single threaded via Netlink listen callback
	 */
	pthread_mutex_lock(&lso_rx_lock);
	*lso_rx_ptr = lso_rx_node;
	pthread_mutex_unlock(&lso_rx_lock);
	return;

cmn_node_stats_free:
	free(cmn_node_stats);

lso_rx_node_free:
	free(lso_rx_node);
}

/*
 * nssinfo_lso_rx_destroy()
 *	Destroy LSO Rx node.
 */
static void nssinfo_lso_rx_destroy(uint32_t core_id, uint32_t if_num)
{
	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].is_inited) {
		nssinfo_node_stats_destroy(&lso_rx_lock, core_id, NSS_LSO_RX_INTERFACE);
	}
}

/*
 * nssinfo_lso_rx_deinit()
 *	Deinitialize lso_rx module.
 */
void nssinfo_lso_rx_deinit(void *data)
{
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].is_inited) {
		pthread_mutex_destroy(&lso_rx_lock);
		nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].is_inited = false;
	}

	nss_nlmcast_sock_leave_grp(ctx, NSS_NLLSO_RX_MCAST_GRP);
}

/*
 * nssinfo_lso_rx_init()
 *	Initialize LSO Rx module.
 */
int nssinfo_lso_rx_init(void *data)
{
	int error;
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	/*
	 * Subscribe for LSO Rx multicast group.
	 */
	nss_nlsock_set_family(&ctx->sock, NSS_NLLSO_RX_FAMILY);
	error = nss_nlmcast_sock_join_grp(ctx, NSS_NLLSO_RX_MCAST_GRP);
	if (error) {
		nssinfo_warn("Unable to join LSO Rx multicast group\n");
		return error;
	}

	if (nssinfo_stats_info_init(nss_stats_str_node,
				"/sys/kernel/debug/qca-nss-drv/strings/common_node_stats") != 0) {
		goto fail;
	}

	if (nssinfo_stats_info_init(nss_lso_rx_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/lso_rx") != 0) {
		goto fail;
	}

	if (pthread_mutex_init(&lso_rx_lock, NULL) != 0) {
		nssinfo_warn("Mutex init has failed for LSO Rx\n");
		goto fail;
	}

	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].display = nssinfo_lso_rx_stats_display;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].notify = nssinfo_lso_rx_stats_notify;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].destroy = nssinfo_lso_rx_destroy;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_LSO_RX].is_inited = true;
	return 0;
fail:
	nss_nlmcast_sock_leave_grp(ctx, NSS_NLLSO_RX_MCAST_GRP);
	return -1;
}
