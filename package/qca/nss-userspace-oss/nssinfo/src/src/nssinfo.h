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

#ifndef __NSSINFO_FAMILY_H
#define __NSSINFO_FAMILY_H

#include "nss_nlbase.h"
#include "ncurses.h"
#include "nssinfo_ipv4.h"
#include "nssinfo_ipv6.h"
#include "nssinfo_ethrx.h"
#include "nssinfo_n2h.h"
#include "nssinfo_dynamic_interface.h"
#include "nssinfo_lso_rx.h"
#include "nss_api_if.h"
#include "nss_dynamic_interface.h"
#include "nss_stats_public.h"

#define NSSINFO_COLOR_RST "\x1b[0m"
#define NSSINFO_COLOR_GRN "\x1b[32m"
#define NSSINFO_COLOR_RED "\x1b[31m"
#define NSSINFO_COLOR_MGT "\x1b[35m"

#ifdef  ENABLE_DEBUG
#define nssinfo_info(fmt, arg...) printf(NSSINFO_COLOR_GRN"INF "NSSINFO_COLOR_RST fmt, ## arg)
#define nssinfo_trace(fmt, arg...) printf(NSSINFO_COLOR_MGT"TRC(%s:%d) "NSSINFO_COLOR_RST fmt, __func__, __LINE__, ## arg)
#define nssinfo_options(fmt, arg...) printf(NSSINFO_COLOR_MGT"OPT_%d "NSSINFO_COLOR_RST fmt, ## arg)
#define nssinfo_warn(fmt, arg...) printf(NSSINFO_COLOR_RED"WARN(%s:%d) "NSSINFO_COLOR_RST fmt, __func__, __LINE__, ##arg)
#else
#define nssinfo_info(fmt, arg...)
#define nssinfo_trace(fmt, arg...)
#define nssinfo_options(fmt, arg...)
#define nssinfo_warn(fmt, arg...)
#endif
#define nssinfo_error(fmt, arg...) printf(NSSINFO_COLOR_RED"ERR(%s:%d) "NSSINFO_COLOR_RST fmt, __func__, __LINE__, ## arg)

#define nssinfo_stats_print(fmt, arg...) ({				\
			if (output_file) {				\
				fprintf(output_file, fmt, ## arg);	\
			} else {					\
				wprintw(stdscr, fmt, ## arg);	\
			}						\
		})
/*
 * Minimum terminal size to use curses library
 */
#define CURSES_ROWS_MIN 4
#define CURSES_COLS_MIN 48

/*
 * Maximum formatted statistics length
 */
#define NSSINFO_STR_LEN 30

extern bool display_all_stats;
extern FILE *output_file;
extern FILE *flow_file;
extern int invalid_input;
extern struct arguments arguments;
extern char *nssinfo_summary_fmt;

/**
 * @brief display method_t function
 *
 * @param core[IN] NSS core id
 */
typedef void (*nssinfo_stats_display_t)(int core, char *input);

/**
 * @brief stats notify method_t function
 *
 * @param data[IN] data received from Netlink client
 */
typedef void (*nssinfo_stats_notify_t)(void *data);

/**
 * @brief init method_t function
 *
 * @param data[IN] an opague context to be used for initialization
 */
typedef int (*nssinfo_init_t)(void *data);

/**
 * @brief deinit method_t function
 *
 * @param data[IN] an opague context to be used for deinitialization
 */
typedef void (*nssinfo_deinit_t)(void *data);

/**
 * @brief destroy method_t function
 *
 * @param core_id[IN] core id of the node to be destroyed
 * @param if_num[IN] interface id of the node to be destroyed
 */
typedef void (*nssinfo_destroy_t)(uint32_t core_id, uint32_t if_num);

/**
 * @brief Used by main to communicate with parse_opt
 */
struct arguments {
	bool verbose;		/*< '-v' >*/
	char *output_file;	/*< file arg to '--output' >*/
	char *flow_file;	/*< file arg to '--flowfile' >*/
	bool higher_unit;	/*< display higher units '-h' >*/
	int core;		/*< core id  >*/
	char **strings;		/*< non-option arguments: [NODE1 [NODE2 ...]] >*/
	int rate;		/*< display rate in second >*/
};

