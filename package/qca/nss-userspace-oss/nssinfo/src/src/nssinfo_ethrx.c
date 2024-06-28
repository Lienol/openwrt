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
 * @file NSSINFO Ethernet Rx handler
 */
#include "nssinfo.h"
#include <nss_eth_rx.h>
#include <nss_nlethrx_if.h>

static pthread_mutex_t eth_rx_lock;
static struct nssinfo_stats_info nss_eth_rx_cmn_stats_str[NSS_STATS_NODE_MAX];
static struct nssinfo_stats_info nss_eth_rx_stats_str[NSS_ETH_RX_STATS_MAX];
static struct nssinfo_stats_info nss_eth_rx_exception_stats_str[NSS_ETH_RX_EXCEPTION_EVENT_MAX];

/*
 * nssinfo_eth_rx_stats_display()
 *	Ethernet Rx display callback function.
 */
static void nssinfo_eth_rx_stats_display(int core, char *input)
{
	struct node *eth_rx_node;

	if (input && strncmp(input, nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].subsystem_name, strlen(input))) {
		++invalid_input;
		nssinfo_trace("Invalid node name: %s\n", input);
		return;
	}

	pthread_mutex_lock(&eth_rx_lock);
	eth_rx_node = nodes[core][NSS_ETH_RX_INTERFACE];
	if (!eth_rx_node) {
		pthread_mutex_unlock(&eth_rx_lock);
		return;
	}

	if (!display_all_stats) {
		nssinfo_print_summary("eth_rx", (uint64_t *)eth_rx_node->cmn_node_stats, (uint64_t *)eth_rx_node->exception_stats, NSS_ETH_RX_EXCEPTION_EVENT_MAX);
		pthread_mutex_unlock(&eth_rx_lock);
		return;
	}

	nssinfo_print_all("eth_rx", "eth_rx Common Stats", nss_eth_rx_cmn_stats_str, NSS_STATS_NODE_MAX, (uint64_t *)eth_rx_node->cmn_node_stats);
	nssinfo_print_all("eth_rx", "eth_rx Special Stats", nss_eth_rx_stats_str, NSS_ETH_RX_STATS_MAX, (uint64_t *)eth_rx_node->node_stats);
	nssinfo_print_all("eth_rx", "eth_rx Exception Stats", nss_eth_rx_exception_stats_str, NSS_ETH_RX_EXCEPTION_EVENT_MAX, (uint64_t *)eth_rx_node->exception_stats);

	pthread_mutex_unlock(&eth_rx_lock);
}

/*
 * nssinfo_eth_rx_stats_notify()
 *	Ethernet Rx statistics notify callback function.
 */
