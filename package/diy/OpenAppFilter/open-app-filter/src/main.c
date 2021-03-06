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
#include "appfilter_user.h"
#include "appfilter_netlink.h"
#include "appfilter_ubus.h"
#include "appfilter_config.h"

void dev_list_timeout_handler(struct uloop_timeout *t){
    dump_dev_list();
	dump_dev_visit_list();
	uloop_timeout_set(t, 5000);
}

struct uloop_timeout dev_tm={
	.cb = dev_list_timeout_handler
};

static struct uloop_fd appfilter_nl_fd = {
	.cb = appfilter_nl_handler,
};

int main(int argc, char **argv)
{
    int ret = 0;
	uloop_init();
    printf("init appfilter\n");
    init_dev_node_htable();
	init_app_name_table();
	init_app_class_name_table();
	if (appfilter_ubus_init() < 0) {
		fprintf(stderr, "Failed to connect to ubus\n");
		return 1;
	}

    appfilter_nl_fd.fd = appfilter_nl_init();
    uloop_fd_add(&appfilter_nl_fd, ULOOP_READ);
	uloop_timeout_set(&dev_tm, 5000);
    uloop_timeout_add(&dev_tm);
	uloop_run();
	uloop_done();
	return 0;
}

