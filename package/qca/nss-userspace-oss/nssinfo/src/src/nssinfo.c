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
 * @file NSSINFO handler
 */
#include <signal.h>
#include "nssinfo.h"

static pthread_t nssinfo_display_thread;	/* Display statistics thread */
static char buf[NSSINFO_STR_LEN];		/* Formatted stats buffer */
bool display_all_stats;				/* Display all stats per sub-system */
int invalid_input;				/* Identify invalid input */
FILE *output_file;				/* Output file pointer */
FILE *flow_file;				/* Flow file pointer */

/* Array of pointers to node stats */
struct node *nodes[NSS_MAX_CORES][NSS_MAX_NET_INTERFACES];

/*
 * NSS subsystems in alphabetical order for nssinfo tool
 * - Make sure the order here is the same as in 'enum nss_nlcmn_subsys'
 *   defined in qca-nss-clients/netlink/include/nss_nlcmn_if.h.
 */
struct nssinfo_subsystem_info nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_MAX] = {
	{.subsystem_name = "dynamic_interface",	.init = nssinfo_dynamic_interface_init,	.deinit = nssinfo_dynamic_interface_deinit},
	{.subsystem_name = "eth_rx",		.init = nssinfo_eth_rx_init,	.deinit = nssinfo_eth_rx_deinit},
	{.subsystem_name = "ipv4",		.init = nssinfo_ipv4_init,	.deinit = nssinfo_ipv4_deinit},
	{.subsystem_name = "ipv6",		.init = nssinfo_ipv6_init,	.deinit = nssinfo_ipv6_deinit},
	{.subsystem_name = "lso_rx",		.init = nssinfo_lso_rx_init,	.deinit = nssinfo_lso_rx_deinit},
	{.subsystem_name = "n2h",		.init = nssinfo_n2h_init,	.deinit = nssinfo_n2h_deinit},
};

char *nssinfo_summary_fmt = "%-12s %-13s %-13s %-9s %-9s\n";

/*
 * nssinfo_print_summary_header()
 *	Print the summary header.
 */
void nssinfo_print_summary_header(void)
{
	nssinfo_stats_print(nssinfo_summary_fmt, "Node", "RX Pkts", "TX Pkts", "Drops", "Exceptions");
	nssinfo_stats_print(nssinfo_summary_fmt, "----", "-------", "-------", "-----", "----------");
}

/*
 * nssinfo_print_summary()
 *	Print the summary of the stats:
 *	- rx pkts
 *	- tx pkts
 *	- rx queue drops
 *	- exceptions
 */
void nssinfo_print_summary(char *node, uint64_t *cmn_node_stats, uint64_t *exception_stats, uint64_t exception_max)
{
	int i;
	uint64_t drops = 0, exceptions = 0;
	char str_rx[NSSINFO_STR_LEN], str_tx[NSSINFO_STR_LEN], str_drop[NSSINFO_STR_LEN], str_ex[NSSINFO_STR_LEN];

	assert(cmn_node_stats);

	memset(str_rx, 0, sizeof(str_rx));
	memset(str_tx, 0, sizeof(str_tx));
	memset(str_drop, 0, sizeof(str_drop));
	memset(str_ex, 0, sizeof(str_ex));

	for (i = NSS_STATS_NODE_RX_QUEUE_0_DROPPED; i < NSS_STATS_NODE_MAX; i++) {
		drops += cmn_node_stats[i];
	}

	if (exception_stats) {
		for (i = 0 ; i < exception_max; i++) {
			exceptions += exception_stats[i];
		}
	}

	if (cmn_node_stats[NSS_STATS_NODE_RX_PKTS] > 0 || cmn_node_stats[NSS_STATS_NODE_TX_PKTS] > 0 ||
			drops > 0 || exceptions > 0 || arguments.verbose) {
		char *format_stats = nssinfo_format_stats(cmn_node_stats[NSS_STATS_NODE_RX_PKTS]);
		strlcpy(str_rx, format_stats, sizeof(str_rx));
		format_stats = nssinfo_format_stats(cmn_node_stats[NSS_STATS_NODE_TX_PKTS]);
		strlcpy(str_tx, format_stats, sizeof(str_tx));
		format_stats = nssinfo_format_stats(drops);
		strlcpy(str_drop, format_stats, sizeof(str_drop));
		if (exception_stats) {
			format_stats = nssinfo_format_stats(exceptions);
			strlcpy(str_ex, format_stats, sizeof(str_ex));
		}
		nssinfo_stats_print(nssinfo_summary_fmt, node, str_rx, str_tx, str_drop, str_ex);
	}
}