static void nssinfo_eth_rx_stats_notify(void *data)
{
	uint64_t *cmn_node_stats, *node_stats, *exception_stats;
	struct nss_eth_rx_stats_notification *nss_stats = (struct nss_eth_rx_stats_notification *)data;
	struct node *eth_rx_node;
	struct node **eth_rx_ptr;

	if (!nssinfo_coreid_ifnum_valid(nss_stats->core_id, NSS_ETH_RX_INTERFACE)) {
		return;
	}

	pthread_mutex_lock(&eth_rx_lock);
	eth_rx_ptr = &nodes[nss_stats->core_id][NSS_ETH_RX_INTERFACE];
	eth_rx_node = *eth_rx_ptr;
	if (eth_rx_node) {
		memcpy(eth_rx_node->cmn_node_stats, &nss_stats->cmn_node_stats, sizeof(nss_stats->cmn_node_stats));
		memcpy(eth_rx_node->node_stats, &nss_stats->special_stats, sizeof(nss_stats->special_stats));
		memcpy(eth_rx_node->exception_stats, &nss_stats->exception_stats, sizeof(nss_stats->exception_stats));
		pthread_mutex_unlock(&eth_rx_lock);
		return;
	}
	pthread_mutex_unlock(&eth_rx_lock);

	eth_rx_node = (struct node *)calloc(1, sizeof(struct node));
	if (!eth_rx_node) {
		nssinfo_warn("Failed to allocate memory for eth rx node\n");
		return;
	}

	cmn_node_stats = (uint64_t *)malloc(sizeof(nss_stats->cmn_node_stats));
	if (!cmn_node_stats) {
		nssinfo_warn("Failed to allocate memory for eth rx common node statistics\n");
		goto eth_rx_node_free;
	}

	node_stats = (uint64_t *)malloc(sizeof(nss_stats->special_stats));
	if (!node_stats) {
		nssinfo_warn("Failed to allocate memory for eth rx special stats\n");
		goto cmn_node_stats_free;
	}

	exception_stats = (uint64_t *)malloc(sizeof(nss_stats->exception_stats));
	if (!exception_stats) {
		nssinfo_warn("Failed to allocate memory for eth rx exception stats\n");
		goto node_stats_free;
	}

	memcpy(cmn_node_stats, &nss_stats->cmn_node_stats, sizeof(nss_stats->cmn_node_stats));
	memcpy(node_stats, &nss_stats->special_stats, sizeof(nss_stats->special_stats));
	memcpy(exception_stats, &nss_stats->exception_stats, sizeof(nss_stats->exception_stats));
	eth_rx_node->cmn_node_stats = cmn_node_stats;
	eth_rx_node->node_stats = node_stats;
	eth_rx_node->exception_stats = exception_stats;
	eth_rx_node->subsystem_id = NSS_NLCMN_SUBSYS_ETHRX;

	/*
	 * Notifify is guaranteed to be single threaded via Netlink listen callback
	 */
	pthread_mutex_lock(&eth_rx_lock);
	nodes[nss_stats->core_id][NSS_ETH_RX_INTERFACE] = eth_rx_node;
	pthread_mutex_unlock(&eth_rx_lock);
	return;

node_stats_free:
	free(node_stats);

cmn_node_stats_free:
	free(cmn_node_stats);

eth_rx_node_free:
	free(eth_rx_node);
	return;
}

/*
 * nssinfo_eth_rx_destroy()
 *      Destroy ethernet Rx node.
 */
static void nssinfo_eth_rx_destroy(uint32_t core_id, uint32_t if_num)
{
	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].is_inited) {
		nssinfo_node_stats_destroy(&eth_rx_lock, core_id, NSS_ETH_RX_INTERFACE);
	}
}

/*
 * nssinfo_ethrx_deinit()
 *	Deinitialize ethrx module.
 */
void nssinfo_eth_rx_deinit(void *data)
{
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].is_inited) {
		pthread_mutex_destroy(&eth_rx_lock);
		nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].is_inited = false;
	}

	nss_nlmcast_sock_leave_grp(ctx, NSS_NLETHRX_MCAST_GRP);
}

/*
 * nssinfo_eth_rx_init()
 *	Initialize Ethernet Rx module.
 */
int nssinfo_eth_rx_init(void *data)
{
	int error;
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	/*
	 * Subscribe for Ethernet Rx MCAST group.
	 */
	nss_nlsock_set_family(&ctx->sock, NSS_NLETHRX_FAMILY);
	error = nss_nlmcast_sock_join_grp(ctx, NSS_NLETHRX_MCAST_GRP);
	if (error) {
		nssinfo_warn("Unable to join Ethernet Rx mcast group.\n");
		return error;
	}

	if (nssinfo_stats_info_init(nss_eth_rx_cmn_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/common_node_stats") != 0) {
		goto fail;
	}

	if (nssinfo_stats_info_init(nss_eth_rx_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/eth_rx/special_stats_str") != 0) {
		goto fail;
	}

	if (nssinfo_stats_info_init(nss_eth_rx_exception_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/eth_rx/exception_stats_str") != 0) {
		goto fail;
	}

	if (pthread_mutex_init(&eth_rx_lock, NULL) != 0) {
		nssinfo_warn("Mutex init has failed for Ethernet Rx\n");
		goto fail;
	}

	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].display = nssinfo_eth_rx_stats_display;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].notify = nssinfo_eth_rx_stats_notify;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].destroy = nssinfo_eth_rx_destroy;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_ETHRX].is_inited = true;
	return 0;
fail:
	nss_nlmcast_sock_leave_grp(ctx, NSS_NLETHRX_MCAST_GRP);
	return -1;
}
