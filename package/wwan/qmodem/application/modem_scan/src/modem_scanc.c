#include "modem_scan_common.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static void usage(FILE *out)
{
	fprintf(out,
		"Usage:\n"
		"  modem_scanc add <slot> <usb|pcie> [delay_seconds]\n"
		"  modem_scanc remove <section> [delay_seconds]\n"
		"  modem_scanc disable <slot> [delay_seconds]\n"
		"  modem_scanc scan [usb|pcie|all] [delay_seconds]\n"
		"  modem_scanc set-log-level <debug|info|notice|warn|err>\n"
		"  modem_scanc status\n");
}

static int send_request(const char *line)
{
	int fd;
	struct sockaddr_un addr;
	char reply[QMODEM_MAX_REPLY];
	ssize_t n;

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		perror("socket");
		return 1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", QMODEM_SCAND_SOCKET);

	for (int i = 0; i < 20; i++) {
		if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0)
			break;
		if (i == 19) {
			fprintf(stderr, "modem_scand unavailable: %s\n", strerror(errno));
			close(fd);
			return 2;
		}
		usleep(100000);
	}

	if (write(fd, line, strlen(line)) < 0 || write(fd, "\n", 1) < 0) {
		perror("write");
		close(fd);
		return 1;
	}

	while ((n = read(fd, reply, sizeof(reply) - 1)) > 0) {
		reply[n] = '\0';
		fputs(reply, stdout);
	}

	close(fd);
	return 0;
}

int main(int argc, char **argv)
{
	char line[QMODEM_MAX_LINE];

	if (argc < 2) {
		usage(stderr);
		return 1;
	}

	if (!strcmp(argv[1], "add")) {
		if (argc != 4 && argc != 5) {
			usage(stderr);
			return 1;
		}
		snprintf(line, sizeof(line), "add %s %s %s", argv[2], argv[3], argc == 5 ? argv[4] : "0");
	} else if (!strcmp(argv[1], "remove")) {
		if (argc != 3 && argc != 4) {
			usage(stderr);
			return 1;
		}
		snprintf(line, sizeof(line), "remove %s %s", argv[2], argc == 4 ? argv[3] : "0");
	} else if (!strcmp(argv[1], "disable")) {
		if (argc != 3 && argc != 4) {
			usage(stderr);
			return 1;
		}
		snprintf(line, sizeof(line), "disable %s %s", argv[2], argc == 4 ? argv[3] : "0");
	} else if (!strcmp(argv[1], "scan")) {
		const char *type = argc >= 3 ? argv[2] : "all";
		const char *delay = argc >= 4 ? argv[3] : "0";
		snprintf(line, sizeof(line), "scan %s %s", type, delay);
	} else if (!strcmp(argv[1], "set-log-level")) {
		if (argc != 3) {
			usage(stderr);
			return 1;
		}
		snprintf(line, sizeof(line), "set-log-level %s", argv[2]);
	} else if (!strcmp(argv[1], "status")) {
		snprintf(line, sizeof(line), "status");
	} else {
		usage(stderr);
		return 1;
	}

	return send_request(line);
}
