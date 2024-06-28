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

/*
 * @file netlink socket handler
 */

#include <nss_nlbase.h>
#include <nss_nlsock_api.h>

/*
 * nss_nlsock_deinit()
 *	de-initialize the socket
 */
static void nss_nlsock_deinit(struct nss_nlsock_ctx *sock)
{
	assert(sock);

	nl_cb_put(sock->nl_cb);
	sock->nl_cb = NULL;

	nl_socket_free(sock->nl_sk);
	sock->nl_sk = NULL;
}

/*
 * nss_nlsock_init()
 *	initialize the socket and callback
 */
static int nss_nlsock_init(struct nss_nlsock_ctx *sock, nl_recvmsg_msg_cb_t cb)
{
	int error;

	assert(sock);

	/*
	 * Initialize spinlock
	 */
	error = pthread_spin_init(&sock->lock, PTHREAD_PROCESS_PRIVATE);
	if (error) {
		nss_nlsock_log_error("Failed to init spinlock for family(%s), error %d\n", sock->family_name, error);
		return error;
	}

	sock->pid = getpid();

	/*
	 * create callback
	 */
	sock->nl_cb = nl_cb_alloc(NL_CB_CUSTOM);
	if (!sock->nl_cb) {
		nss_nlsock_log_error("%d:failed to alloc callback for family(%s)\n",sock->pid, sock->family_name);
		goto fail1;
	}

	/*
	 * register callback
	 */
	nl_cb_set(sock->nl_cb, NL_CB_VALID, NL_CB_CUSTOM, cb, sock);

	/*
	 * Create netlink socket
	 */
	sock->nl_sk = nl_socket_alloc_cb(sock->nl_cb);
	if (!sock->nl_sk) {
		nss_nlsock_log_error("%d:failed to alloc socket for family(%s)\n", sock->pid, sock->family_name);
		goto fail2;
	}

	sock->ref_cnt = 1;

	/*
	 * is_avail is set to indicate the socket is available for send/listen
	 */
	sock->is_avail = true;
	return 0;

fail2:
	nl_cb_put(sock->nl_cb);
	sock->nl_cb = NULL;
fail1:
	pthread_spin_destroy(&sock->lock);
	sock->lock = (pthread_spinlock_t)0;
	return -ENOMEM;
}

/*
 * nss_nlsock_deref()
 *	decrement the reference count and free socket resources if '0'
 */
static inline void nss_nlsock_deref(struct nss_nlsock_ctx *sock)
{
	assert(sock->ref_cnt > 0);

	pthread_spin_lock(&sock->lock);
	if (--sock->ref_cnt) {
		pthread_spin_unlock(&sock->lock);
		return;
	}

	/*
	 * When there are no more references on the socket,
	 * deinitialize the socket and destroy the spin lock
	 * created during nss_nlsock_init
	 */
	nss_nlsock_deinit(sock);
	pthread_spin_unlock(&sock->lock);

	pthread_spin_destroy(&sock->lock);
	sock->lock = (pthread_spinlock_t)0;
}

/*
 * nss_nlsock_ref()
 *	Increment the reference count.
 *
 * if ref_cnt == 0, return false
 * if ref_cnt != 0, increment the socket reference count and return true
 */
static inline bool nss_nlsock_ref(struct nss_nlsock_ctx *sock)
{
	/*
	 * if ref count is 0, it means there are no references
	 * on the socket and so return false. Socket will eventually be
	 * freed by nss_nlsock_deinit else increment the ref count
	 */
	pthread_spin_lock(&sock->lock);
	if (sock->ref_cnt == 0) {
		pthread_spin_unlock(&sock->lock);
		return false;
	}

	sock->ref_cnt++;
	pthread_spin_unlock(&sock->lock);

	return true;
}

/*
 * nss_nlsock_listen_callback()
 *	listen to responses from the netlink socket
 *
 * The API keeps listening for the responses on the netlink socket
 * until socket close is initiated and there are no more
 * responses on the socket
 */
static void *nss_nlsock_listen_callback(void *arg)
{
	struct nss_nlsock_ctx *sock = (struct nss_nlsock_ctx *)arg;
	assert(sock);

	/*
	 * drain responses on the socket
	 */
	for (;;) {
		/*
		 * if, socket is freed then break out
		 */
		if (!nss_nlsock_ref(sock)) {
			break;
		}

		/*
		 * get or block for pending messages
		 */
		nl_recvmsgs(sock->nl_sk, sock->nl_cb);
		nss_nlsock_deref(sock);
	}

	return NULL;
}

