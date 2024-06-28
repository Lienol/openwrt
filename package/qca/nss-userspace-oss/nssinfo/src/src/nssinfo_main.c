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

#include "nssinfo.h"
#include <getopt.h>

static const char *nssinfo_version = "1.0";

static struct option long_options[] = {
	{"verbose",	no_argument,		NULL,	'v'},
	{"higherunit",	no_argument,		NULL,	'u'},
	{"help",	no_argument,		NULL,	'h'},
	{"version",	no_argument,		NULL,	'V'},
	{"output",	required_argument,	NULL,	'o'},
	{"flowfile",	required_argument,	NULL,	'f'},
	{"core",	required_argument,	NULL,	'c'},
	{"rate",	required_argument,	NULL,	'r'},
	{0, 0, 0, 0}
};
static char *short_options = "vuh?Vo:f:c:r:";

static void print_help(void)
{
	printf("nssinfo is an userspace tool used to display NODE stats from NSS-FW\n");
	printf("Usage: nssinfo [OPTION ...] [-c ID [NODE1 NODE2 ...]]\n");
	printf("OPTION:\n");
	printf("  -c, --core=ID              Display statistics based on core id\n");
	printf("  -f, --flowfile=FILE        Specify output content in FILE\n");
	printf("  -o, --output=FILE          Write output to FILE instead of stdout\n");
	printf("  -r, --rate=RATE            Update screen every RATE seconds\n");
	printf("  -u, --higherunit           Display stats in higher units, i.e. K, M, B\n");
	printf("  -v, --verbose              Display all the stats (zero and non-zero stats)\n");
	printf("  -V, --version              Print program version\n");
	printf("  -h, --help                 Give this help message\n");
	printf("Examples:\n");
	printf("  nssinfo\n");
	printf("  nssinfo -c0\n");
	printf("  nssinfo -c0 ipv4 edma[0] edma[4]\n");
	printf("  nssinfo -r5 -o stats.log\n");
}

struct arguments arguments;

/*
 * getopt_parse()
 *	Parse command line arguments using getopt_long().
 */
static int getopt_parse(int argc, char **argv, void *a)
{
	struct arguments *arguments = (struct arguments *)a;

	while (1) {
		int key = getopt_long(argc, argv, short_options, long_options, NULL);

		/*
		 * Detect the end of the options.
		 */
		if (key == -1)
			break;

		switch (key) {
		case 'v':
			arguments->verbose = true;
			break;

		case 'u':
			arguments->higher_unit = true;
			break;

		case 'f':
			arguments->flow_file = optarg;
			break;

		case 'o':
			arguments->output_file = optarg;
			break;

		case 'r':	/* -r5	*/
			arguments->rate = atoi(optarg);
			if (arguments->rate <= 0) {
				printf("Invalid rate `%s'\n", optarg);
				exit(-1);
			}
			break;

		case 'c':	/* -c0 */
			arguments->core = atoi(optarg);
			if (arguments->core >= NSS_MAX_CORES || arguments->core < 0) {
				printf("Invalid core id `%s'\n", optarg);
				exit(-1);
			}
			break;

		case 'h':
			print_help();
			exit(0);

		case 'V':
			printf("%s\n", nssinfo_version);
			exit(0);

		case '?':
		default:
			/*
			 * getopt_long already printed an error message.
			 */
			exit(-1);
		}
	}

	/* Any remaining non-option arguments start from argv[optind].
	 * Init arguments->strings so that
	 * arguments->strings[0] points to the 1st non-option argument
	 * arguments->strings[1] points to the 2nd non-option argument
	 * ...
	 * arguments->strings[n] points to the last non-option argument
	 * arguments->strings[n+1] is NULL
	 *
	 * For example,
	 * If user enters 'nssinfo -c1 edma1 edma2', optind is 2 at this point and
	 * arguments->strings[0] = "edma1", arguments->strings[1] = "edma2", arguments->strings[2] = NULL.
	 * If user does not specify any non-option argument (e.g. nssinfo -v),
	 * argv[optind] is NULL so arguments->strings[0] is NULL.
	 */
	arguments->strings = &argv[optind];

	return 0;
}

/*
 * main()
 */
int main(int argc, char **argv)
{
	int error;

	arguments.output_file = NULL;
	arguments.flow_file = NULL;
	arguments.verbose = false;
	arguments.higher_unit = false;
	arguments.core = -1;	/* display stats for all cores */
	arguments.rate = 1;	/* 1 sec */

	getopt_parse(argc, argv, &arguments);

	if (arguments.output_file) {
		output_file = fopen(arguments.output_file, "w");
		if (!output_file) {
			nssinfo_error("Error opening output file!\n");
			exit(1);
		}
	}

	if (arguments.flow_file) {
		flow_file = fopen(arguments.flow_file, "r");
		if (!flow_file) {
			nssinfo_error("Error opening flow file!\n");
			error = -1;
			goto end;
		}
	}

	error = nssinfo_init();
	if (error) {
		nssinfo_info("Nssinfo initialization failed(%d)\n", error);
	}

	if (flow_file) {
		fclose(flow_file);
	}

end:
	if (output_file) {
		fclose(output_file);
	}

	return error;
}