/*
 * nssinfo_print_all()
 *	Print detailed statistics.
 */
void nssinfo_print_all(char *node, char *stat_details, struct nssinfo_stats_info *stats_info, uint64_t max, uint64_t *stats_val)
{
	int i;
	uint16_t maxlen = 0;
	char *type;

	for (i = 0; i < max; i++){
		if (strlen(stats_info[i].stats_name) > maxlen) {
			maxlen = strlen(stats_info[i].stats_name);
		}
	}

	/*
	 * Display stats header, e.g. "#ipv4 Common Stats\n"
	 */
	if (stat_details != NULL) {
		nssinfo_stats_print("#%s\n", stat_details);
	}

	/* Display each stat, e.g.
	 * ipv4_rx_byts           = 32903179        common
	 * ipv4_mc_create_invalid_interface = 12    special
	 * ...
	 */
	for (i = 0; i < max; i++) {
		if (arguments.verbose || stats_val[i] > 0) {

			switch (stats_info[i].stats_type) {
		        case NSS_STATS_TYPE_COMMON:
		        	type = "common";
		        	break;

		        case NSS_STATS_TYPE_SPECIAL:
		        	type = "special";
		        	break;

		        case NSS_STATS_TYPE_DROP:
		        	type = "drop";
		        	break;

		        case NSS_STATS_TYPE_ERROR:
		        	type = "error";
		        	break;

		        case NSS_STATS_TYPE_EXCEPTION:
		        	type = "exception";
		        	break;

		        default:
		        	type = "unknown";
		        	break;
			}

			nssinfo_stats_print("%s_%-*s = %-20llu %-s\n",
					node, maxlen, stats_info[i].stats_name, stats_val[i], type);
		}
	}
	nssinfo_stats_print("\n");

	return;
}

/*
 * nssinfo_parse_stats_strings()
 *	Parse each line in the debug strings file.
 *
 * Each line has the following format:
 *	\t<stats_type> , <stats_name>\n
 * for example:
 * root@OpenWrt:/sys/kernel/debug/qca-nss-drv/strings# cat n2h
 *	   0 , rx_pkts
 *	   ...
 *	   1 , rx_queue[0]_drops
 *	   ...
 *	   4 , n2h_data_interface_invalid
 */
static void nssinfo_parse_stats_strings(struct nssinfo_stats_info *info, char *line)
{
	char *token;
	char *rest = NULL;

	token = strtok_r(line, " ", &rest);
	if (token) {
		info->stats_type = atoi(token);
		token = strtok_r(NULL, ",", &rest);
	}
	if (token) {
		token = strtok_r(token, " ", &rest);
	}
	if (token) {
		token = strtok_r(token, "\n", &rest);
	}
	if (token) {
		strlcpy(info->stats_name, token, sizeof(info->stats_name));
	}
}

/*
 * nssinfo_stats_info_init()
 * 	Init 'struct nssinfo_stats_info' from a file in /sys/kernel/debug/qca-nss-drv/strings/.
 */
int nssinfo_stats_info_init(struct nssinfo_stats_info *info, char *strings_file)
{
	FILE *fptr;
	char line[NSS_STATS_MAX_STR_LENGTH];

	fptr = fopen(strings_file, "r");
	if (!fptr) {
		nssinfo_error("Unable to open\n");
		return -1;
	}

	while (fgets(line, NSS_STATS_MAX_STR_LENGTH, fptr)) {
		nssinfo_parse_stats_strings(info, line);
		info++;
	}
	fclose(fptr);

	return 0;
}

/*
 * nssinfo_node_stats_destroy()
 * 	Release memories used to store the node stats.
 */
