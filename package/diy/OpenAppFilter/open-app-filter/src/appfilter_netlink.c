/*
  Copyright (C) 2020 Derry <destan19@126.com>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
*/
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/socket.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <libubox/uloop.h>
#include <libubox/utils.h>
#include <libubus.h>
#include <json-c/json.h>
#include "appfilter_user.h"
#include "appfilter_netlink.h"
#define MAX_NL_RCV_BUF_SIZE 4096

#define REPORT_INTERVAL_SECS 60
void appfilter_nl_handler(struct uloop_fd *u, unsigned int ev)
{
    int ret;
	int i;
	char buf[MAX_NL_RCV_BUF_SIZE];
	struct sockaddr_nl nladdr;
	struct iovec iov = {buf, sizeof(buf)};
	struct nlmsghdr *h;
    char *mac = NULL;
	struct msghdr msg = {
		.msg_name    = &nladdr,
		.msg_namelen = sizeof(nladdr),
		.msg_iov     = &iov,
		.msg_iovlen  = 1,
	};
	
	do{
        ret = recvmsg(u->fd, &msg, 0);
    } while ((-1 == ret) && (EINTR == errno));
    
	if (ret < 0) {
		printf("recv msg error\n");
		return;
	}
	else if (0 == ret) {
		return;
	}
	
	h = (struct nlmsghdr *)buf;
    char *kmsg = (char *)NLMSG_DATA(h);
    struct af_msg_hdr *af_hdr = (struct af_msg_hdr *)kmsg;
    if (af_hdr->magic != 0xa0b0c0d0){
        printf("magic error %x\n", af_hdr->magic);
		return;
    }
    if (af_hdr->len <= 0 || af_hdr->len >= MAX_OAF_NETLINK_MSG_LEN){
        printf("data len error\n");
        return;
    }

    char *kdata = kmsg + sizeof(struct af_msg_hdr);
	struct json_object *root = json_tokener_parse(kdata);
	if (!root){
		printf("parse json failed:%s", kdata);
		return;
	}
    
	struct json_object *mac_obj = json_object_object_get(root,"mac");
    
	if (!mac_obj){
		printf("parse mac obj failed\n");
		json_object_put(root);
        return;
    }
    
    mac = json_object_get_string(mac_obj);
    
    dev_node_t *node = find_dev_node(mac);
    
    if (!node){
	    node = add_dev_node(mac);
    }
    
    struct json_object *ip_obj = json_object_object_get(root, "ip");
    if (ip_obj)
        strncpy(node->ip, json_object_get_string(ip_obj), sizeof(node->ip));
    struct json_object *visit_array = json_object_object_get(root, "visit_info");
	if (!visit_array){
		json_object_put(root);
		return;
	}
	for (i = 0; i < json_object_array_length(visit_array); i++){
		struct json_object *visit_obj = json_object_array_get_idx(visit_array, i);
		struct json_object *appid_obj = json_object_object_get(visit_obj, "appid");
        struct json_object *action_obj = json_object_object_get(visit_obj, "latest_action");
		struct json_object *up_obj = json_object_object_get(visit_obj, "up_bytes");
        struct json_object *down_obj = json_object_object_get(visit_obj, "down_bytes");
        struct timeval cur_time;
        
        gettimeofday(&cur_time, NULL);
        int appid = json_object_get_int(appid_obj);
        int action = json_object_get_int(action_obj);

		int type = appid / 1000;
		int id = appid % 1000;
        
		node->stat[type - 1][id - 1].total_time += REPORT_INTERVAL_SECS;
        
	//	node->stat[type - 1][id - 1].total_down_bytes += json_object_get_int(down_obj);
	//	node->stat[type - 1][id - 1].total_up_bytes += json_object_get_int(up_obj);

		int hash = hash_appid(appid);
		visit_info_t *head = node->visit_htable[hash];
		if (head && (cur_time.tv_sec - head->latest_time) < 300){
			printf("update visit info curtime=%d, last time=%d\n", cur_time.tv_sec, head->latest_time);
				head->latest_time = cur_time.tv_sec;
		}
		else{
			visit_info_t *visit_node = (visit_info_t *)calloc(1, sizeof(visit_info_t));
			visit_node->action = action;
			visit_node->appid = appid;
			visit_node->latest_time = cur_time.tv_sec;
			visit_node->first_time = cur_time.tv_sec - MIN_VISIT_TIME;
			visit_node->next = NULL;
			add_visit_info_node(&node->visit_htable[hash], visit_node);
			//printf("add  visit info curtime=%d\n", cur_time.tv_sec);
		}
	}
    
	json_object_put(root);
}


int appfilter_nl_init(void)
{
    int fd;
	struct sockaddr_nl nls;
    fd = socket(AF_NETLINK, SOCK_RAW, OAF_NETLINK_ID);
    if(fd < 0)
    {
        printf("Connect netlink %d failed %s", OAF_NETLINK_ID, strerror(errno));
	    exit(1);
    }   
    memset(&nls, 0, sizeof(struct sockaddr_nl));
    nls.nl_pid = DEFAULT_USR_NL_PID;
    nls.nl_groups = 0;
    nls.nl_family = AF_NETLINK;

    if (bind(fd, (void *)&nls, sizeof(struct sockaddr_nl))) {
        printf("Bind failed %s\n", strerror(errno));
        exit(1);
	}
    return fd;
}

