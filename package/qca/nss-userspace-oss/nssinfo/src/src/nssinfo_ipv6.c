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
 * @file NSSINFO ipv6 handler
 */
#include "nssinfo.h"

static pthread_mutex_t ipv6_lock;
static struct nssinfo_stats_info nss_stats_str_node[NSS_STATS_NODE_MAX];
static struct nssinfo_stats_info nss_ipv6_stats_str[NSS_IPV6_STATS_MAX];
static struct nssinfo_stats_info nss_ipv6_exception_stats_str[NSS_IPV6_EXCEPTION_EVENT_MAX];

/*
 * nssinfo_ipv6_stats_display()
 *	IPv6 display callback function.
 */
static void nssinfo_ipv6_stats_display(int core, char *input)
{
	struct node *ipv6_node;

	if (input && strncmp(input, nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].subsystem_name, strlen(input))) {
		++invalid_input;
		nssinfo_trace("Invalid node name: %s\n", input);
		return;
	}

	pthread_mutex_lock(&ipv6_lock);
	ipv6_node = nodes[core][NSS_IPV6_RX_INTERFACE];
	if (!ipv6_node) {
		pthread_mutex_unlock(&ipv6_lock);
		return;
	}

	if (display_all_stats) {
		nssinfo_print_all("ipv6", "ipv6 Common Stats", nss_stats_str_node, NSS_STATS_NODE_MAX, (uint64_t *)ipv6_node->cmn_node_stats);
		nssinfo_print_all("ipv6", "ipv6 Special Stats", nss_ipv6_stats_str, NSS_IPV6_STATS_MAX, (uint64_t *)ipv6_node->node_stats);
		nssinfo_print_all("ipv6", "ipv6 Exception Stats", nss_ipv6_exception_stats_str, NSS_IPV6_EXCEPTION_EVENT_MAX, (uint64_t *)ipv6_node->exception_stats);

		pthread_mutex_unlock(&ipv6_lock);
		return;
	}

	nssinfo_print_summary("ipv6", (uint64_t *)ipv6_node->cmn_node_stats, (uint64_t *)ipv6_node->exception_stats, NSS_IPV6_EXCEPTION_EVENT_MAX);
	pthread_mutex_unlock(&ipv6_lock);
}

/*
 * nssinfo_ipv6_stats_notify()
 * 	IPv6 stats notify callback function.
 */
static void nssinfo_ipv6_stats_notify(void *data)
{
	uint64_t *cmn_node_stats, *node_stats, *exception_stats;
	struct nss_nlipv6_rule *rule = (struct nss_nlipv6_rule *)data;
	struct node *ipv6_node;
	struct node **ipv6_ptr;

	if (!nssinfo_coreid_ifnum_valid(rule->stats.core_id, NSS_IPV6_RX_INTERFACE)) {
		return;
	}

	pthread_mutex_lock(&ipv6_lock);
	ipv6_ptr = &nodes[rule->stats.core_id][NSS_IPV6_RX_INTERFACE];
	ipv6_node = *ipv6_ptr;
	if (ipv6_node) {
		memcpy(ipv6_node->cmn_node_stats, &rule->stats.cmn_node_stats, sizeof(rule->stats.cmn_node_stats));
		memcpy(ipv6_node->node_stats, &rule->stats.special_stats, sizeof(rule->stats.special_stats));
		memcpy(ipv6_node->exception_stats, &rule->stats.exception_stats, sizeof(rule->stats.exception_stats));
		pthread_mutex_unlock(&ipv6_lock);
		return;
	}
	pthread_mutex_unlock(&ipv6_lock);

	ipv6_node = (struct node *)calloc(1, sizeof(struct node));
	if (!ipv6_node) {
		nssinfo_warn("Failed to allocate memory for ipv6 node\n");
		return;
	}

	cmn_node_stats = (uint64_t *)malloc(sizeof(rule->stats.cmn_node_stats));
	if (!cmn_node_stats) {
		nssinfo_warn("Failed to allocate memory for ipv6 common node statistics\n");
		goto ipv6_node_free;
	}

	node_stats = (uint64_t *)malloc(sizeof(rule->stats.special_stats));
	if (!node_stats) {
		nssinfo_warn("Failed to allocate memory for ipv6 special stats\n");
		goto cmn_node_stats_free;
	}

	exception_stats = (uint64_t *)malloc(sizeof(rule->stats.exception_stats));
	if (!exception_stats) {
		nssinfo_warn("Failed to allocate memory for ipv6 exception stats\n");
		goto node_stats_free;
	}

	memcpy(cmn_node_stats, &rule->stats.cmn_node_stats, sizeof(rule->stats.cmn_node_stats));
	memcpy(node_stats, &rule->stats.special_stats, sizeof(rule->stats.special_stats));
	memcpy(exception_stats, &rule->stats.exception_stats, sizeof(rule->stats.exception_stats));
	ipv6_node->cmn_node_stats = cmn_node_stats;
	ipv6_node->node_stats = node_stats;
	ipv6_node->exception_stats = exception_stats;
	ipv6_node->subsystem_id = NSS_NLCMN_SUBSYS_IPV6;

	/*
	 * Notifify is guaranteed to be single threaded via Netlink listen callback
	 */
	pthread_mutex_lock(&ipv6_lock);
	*ipv6_ptr = ipv6_node;
	pthread_mutex_unlock(&ipv6_lock);
	return;

node_stats_free:
	free(node_stats);

cmn_node_stats_free:
	free(cmn_node_stats);

ipv6_node_free:
	free(ipv6_node);
}