void nssinfo_node_stats_destroy(pthread_mutex_t *mutex, uint32_t core_id, uint32_t if_num)
{
	struct node *p, *next;

	if (mutex) {
		pthread_mutex_lock(mutex);
	}

	p = nodes[core_id][if_num];
	nodes[core_id][if_num] = NULL;

	if (mutex) {
		pthread_mutex_unlock(mutex);
	}

	while (p) {
		next = p->next;

		if (p->cmn_node_stats) {
			free(p->cmn_node_stats);
		}

		if (p->node_stats) {
			free(p->node_stats);
		}

		if (p->exception_stats) {
			free(p->exception_stats);
		}

		free(p);

		p = next;
	}

	return;
}

/*
 * nssinfo_add_comma()
 *	Add commas in thousand's place in statistics.
 */
static char* nssinfo_add_comma(uint64_t num)
{
	if (num < 1000) {
		snprintf(buf, sizeof(buf), "%llu", num);
		return buf;
	}

	nssinfo_add_comma(num/1000);
	snprintf(buf + strlen(buf), sizeof(buf[NSSINFO_STR_LEN] + strlen(buf)), ",%03llu", num % 1000);
	return buf;
}

/*
 * nssinfo_add_suffix()
 *	Convert number into K thousands M million and B billion suffix.
 */
static char* nssinfo_add_suffix(uint64_t num)
{
	if (num < 1000) {
		snprintf(buf, sizeof(buf), "%llu", num);
		return buf;
	}

	if (1000 <= num && num < 1000000) {
		snprintf(buf , sizeof(buf), "%.2lfK", num / 1000.0);
		return buf;
	}

	if (1000000 <= num && num < 1000000000) {
		snprintf(buf , sizeof(buf), "%.2lfM", num / 1000000.0);
		return buf;
	}

	if (1000000000 <= num) {
		snprintf(buf , sizeof(buf), "%.2lfB", num / 1000000000.0);
		return buf;
	}

	return buf;
}

/*
 * nssinfo_format_stats()
 *	Format statistics value.
 */
char* nssinfo_format_stats(uint64_t num)
{
	memset(buf, 0, sizeof(buf));
	if (!arguments.higher_unit) {
		return nssinfo_add_comma(num);
	}

	return nssinfo_add_suffix(num);
}

/*
 * nssinfo_stats_display()
 *	Invoke each sub-system's display function.
 */