/*
 * nss_nlsock_msg_init()
 *	Initialize parameters to send message down the socket
 */
static int nss_nlsock_msg_init(struct nss_nlsock_ctx *sock, struct nss_nlcmn *cm, void *data, struct nl_msg *msg)
{
	int pid = sock->pid;
	void *user_hdr;
	uint32_t ver;
	uint8_t cmd;
	int len;

	ver = nss_nlcmn_get_ver(cm);
	len = nss_nlcmn_get_len(cm);
	cmd = nss_nlcmn_get_cmd(cm);

	/*
	 * create space for user header
	 */
	user_hdr = genlmsg_put(msg, pid, NL_AUTO_SEQ, sock->family_id, len, 0, cmd, ver);
	if (!user_hdr) {
		nss_nlsock_log_error("%d:failed to put message header of len(%d)\n", pid, len);
		return -ENOMEM;

	}

	memcpy(user_hdr, data, len);
	return 0;
}

/*
 * nss_nlsock_leave_grp()
 *	nl socket unsubscribe for the multicast group
 */
int nss_nlsock_leave_grp(struct nss_nlsock_ctx *sock, char *grp_name)
{
	int error;

	assert(sock->ref_cnt > 0);

	/*
	 * Resolve the group
	 */
	sock->grp_id = genl_ctrl_resolve_grp(sock->nl_sk, sock->family_name, grp_name);
	if (sock->grp_id < 0) {
		nss_nlsock_log_error("failed to resolve group(%s)\n", grp_name);
		return -EINVAL;
	}

	/*
	 * Unsubscribe for the mcast async events
	 */
	error = nl_socket_drop_memberships(sock->nl_sk, sock->grp_id, 0);
	if (error < 0) {
		nss_nlsock_log_error("failed to deregister grp(%s)\n", grp_name);
		return error;
	}

	return 0;
}

/*
 * nss_nlsock_join_grp()
 *	nl socket subscribe for the multicast group
 */
int nss_nlsock_join_grp(struct nss_nlsock_ctx *sock, char *grp_name)
{
	int error;

	assert(sock->ref_cnt > 0);

	/*
	 * Resolve the group
	 */
	sock->grp_id = genl_ctrl_resolve_grp(sock->nl_sk, sock->family_name, grp_name);
	if (sock->grp_id < 0) {
		nss_nlsock_log_error("failed to resolve group(%s)\n", grp_name);
		return -EINVAL;
	}

	/*
	 * Subscribe for the mcast async events
	 */
	error = nl_socket_add_memberships(sock->nl_sk, sock->grp_id, 0);
	if (error < 0) {
		nss_nlsock_log_error("failed to register grp(%s)\n", grp_name);
		return error;
	}

	return 0;
}

/*
 * nss_nlsock_open_mcast()
 *	Open the socket for async events
 */
int nss_nlsock_open_mcast(struct nss_nlsock_ctx *sock, nl_recvmsg_msg_cb_t cb)
{
	int error;
	assert(sock);

	error = nss_nlsock_init(sock, cb);
	if (error) {
		nss_nlsock_log_error("%d:failed to initialize socket(%s)\n", sock->pid, sock->family_name);
		return error;
	}

	/*
	 * Disable seq number and auto ack checks for sockets listening for mcast events
	 */
	nl_socket_disable_seq_check(sock->nl_sk);
	nl_socket_disable_auto_ack(sock->nl_sk);

	/*
	 * Connect the socket with the netlink bus
	 */
	if (genl_connect(sock->nl_sk)) {
		nss_nlsock_log_error("%d:failed to connect socket for family(%s)\n", sock->pid, sock->family_name);
		error = -EBUSY;
		goto free_sock;
	}
	return 0;

free_sock:
	nss_nlsock_deref(sock);
	return error;
}

/*
 * nss_nlsock_send()
 *	send a message synchronously through the socket
 */
