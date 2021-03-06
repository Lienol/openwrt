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
#include <libubox/uloop.h>
#include <libubox/utils.h>
#include <libubus.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/socket.h>
#include <sys/socket.h>
#include "appfilter_user.h"

dev_node_t *dev_hash_table[MAX_DEV_NODE_HASH_SIZE];

unsigned int hash_mac(unsigned char *mac)
{
	if (!mac)
		return 0;
	else
		return mac[0] & (MAX_DEV_NODE_HASH_SIZE - 1);
}

int hash_appid(int appid){
	return appid % (MAX_VISIT_HASH_SIZE - 1);
}

void add_visit_info_node(visit_info_t **head, visit_info_t *node){
	if (*head == NULL){
		*head = node;
	}
	else{
		node->next = *head;
		*head = node;
	}
}

void init_dev_node_htable(){
    int i;
    for (i = 0; i < MAX_DEV_NODE_HASH_SIZE; i++){
        dev_hash_table[i] = NULL;
    }
}

dev_node_t *add_dev_node(char *mac){
    unsigned int hash = 0;
    hash = hash_mac(mac);
    if (hash >= MAX_DEV_NODE_HASH_SIZE){
        printf("hash code error %d\n", hash);
        return NULL;
    }
    dev_node_t *node = (dev_node_t *)calloc(1, sizeof(dev_node_t));
    if (!node)
        return NULL;
    strncpy(node->mac, mac, sizeof(node->mac));

    if (dev_hash_table[hash] == NULL)
        dev_hash_table[hash] = node;
    else{
        node->next = dev_hash_table[hash];
        dev_hash_table[hash] = node;
    }
    printf("add mac:%s to htable[%d]....success\n", mac, hash);
    return node;
}

dev_node_t *find_dev_node(char *mac){
    unsigned int hash = 0;
    dev_node_t *p = NULL;
    hash = hash_mac(mac);
    if (hash >= MAX_DEV_NODE_HASH_SIZE){
        printf("hash code error %d\n", hash);
        return NULL;
    }
    p = dev_hash_table[hash];
    while(p){
        if (0 == strncmp(p->mac, mac, sizeof(p->mac))){
            return p;
        }
        p = p->next;
    }
    return NULL;
}

void dev_foreach(void *arg, iter_func iter){
	int i, j;
	dev_node_t *node = NULL;

    for (i = 0;i < MAX_DEV_NODE_HASH_SIZE; i++){
        dev_node_t *node = dev_hash_table[i];
		while(node){
            iter(arg, node);
			node = node->next;
		}
    }
}


char * format_time(int timetamp){
	char time_buf[64] = {0};
	time_t seconds = timetamp;
	struct tm *auth_tm = localtime(&seconds); 
	strftime(time_buf, sizeof(time_buf), "%Y %m %d %H:%M:%S", auth_tm);
	return strdup(time_buf);
}

void dump_dev_list(void){
    int i, j;
	int count = 0;
	FILE *fp = fopen(OAF_DEV_LIST_FILE, "w");
	if (!fp){
		return;
	}
		
	fprintf(fp, "%-4s %-20s %-20s %-32s\n", "Id", "Mac Addr", "Ip Addr", "Hostname");
    for (i = 0;i < MAX_DEV_NODE_HASH_SIZE; i++){
        dev_node_t *node = dev_hash_table[i];
		while(node){
			fprintf(fp, "%-4d %-20s %-20s %-32s\n", i + 1, node->mac, node->ip, node->hostname);
			node = node->next;
		}
    }
EXIT:
	fclose(fp);
}

void dump_dev_visit_list(void){
    int i, j;
	int count = 0;
	FILE *fp = fopen(OAF_VISIT_LIST_FILE, "w");
	if (!fp){
		return;
	}
		
	fprintf(fp, "%-4s %-20s %-20s %-8s %-32s %-32s %-32s\n", "Id", "Mac Addr", \
		"Ip Addr", "Appid", "First Time", "Latest Time", "Total Time(s)");
    for (i = 0;i < MAX_DEV_NODE_HASH_SIZE; i++){
        dev_node_t *node = dev_hash_table[i];
        while(node){
			for (j = 0; j < MAX_VISIT_HASH_SIZE; j++){
				visit_info_t *p_info = node->visit_htable[j];
				while(p_info){
					char *first_time_str = format_time(p_info->first_time);
					char *latest_time_str = format_time(p_info->latest_time);
					int total_time = p_info->latest_time - p_info->first_time;
					fprintf(fp, "%-4d %-20s %-20s %-8d %-32s %-32s %-32d\n", 
						count, node->mac, node->ip, p_info->appid, first_time_str,
						latest_time_str, total_time);
					if (first_time_str)
						free(first_time_str);
					if (latest_time_str)
						free(latest_time_str);
					p_info = p_info->next;
					count++;
					if (count > 50)
						goto EXIT;
				}
			}
			node = node->next;
        }
    }
EXIT:
	fclose(fp);
}