static void *nssinfo_stats_display(void *arg)
{
	int i, j, core;
	char mesg[]="NSS STATS";

	pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, NULL);

	for (;;) {
		nssinfo_stats_print("\t\t\t%s\n", mesg);

		/*
		 * If user does not specify a core id,
		 * check if the flow file is specified and display stats accordingly.
		 */
		if (arguments.core < 0) {
			/*
			 * If flow file is not specified (via '-f' option),
			 * display each node's summary stats in alphabetical order for all the cores.
			 */
			if (!flow_file) {
				for (core = 0 ; core < NSS_MAX_CORES ; core++) {
					nssinfo_stats_print("Stats for core %d\n",core);
					nssinfo_print_summary_header();
					for (i = 0 ; i < NSS_NLCMN_SUBSYS_MAX; i++) {
						if (nssinfo_subsystem_array[i].is_inited && i != NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE) {
							nssinfo_subsystem_array[i].display(core, NULL);
						}
					}
					nssinfo_stats_print("\n");
				}

				goto done;
			}

			/*
			 * Flow file is specified (via '-f' option),
			 * Parse the network graph from flow file and display the node's summary stats
			 * For example, the network graph would look like
			 * ipv4-0 eth_rx-0 n2h-1
			 * Where, node = ipv4 , core = 0
			 * node = eth_rx , core = 0
			 * node = n2h , core = 1
			 */
			char *line = NULL;
			char *rest = NULL;
			size_t len = 0;
			ssize_t read;
			char *node = NULL;
			int matched = 0;

			nssinfo_print_summary_header();
			fseek(flow_file, 0, SEEK_SET);
			while ((read = getline(&line, &len, flow_file)) != -1) {
				node = strtok_r(line, "-", &rest);

				while (node != NULL) {
					core = atoi(strtok_r(NULL, " ", &rest));
					if (core >= NSS_MAX_CORES || core < 0) {
						printf("Invalid core id `%d'\n", core);
						exit(-1);
					}

					for (j = 0; j < NSS_NLCMN_SUBSYS_MAX; j++) {
						if (nssinfo_subsystem_array[j].is_inited &&
							strstr(node, nssinfo_subsystem_array[j].subsystem_name)) {
							if (j != NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE) {
								++matched;
								nssinfo_subsystem_array[j].display(core, node);
							}
						}
					}

					node = strtok_r(NULL, "-", &rest);
				}

				/* If all NODE names are invalid */
				if (matched == invalid_input) {
					nssinfo_error("Invalid input\n");
					return NULL;
				}
			}

			if (line) {
				free(line);
			}

			goto done;
		}

		if (!arguments.strings[0]) {
			/*
			 * If a core id is specified (via '-c' option) but NODE is not specified,
			 * display each node's summary stats in alphabetical order for that core.
			 */
			nssinfo_stats_print("Stats for core %d\n", arguments.core);
			nssinfo_print_summary_header();
			for (i = 0 ; i < NSS_NLCMN_SUBSYS_MAX; i++) {
				if (nssinfo_subsystem_array[i].is_inited && i != NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE) {
					nssinfo_subsystem_array[i].display(arguments.core, NULL);
				}
			}

			goto done;
		}

		/*
		 * If a core id is specified and at least one NODE is specified.
		 */
		nssinfo_stats_print("Stats for core %d\n", arguments.core);

		/*
		 * If user specifies only one NODE, then display all stats for this NODE.
		 * For example, if NODE="ipv4", then display:
		 * - common stats (i.e. enum nss_stats_node)
		 * - ipv4 special stats (i.e. enum nss_ipv4_stats_types)
		 * - ipv4 exception stats (i.e. enum nss_ipv4_exception_events)
		 */
		if (!arguments.strings[1]) {
			display_all_stats = true;
		} else {
			/*
			 * If user specifies more than one NODEs, then display the summary stats for each node
			 */
			nssinfo_print_summary_header();
		}

		/*
		 * Now, display NODEs in the desired order.
		 */
		int matched = 0;
		for (i = 0; arguments.strings[i]; i++) {
			for (j = 0; j < NSS_NLCMN_SUBSYS_MAX; j++) {
				if (nssinfo_subsystem_array[j].is_inited &&
				    strstr(arguments.strings[i], nssinfo_subsystem_array[j].subsystem_name)) {
					if (j != NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE) {
						++matched;
						nssinfo_subsystem_array[j].display(arguments.core, arguments.strings[i]);
					}
				}

			}
		}

		/*
		 * If all NODE names are invalid.
		 */
		if (matched == invalid_input) {
			nssinfo_error("Invalid input\n");
			return NULL;
		}
done:
		/*
		 * If using ncurses, refresh the screen.
		 */
		if (!output_file) {
			refresh();	/* draw on screen */
			clear();	/* clear screen buffer */
			move(0, 0);	/* move cursor to (line, column)=(0,0) */
		}

		invalid_input = 0;
		sleep(arguments.rate);
	}
}

/*
 * nssinfo_curses_init()
 *	Initialize curses library.
 */
static int nssinfo_curses_init()
{
	int rows, cols;

	if (!initscr()) {		/* satrt curses mode */
		nssinfo_error("Unable to initialize curses screen\n");
		return -EOPNOTSUPP;
	}

	getmaxyx(stdscr, rows, cols);	/* get the size of the screen */
	if (rows < CURSES_ROWS_MIN) {
		nssinfo_error("Screen must be at least %d rows in height", CURSES_ROWS_MIN);
		goto out;
	}
	if (cols < CURSES_COLS_MIN) {
		nssinfo_error("Screen must be at least %d columns width", CURSES_COLS_MIN);
		goto out;
	}

	cbreak();			/* disable line buffering */
	noecho();			/* not to echo the input back to the screen */
	nonl();				/* disable 'enter' key translation */
	keypad(stdscr, TRUE);		/* enable keypad keys, such as arrow keys, etc. */
	nodelay(stdscr, TRUE);		/* cause getch() to be a non-blocking call */
	curs_set(0);			/* make the cursor invisible */
	clear();			/* clear screen buffer */
	move(0, 0);			/* move cursor to (line, column)=(0,0) */
	return 0;

out:
	endwin();			/* stop curses mode */
	return -1;
}

/*
 * nssinfo_termination_handler()
 *	Terminates all the modules.
 */
static void nssinfo_termination_handler(int signum)
{
	pthread_cancel(nssinfo_display_thread);
}