int nss_nlsock_send(struct nss_nlsock_ctx *sock, struct nss_nlcmn *cm, void *data, bool has_resp)
{
	int pid = sock->pid;
	struct nl_msg *msg;
	int error;

	/*
	 * return -EBUSY if the socket is currently unavailable for sending message
	 */
	pthread_spin_lock(&sock->lock);
	if (!sock->is_avail) {
		pthread_spin_unlock(&sock->lock);
		return -EBUSY;
	}

	/*
	 * To indicate the socket is unavailable until the current thread completes the send/listen.
	 * This is to prevent other threads from simultaneous send/listen.
	 */
	sock->is_avail = false;
	pthread_spin_unlock(&sock->lock);

	/*
	 * allocate new message buffer
	 */
	msg = nlmsg_alloc();
	if (!msg) {
		nss_nlsock_log_error("%d:failed to allocate message buffer\n", pid);
		sock->is_avail = true;
		return -ENOMEM;
	}

	/*
	 * Holds a reference on the socket until msg is sent down to the kernel
	 */
	if (!nss_nlsock_ref(sock)) {
		nss_nlsock_log_error("%d:failed to get NL socket\n", pid);
		nlmsg_free(msg);
		sock->is_avail = true;
		return -EINVAL;
	}

	/*
	 * Initialize message parameters
	 */
	error = nss_nlsock_msg_init(sock, cm, data, msg);
	if (error) {
		nss_nlsock_log_error("%d:failed to initialize message structure (family:%s, error:%d)\n",
					pid, sock->family_name, error);
		nss_nlsock_deref(sock);
		nlmsg_free(msg);
		sock->is_avail = true;
		return error;
	}

	/*
	 * If has_resp is true and msg is sent to FW, then there will be two
	 * netlink messages coming from kernel - FW response and ACK
	 * If msg fails in netlink, then error will be returned from kernel.
	 * If has_resp is false, then there is only one netlink message
	 * coming from kernel: either ACK or error
	 * In case firmware response is sent before nl_recvmsgs is invoked,
	 * the response will be queued until the listener is available.
	 */
	error = nl_send_sync(sock->nl_sk, msg);
	if (error < 0) {
		nss_nlsock_log_error("%d:failed to send (family:%s, error:%d)\n", pid, sock->family_name, error);
		nss_nlsock_deref(sock);
		sock->is_avail = true;
		return error;
	}

	if (has_resp) {
		nl_recvmsgs(sock->nl_sk, sock->nl_cb);
	}

	nss_nlsock_deref(sock);
	sock->is_avail = true;
	return 0;
}

/*
 * nss_nlsock_listen()
 *	listen for async events on the socket
 */
int nss_nlsock_listen(struct nss_nlsock_ctx *sock)
{
	int error;

	assert(sock->ref_cnt > 0);

	/*
	 * return -EBUSY if the socket is currently unavailable for listening
	 */
	if (!sock->is_avail) {
		return -EBUSY;
	}

	/*
	 * To indicate the socket is unavailable until the current thread completes the send/listen.
	 * This is to prevent other threads from simultaneous send/listen.
	 */
	sock->is_avail = false;

	/*
	 * Create an async thread for clearing the pending resp on the socket asynchronously
	 */
	error = pthread_create(&sock->thread, NULL, nss_nlsock_listen_callback, sock);
	if (error) {
		nss_nlsock_log_error("%d:failed to create sync thread for family(%s)\n", sock->pid, sock->family_name);
		return error;
	}

	return 0;
}

/*
 * nss_nlsock_close()
 *	close the allocated socket and all associated memory
 */
void nss_nlsock_close(struct nss_nlsock_ctx *sock)
{
	assert(sock);
	assert(sock->nl_sk);
	assert(sock->ref_cnt > 0);

	/*
	 * put the reference down for the socket
	 */
	nss_nlsock_deref(sock);

	/*
	 * wait for the async thread to complete
	 */
	if (sock->thread) {
		pthread_join(sock->thread, NULL);
		sock->thread = NULL;
	}
}

/*
 * nss_nlsock_open()
 *	open a socket for unicast communication with the generic netlink framework
 */
int nss_nlsock_open(struct nss_nlsock_ctx *sock, nl_recvmsg_msg_cb_t cb)
{
	int error = 0;
	assert(sock);

	error = nss_nlsock_init(sock, cb);
	if (error) {
		nss_nlsock_log_error("%d:failed to initialize socket(%s)\n", sock->pid, sock->family_name);
		return error;
	}

	/*
	 * Connect the socket with the netlink bus
	 */
	if (genl_connect(sock->nl_sk)) {
		nss_nlsock_log_error("%d:failed to connect socket for family(%s)\n", sock->pid, sock->family_name);
		error = -EBUSY;
		goto free_sock;
	}

	/*
	 * resolve the family
	 */
	sock->family_id = genl_ctrl_resolve(sock->nl_sk, sock->family_name);
	if (sock->family_id <= 0) {
		nss_nlsock_log_error("%d:failed to resolve family(%s)\n", sock->pid, sock->family_name);
		error = -EINVAL;
		goto free_sock;
	}

	return 0;

free_sock:

	nss_nlsock_deref(sock);
	return error;
}
