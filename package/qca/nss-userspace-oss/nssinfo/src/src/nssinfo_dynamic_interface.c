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
 * @file NSSINFO dynamic interface handler
 */
#include "nssinfo.h"
#include <nss_nldynamic_interface_if.h>

/*
 * nssinfo_dynamic_interface_destroy_notify()
 *	Dynamic interface notify callback function.
 */
static void nssinfo_dynamic_interface_destroy_notify(void *data)
{
	struct nss_dynamic_interface_notification *nss_info = (struct nss_dynamic_interface_notification *)data;
	struct node *node = nodes[nss_info->core_id][nss_info->if_num];

	if (!node) {
		return;
	}

	nssinfo_subsystem_array[node->subsystem_id].destroy(nss_info->core_id, nss_info->if_num);
}

/*
 * nssinfo_dynamic_interface_deinit()
 *	Deinitialize dynamic_interface module.
 */
void nssinfo_dynamic_interface_deinit(void *data)
{
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	nss_nlmcast_sock_leave_grp(ctx, NSS_NLDYNAMIC_INTERFACE_MCAST_GRP);
}

/*
 * nssinfo_dynamic_interface_init()
 *	Initialize dynamic interface module.
 */
int nssinfo_dynamic_interface_init(void *data)
{
	int error;
	struct nss_nlmcast_ctx *ctx = (struct nss_nlmcast_ctx *)data;

	/*
	 * Subscribe for dynamic interface multicast group.
	 */
	nss_nlsock_set_family(&ctx->sock, NSS_NLDYNAMIC_INTERFACE_FAMILY);
	error = nss_nlmcast_sock_join_grp(ctx, NSS_NLDYNAMIC_INTERFACE_MCAST_GRP);
	if (error) {
		nssinfo_warn("Unable to join dynamic interface multicast group.\n");
		return error;
	}

	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE].notify = nssinfo_dynamic_interface_destroy_notify;
	nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE].is_inited = true;
	return 0;
}