/*
 * nssinfo_display_init()
 * 	Handle displaying all the stats.
 */
static int nssinfo_display_init()
{
	int error;

	if (!output_file) {
		if (nssinfo_curses_init() != 0) {
			return -1;
		}
	}

	error = pthread_create(&nssinfo_display_thread, NULL, nssinfo_stats_display, NULL);
	if (error) {
		nssinfo_error("failed to create display thread, error %d\n", error);
		if (!output_file) {
			endwin();
		}
	}

	return error;
}

/*
 * nssinfo_display_wait()
 *	Wait for the display thread.
 */
static int nssinfo_display_wait()
{
	/*
	 * waiting for the display thread to be terminated.
	 */
	pthread_join(nssinfo_display_thread, NULL);

	if (!output_file) {
		refresh();
		endwin();
	}

	return 0;
}

/*
 * nssinfo_notify_callback
 *	Get notified when NL message is received.
 */
static void nssinfo_notify_callback(int cmd, void *data)
{
	if (cmd < NSS_NLCMN_SUBSYS_MAX && nssinfo_subsystem_array[cmd].is_inited) {
		nssinfo_subsystem_array[cmd].notify(data);
	} else {
		nssinfo_error("Unknown message type %d\n", cmd);
	}
}

/*
 */
static void nssinfo_deinit(struct nss_nlmcast_ctx *ctx)
{
	int i, core;
	struct node *node;
	nssinfo_deinit_t deinit;

	/*
	 * Close NL socket and terminate ctx->sock.thread
	 */
	nss_nlmcast_sock_close(ctx);

	/*
	 * Release memory used for storing stats
	 */
	for (core = 0; core < NSS_MAX_CORES; ++core) {
		for (i = 0; i < NSS_MAX_NET_INTERFACES; ++i) {
			node = nodes[core][i];
			if (node) {
				assert(node->subsystem_id != NSS_NLCMN_SUBSYS_DYNAMIC_INTERFACE);
				nssinfo_subsystem_array[node->subsystem_id].destroy(core, i);
			}
		}
	}

	/*
	 * Release resources used by each subsystem
	 */
	for (i = 0; i < NSS_NLCMN_SUBSYS_MAX; i++) {
		deinit = nssinfo_subsystem_array[i].deinit;
		if (deinit) {
			deinit(ctx);
		}
	}
}

/*
 * nssinfo_init()
 *	Initialize all the modules.
 */
int nssinfo_init(void)
{
	int error, i;
	struct nss_nlmcast_ctx ctx;
	nssinfo_init_t init;

	memset(&ctx, 0, sizeof(ctx));

	/*
	 * Create NL socket
	 */
	error = nss_nlmcast_sock_open(&ctx, nssinfo_notify_callback, NULL);
	if (error) {
		nssinfo_error("Socket creation failed for NSSINFO, error(%d)\n", error);
		return error;
	}

	/*
	 * Initialize all the subsystems and subscribe for mcast groups.
	 */
	for (i = 0; i < NSS_NLCMN_SUBSYS_MAX; i++) {
		init = nssinfo_subsystem_array[i].init;
		if (init) {
			error = init(&ctx);
			if (error) {
				nssinfo_error("%s init failed, error(%d)\n", nssinfo_subsystem_array[i].subsystem_name, error);
			}
		}
	}

	/*
	 * Listen for MCAST events from kernel.
	 */
	error = nss_nlmcast_sock_listen(&ctx);
	if (error < 0) {
		nssinfo_error("failed to listen for mcast events from kernel\n");
		goto end;
	}

	/*
	 * Create a thread which displays the stats continuously.
	 */
	error = nssinfo_display_init();
	if (error) {
		goto end;
	}

	/*
	 * Install CTRL-C handler
	 */
	struct sigaction new_action;
	new_action.sa_handler = nssinfo_termination_handler;
	sigemptyset(&new_action.sa_mask);
	new_action.sa_flags = 0;
	error = sigaction(SIGINT, &new_action, NULL);
	if (error) {
		nssinfo_error("failed to install CTRL-C handler\n");
		goto end;
	}

	/*
	 * main thread is waiting here
	 */
	nssinfo_display_wait();

end:
	nssinfo_deinit(&ctx);
	return error;
}
