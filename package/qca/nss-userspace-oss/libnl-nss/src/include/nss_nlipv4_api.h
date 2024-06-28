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

#ifndef __NSS_NLIPV4_API_H__
#define __NSS_NLIPV4_API_H__

#define NSS_IPV4_RULE_CREATE_IDENTIFIER_VALID 0x1000	/**< Identifier is valid. */

/** @addtogroup chapter_nlipv4
 This chapter describes IPv4 APIs in the user space.
 These APIs are wrapper functions for IPv4 family specific operations.
*/

/** @addtogroup nss_nlipv4_datatypes @{ */

/**
 * Response callback for IPv4.
 *
 * @param[in] user_ctx User context (provided at socket open).
 * @param[in] rule IPv4 rule.
 * @param[in] resp_ctx User data per callback.
 *
 * @return
 * None.
 */
typedef void (*nss_nlipv4_resp_t)(void *user_ctx, struct nss_nlipv4_rule *rule, void *resp_ctx);

/**
 * Event callback for IPv4.
 *
 * @param[in] user_ctx User context (provided at socket open).
 * @param[in] rule IPv4 rule.
 *
 * @return
 * None.
 */
typedef void (*nss_nlipv4_event_t)(void *user_ctx, struct nss_nlipv4_rule *rule);

/**
 * NSS NL IPv4 response.
 */
struct nss_nlipv4_resp {
	void *data;		/**< Response context. */
	nss_nlipv4_resp_t cb;	/**< Response callback. */
};

/**
 * NSS NL IPv4 context.
 */
struct nss_nlipv4_ctx {
	struct nss_nlsock_ctx sock;	/**< NSS socket context. */
	nss_nlipv4_event_t event;	/**< NSS event callback function. */
};

/** @} *//* end_addtogroup nss_nlipv4_datatypes */
/** @addtogroup nss_nlipv4_functions @{ */

/**
 * Opens NSS NL IPv4 socket.
 *
 * @param[in] ctx NSS NL socket context allocated by the caller.
 * @param[in] user_ctx User context stored per socket.
 * @param[in] event_cb Event callback handler.
 *
 * @return
 * Status of the open call.
 */
int nss_nlipv4_sock_open(struct nss_nlipv4_ctx *ctx, void *user_ctx, nss_nlipv4_event_t event_cb);

/**
 * Closes NSS NL IPv4 socket.
 *
 * @param[in] ctx NSS NL context.
 *
 * @return
 * None.
 */
void nss_nlipv4_sock_close(struct nss_nlipv4_ctx *ctx);

/**
 * Sends an IPv4 rule synchronously to NSS NETLINK.
 *
 * @param[in] ctx NSS NL IPv4 context.
 * @param[in] rule IPv4 rule.
 * @param[in] cb Response callback handler.
 * @param[in] data Response data per callback.
 *
 * @return
 * Send status:
 * - 0 -- Success.
 * - Negative version error (-ve) -- Failure.
 */
int nss_nlipv4_sock_send(struct nss_nlipv4_ctx *ctx, struct nss_nlipv4_rule *rule, nss_nlipv4_resp_t cb, void *data);

/**
 * Initializes IPv4 rule message.
 *
 * @param[in] rule IPv4 rule.
 * @param[in] type Command type.
 *
 * @return
 * None.
 */
void nss_nlipv4_init_rule(struct nss_nlipv4_rule *rule, enum nss_ipv4_message_types type);

/**
 * Initializes connection rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_conn_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->valid_flags |= NSS_IPV4_RULE_CREATE_CONN_VALID;
}

/**
 * Enables route flow.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_route_flow_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->rule_flags |= NSS_IPV4_RULE_CREATE_FLAG_ROUTED;
}

/**
 * Enables bridge flow.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_bridge_flow_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->rule_flags |= NSS_IPV4_RULE_CREATE_FLAG_BRIDGE_FLOW;
}

/**
 * Initializes TCP protocol rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_tcp_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->valid_flags |= NSS_IPV4_RULE_CREATE_TCP_VALID;
}

/**
 * Initializes PPPoE rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_pppoe_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->valid_flags |= NSS_IPV4_RULE_CREATE_PPPOE_VALID;
}

/**
 * Initializes QoS rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_qos_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->valid_flags |= NSS_IPV4_RULE_CREATE_QOS_VALID;
}

/**
 * Initializes DSCP rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_dscp_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->valid_flags |= NSS_IPV4_RULE_CREATE_DSCP_MARKING_VALID;
}

/**
 * Initializes VLAN rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_vlan_rule(struct nss_ipv4_rule_create_msg *create)
{
	struct nss_ipv4_vlan_rule *primary;
	struct nss_ipv4_vlan_rule *secondary;

	primary = &create->vlan_primary_rule;
	secondary = &create->vlan_secondary_rule;

	create->valid_flags |= NSS_IPV4_RULE_CREATE_VLAN_VALID;

	/*
	 * set the tags to default values
	 */
	primary->ingress_vlan_tag = NSS_NLIPV4_VLAN_ID_NOT_CONFIGURED;
	primary->egress_vlan_tag = NSS_NLIPV4_VLAN_ID_NOT_CONFIGURED;

	secondary->ingress_vlan_tag = NSS_NLIPV4_VLAN_ID_NOT_CONFIGURED;
	secondary->egress_vlan_tag = NSS_NLIPV4_VLAN_ID_NOT_CONFIGURED;
}

/**
 * Initializes Identifier rule for create message.
 *
 * @param[in] create Creates message.
 *
 * @return
 * None.
 */
static inline void nss_nlipv4_init_identifier_rule(struct nss_ipv4_rule_create_msg *create)
{
	create->valid_flags |= NSS_IPV4_RULE_CREATE_IDENTIFIER_VALID;
}

/** @} *//* end_addtogroup nss_nlipv4_functions */

#endif /* __NSS_NLIPV4_API_H__ */