/**
 * @brief NSSINFO subsystem information
 */
struct nssinfo_subsystem_info {
	char *subsystem_name;			/**< Subsystem name string  */
	nssinfo_init_t init;			/**< Initialize method_t */
	nssinfo_deinit_t deinit;		/**< Deinitialize method_t */
	nssinfo_stats_display_t display;	/**< Display method_t */
	nssinfo_stats_notify_t notify;		/**< Stats notify method_t */
	nssinfo_destroy_t destroy;		/**< Stats notify method_t */
	bool is_inited;				/**< True if the subsystem is initialized */
};

extern struct nssinfo_subsystem_info nssinfo_subsystem_array[NSS_NLCMN_SUBSYS_MAX];

/**
 * @brief NSSINFO pnode stats
 */
struct node {
	struct node *next;		/**< Pointer to next node */
	uint64_t id;			/**< Dynamic interface number */
	int type;			/**< see 'enum nss_dynamic_interface_type' */
	int subsystem_id;		/**< see 'enum nss_nlcmn_subsys' */
	void *cmn_node_stats;		/**< Common node stats */
	void *node_stats;		/**< Special stats */
	void *exception_stats;		/**< Exception stats */
};

extern struct node *nodes[NSS_MAX_CORES][NSS_MAX_NET_INTERFACES];

/**
 * @brief Structure definition carrying stats info.
 */
struct nssinfo_stats_info {
	char stats_name[NSS_STATS_MAX_STR_LENGTH];	/* stat name */
	int stats_type;					/* enum that tags stat type  */
};

/**
 * @brief validates core id and interface number
 *
 * @param core_id[IN] validates the core d
 * @param if_num[IN] validates the interface number
 *
 * @return true on success or false for failure
 */
static inline bool nssinfo_coreid_ifnum_valid(uint32_t core_id, uint32_t if_num)
{
	return (core_id < NSS_MAX_CORES && if_num < NSS_MAX_NET_INTERFACES);
}

/**
 * @brief initialize all the modules
 *
 * @param flow_file[IN] parse it and display output accordingly
 *
 * @return 0 on success or -ve for failure
 */
int nssinfo_init(void);

/**
 * @brief Format statistics value
 *
 * @param num[IN] statistics value in uint64_t
 *
 * @return comma separated string
 */
char* nssinfo_format_stats(uint64_t num);

/**
 * @brief Init nssinfo_stats_info from kernel debug file.
 *
 * @param info[IN] pointer to a nssinfo_stats_info array
 * @param line[IN] string file in kernel/debug/qca-nss-drv/strings/
 */
int nssinfo_stats_info_init(struct nssinfo_stats_info *info, char *strings_file);

/**
 * @brief Free all resources used for node stats.
 *
 * @param mutex[IN] mutex lock
 * @param core_id[IN] core id
 * @param if_num[IN] node's interface number
 */
void nssinfo_node_stats_destroy(pthread_mutex_t *mutex, uint32_t core_id, uint32_t if_num);

/**
 * @brief Print detailed statistics.
 *
 * @param node[IN] node for which stats to be printed
 * @param stat_details[IN] statistics details to be printed
 * @param stats_info[IN] statistics information
 * @param max[IN] maximum number of strings
 * @param stats_val[IN] statistics values
 */
void nssinfo_print_all(char *node, char *stat_details, struct nssinfo_stats_info *stats_info, uint64_t max, uint64_t *stats_val);

/**
 * @brief Print the summary of the statistics.
 *
 * @param node[IN] node for which stats to be printed
 * @param cmn_node_stats[IN] common node stats
 * @param exception_stats[IN] exception stats
 * @param exception_max[IN] maximum exception type
 */
void nssinfo_print_summary(char *node, uint64_t *cmn_node_stats, uint64_t *exception_stats, uint64_t exception_max);

void nssinfo_print_summary_header(void);

#endif /* __NSSINFO_FAMILY_H*/