/*
 * nssinfo_ipv6_destroy()
 *	Destroy IPv6 node.
 */
static void nssinfo_ipv6_destroy(uint32_t core_id, uint32_t if_num)
{
	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].is_inited) {
		nssinfo_node_stats_destroy(&ipv6_lock, core_id, NSS_IPV6_RX_INTERFACE);
	}
}

/*
 * nssinfo_ipv6_deinit()
 *	Deinitialize ipv6 module.
 */
void nssinfo_ipv6_deinit(void *data)
{
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	if (nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].is_inited) {
		pthread_mutex_destroy(&ipv6_lock);
		nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].is_inited = false;
	}

	nss_nlmcast_sock_leave_grp(ctx, NSS_NLIPV6_MCAST_GRP);
}

/*
 * nssinfo_ipv6_init()
 *	Initialize IPv6 module.
 */
int nssinfo_ipv6_init(void *data)
{
	int error;
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	/*
	 * Subscribe for IPV6 MCAST group.
	 */
	nss_nlsock_set_family(&ctx->sock, NSS_NLIPV6_FAMILY);
	error = nss_nlmcast_sock_join_grp(ctx, NSS_NLIPV6_MCAST_GRP);
	if (error) {
		nssinfo_warn("Unable to join IPv6 mcast group\n");
		return error;
	}

	if (nssinfo_stats_info_init(nss_stats_str_node,
				"/sys/kernel/debug/qca-nss-drv/strings/common_node_stats") != 0) {
		goto fail;
	}

	if (nssinfo_stats_info_init(nss_ipv6_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/ipv6/special_stats_str") != 0) {
		goto fail;
	}

	if (nssinfo_stats_info_init(nss_ipv6_exception_stats_str,
				"/sys/kernel/debug/qca-nss-drv/strings/ipv6/exception_stats_str") != 0) {
		goto fail;
	}

	if (pthread_mutex_init(&ipv6_lock, NULL) != 0) {
		nssinfo_warn("Mutex init has failed for IPV6\n");
		goto fail;
	}

	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].display = nssinfo_ipv6_stats_display;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].notify = nssinfo_ipv6_stats_notify;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].destroy = nssinfo_ipv6_destroy;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_IPV6].is_inited = true;
	return 0;
fail:
	nss_nlmcast_sock_leave_grp(ctx, NSS_NLIPV6_MCAST_GRP);
	return -1;
}
