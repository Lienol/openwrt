#include "modem_scan_common.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <json-c/json.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

enum event_type {
	EV_ADD,
	EV_REMOVE,
	EV_DISABLE,
	EV_SCAN,
};

enum log_level {
	LOG_L_DEBUG = 0,
	LOG_L_INFO,
	LOG_L_NOTICE,
	LOG_L_WARN,
	LOG_L_ERR,
};

struct str_list {
	char **items;
	size_t len;
	size_t cap;
};

struct event {
	enum event_type type;
	char slot[128];
	char slot_type[16];
	char section[128];
	char key[256];
	time_t not_before;
	int attempts;
	struct event *next;
};

struct port_rule {
	int has_rule;
	int option_driver;
	struct str_list include;
};

struct modem_profile {
	char name[128];
	char manufacturer[64];
	char platform[64];
	char pdp_index[32];
	char wcdma_band[512];
	char lte_band[512];
	char nsa_band[512];
	char sa_band[512];
	struct str_list modes;
};

struct port_candidate {
	char dev[128];
	int is_pcie;
};

struct scan_result {
	struct str_list net_devices;
	struct str_list at_ports;
	struct str_list pcie_at_ports;
	struct str_list valid_at_ports;
	char preferred_at[128];
	char modem_path[256];
	char vid[16];
	char pid[16];
	int option_driver;
};

struct daemon_state {
	pthread_mutex_t queue_lock;
	pthread_cond_t queue_cond;
	struct event *queue_head;
	struct event *queue_tail;
	struct str_list active_keys;
	int queue_len;
	int active_jobs;
	int stop;
	int scan_workers;
	int at_probe_workers;
	int at_timeout_fast;
	int at_timeout_model;
	int add_retry_delay;
	int add_retry_max;
	enum log_level log_level;
	json_object *support_json;
	json_object *port_rule_json;
};

static struct daemon_state g;
static pthread_mutex_t uci_lock = PTHREAD_MUTEX_INITIALIZER;

static void sl_init(struct str_list *l)
{
	memset(l, 0, sizeof(*l));
}

static void sl_free(struct str_list *l)
{
	for (size_t i = 0; i < l->len; i++)
		free(l->items[i]);
	free(l->items);
	memset(l, 0, sizeof(*l));
}

static int sl_contains(const struct str_list *l, const char *s)
{
	for (size_t i = 0; i < l->len; i++) {
		if (!strcmp(l->items[i], s))
			return 1;
	}
	return 0;
}

static int sl_add(struct str_list *l, const char *s)
{
	char **n;

	if (!s || !*s || sl_contains(l, s))
		return 0;
	if (l->len == l->cap) {
		size_t cap = l->cap ? l->cap * 2 : 8;
		n = realloc(l->items, cap * sizeof(*n));
		if (!n)
			return -1;
		l->items = n;
		l->cap = cap;
	}
	l->items[l->len] = strdup(s);
	if (!l->items[l->len])
		return -1;
	l->len++;
	return 0;
}

static void sl_truncate(struct str_list *l, size_t len)
{
	if (len >= l->len)
		return;
	for (size_t i = len; i < l->len; i++)
		free(l->items[i]);
	l->len = len;
}

static void log_msg(enum log_level lvl, const char *fmt, ...)
{
	int prio = LOG_INFO;
	va_list ap;

	if (lvl < g.log_level)
		return;
	switch (lvl) {
	case LOG_L_DEBUG: prio = LOG_DEBUG; break;
	case LOG_L_INFO: prio = LOG_INFO; break;
	case LOG_L_NOTICE: prio = LOG_NOTICE; break;
	case LOG_L_WARN: prio = LOG_WARNING; break;
	case LOG_L_ERR: prio = LOG_ERR; break;
	}

	va_start(ap, fmt);
	vsyslog(prio, fmt, ap);
	va_end(ap);
}

static enum log_level parse_log_level(const char *s)
{
	if (!s)
		return LOG_L_INFO;
	if (!strcmp(s, "debug")) return LOG_L_DEBUG;
	if (!strcmp(s, "notice")) return LOG_L_NOTICE;
	if (!strcmp(s, "warn") || !strcmp(s, "warning")) return LOG_L_WARN;
	if (!strcmp(s, "err") || !strcmp(s, "error")) return LOG_L_ERR;
	return LOG_L_INFO;
}

static void trim(char *s)
{
	size_t n;
	while (*s && isspace((unsigned char)*s))
		memmove(s, s + 1, strlen(s));
	n = strlen(s);
	while (n && isspace((unsigned char)s[n - 1]))
		s[--n] = '\0';
}

static int read_file_trim(const char *path, char *buf, size_t len)
{
	int fd;
	ssize_t n;

	if (!len)
		return -1;
	fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	n = read(fd, buf, len - 1);
	close(fd);
	if (n < 0)
		return -1;
	buf[n] = '\0';
	trim(buf);
	return 0;
}

static int path_exists(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0;
}

static int is_dir(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int capture_exec(char *const argv[], char *out, size_t out_len, int timeout_sec)
{
	int pipefd[2];
	pid_t pid;
	size_t used = 0;
	int status = 0;
	time_t start;

	if (out_len)
		out[0] = '\0';
	if (pipe(pipefd) < 0)
		return -1;

	pid = fork();
	if (pid < 0) {
		close(pipefd[0]);
		close(pipefd[1]);
		return -1;
	}
	if (pid == 0) {
		dup2(pipefd[1], STDOUT_FILENO);
		dup2(pipefd[1], STDERR_FILENO);
		close(pipefd[0]);
		close(pipefd[1]);
		execvp(argv[0], argv);
		_exit(127);
	}

	close(pipefd[1]);
	fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL, 0) | O_NONBLOCK);
	start = time(NULL);

	for (;;) {
		fd_set rfds;
		struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 };
		char tmp[512];
		ssize_t n;
		pid_t r;

		FD_ZERO(&rfds);
		FD_SET(pipefd[0], &rfds);
		if (select(pipefd[0] + 1, &rfds, NULL, NULL, &tv) > 0) {
			while ((n = read(pipefd[0], tmp, sizeof(tmp))) > 0) {
				if (out && out_len > 1 && used < out_len - 1) {
					size_t copy = (size_t)n;
					if (copy > out_len - 1 - used)
						copy = out_len - 1 - used;
					memcpy(out + used, tmp, copy);
					used += copy;
					out[used] = '\0';
				}
			}
		}

		r = waitpid(pid, &status, WNOHANG);
		if (r == pid)
			break;
		if (timeout_sec > 0 && time(NULL) - start >= timeout_sec) {
			kill(pid, SIGTERM);
			usleep(200000);
			if (waitpid(pid, &status, WNOHANG) == 0)
				kill(pid, SIGKILL);
			waitpid(pid, &status, 0);
			close(pipefd[0]);
			return -2;
		}
	}

	while (1) {
		char tmp[512];
		ssize_t n = read(pipefd[0], tmp, sizeof(tmp));
		if (n <= 0)
			break;
		if (out && out_len > 1 && used < out_len - 1) {
			size_t copy = (size_t)n;
			if (copy > out_len - 1 - used)
				copy = out_len - 1 - used;
			memcpy(out + used, tmp, copy);
			used += copy;
			out[used] = '\0';
		}
	}
	close(pipefd[0]);

	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	return -1;
}

static int run_exec(char *const argv[], int timeout_sec)
{
	char buf[256];
	return capture_exec(argv, buf, sizeof(buf), timeout_sec);
}

static int uci_get(const char *key, char *out, size_t out_len)
{
	char *argv[] = { "uci", "-q", "get", (char *)key, NULL };
	int rc = capture_exec(argv, out, out_len, 3);
	if (!rc)
		trim(out);
	return rc;
}

static int uci_set(const char *key, const char *value)
{
	char arg[768];
	char *argv[] = { "uci", "-q", "set", arg, NULL };
	snprintf(arg, sizeof(arg), "%s=%s", key, value ? value : "");
	return run_exec(argv, 3);
}

static int uci_del(const char *key)
{
	char *argv[] = { "uci", "-q", "del", (char *)key, NULL };
	return run_exec(argv, 3);
}

static int uci_add_list(const char *key, const char *value)
{
	char arg[768];
	char *argv[] = { "uci", "-q", "add_list", arg, NULL };
	snprintf(arg, sizeof(arg), "%s=%s", key, value ? value : "");
	return run_exec(argv, 3);
}

static void uci_commit(const char *config)
{
	char *argv[] = { "uci", "commit", (char *)config, NULL };
	run_exec(argv, 5);
}

static int find_slot_section(const char *slot, char *section, size_t len)
{
	char out[16384];
	char *argv[] = { "uci", "-q", "show", "qmodem", NULL };
	char *save = NULL, *line;
	int rc;

	section[0] = '\0';
	rc = capture_exec(argv, out, sizeof(out), 3);
	if (rc != 0)
		return -1;

	for (line = strtok_r(out, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
		char prefix[160], value[160];
		char *p;

		if (strncmp(line, "qmodem.", 7))
			continue;
		p = strstr(line, ".slot=");
		if (!p)
			continue;
		snprintf(value, sizeof(value), "%s", p + 6);
		trim(value);
		if ((value[0] == '\'' || value[0] == '"') && strlen(value) >= 2) {
			size_t n = strlen(value);
			memmove(value, value + 1, n);
			value[n - 2] = '\0';
		}
		if (strcmp(value, slot))
			continue;
		*p = '\0';
		snprintf(prefix, sizeof(prefix), "%s", line + 7);
		snprintf(section, len, "%s", prefix);
		return 0;
	}

	return -1;
}

static void get_slot_option(const char *slot, const char *opt, char *out, size_t len)
{
	char section[128], key[256];
	out[0] = '\0';
	if (find_slot_section(slot, section, sizeof(section)) != 0)
		return;
	snprintf(key, sizeof(key), "qmodem.%s.%s", section, opt);
	uci_get(key, out, len);
}

static void section_from_slot(const char *slot, char *out, size_t len)
{
	size_t j = 0;
	for (size_t i = 0; slot[i] && j + 1 < len; i++) {
		char c = slot[i];
		out[j++] = (c == '.' || c == ':' || c == '-') ? '_' : c;
	}
	out[j] = '\0';
}

static int basename_of(const char *path, char *out, size_t len)
{
	const char *p = strrchr(path, '/');
	snprintf(out, len, "%s", p ? p + 1 : path);
	return 0;
}

static int readlink_basename(const char *path, char *out, size_t len)
{
	char buf[512];
	ssize_t n = readlink(path, buf, sizeof(buf) - 1);
	if (n < 0)
		return -1;
	buf[n] = '\0';
	return basename_of(buf, out, len);
}

static void list_net_devices(const char *net_path, struct str_list *nets)
{
	DIR *d = opendir(net_path);
	struct dirent *de;
	if (!d)
		return;
	while ((de = readdir(d))) {
		if (de->d_name[0] == '.')
			continue;
		sl_add(nets, de->d_name);
	}
	closedir(d);
}

static void list_child_matching(const char *path, const char *prefix, struct str_list *out)
{
	DIR *d = opendir(path);
	struct dirent *de;
	size_t n = strlen(prefix);
	if (!d)
		return;
	while ((de = readdir(d))) {
		if (!strncmp(de->d_name, prefix, n))
			sl_add(out, de->d_name);
	}
	closedir(d);
}

static int json_get_obj(json_object *root, const char *key, json_object **out)
{
	return root && json_object_object_get_ex(root, key, out);
}

static const char *json_get_string_default(json_object *obj, const char *key, const char *def)
{
	json_object *v;
	if (json_get_obj(obj, key, &v) && json_object_is_type(v, json_type_string))
		return json_object_get_string(v);
	return def;
}

static int json_get_int_default(json_object *obj, const char *key, int def)
{
	json_object *v;
	if (json_get_obj(obj, key, &v))
		return json_object_get_int(v);
	return def;
}

static int load_port_rule(const char *vid, const char *pid, struct port_rule *rule)
{
	json_object *a, *usb, *obj, *include;
	char id[32];
	memset(rule, 0, sizeof(*rule));
	sl_init(&rule->include);
	if (!vid[0] || !pid[0])
		return 0;
	snprintf(id, sizeof(id), "%s:%s", vid, pid);
	if (!json_get_obj(g.port_rule_json, "modem_port_rule", &a) ||
	    !json_get_obj(a, "usb", &usb) ||
	    !json_get_obj(usb, id, &obj))
		return 0;
	rule->has_rule = 1;
	rule->option_driver = json_get_int_default(obj, "option_driver", 0);
	if (json_get_obj(obj, "include", &include) && json_object_is_type(include, json_type_array)) {
		int n = json_object_array_length(include);
		for (int i = 0; i < n; i++) {
			json_object *v = json_object_array_get_idx(include, i);
			if (v)
				sl_add(&rule->include, json_object_get_string(v));
		}
	}
	return 0;
}

static int interface_allowed(const struct port_rule *rule, const char *if_port)
{
	if (!rule->include.len)
		return 1;
	return sl_contains(&rule->include, if_port);
}

static void apply_option_driver(const char *vid, const char *pid)
{
	int fd;
	char line[64];
	if (!vid[0] || !pid[0])
		return;
	fd = open("/sys/bus/usb-serial/drivers/option1/new_id", O_WRONLY);
	if (fd < 0) {
		log_msg(LOG_L_DEBUG, "option new_id unavailable for %s:%s", vid, pid);
		return;
	}
	snprintf(line, sizeof(line), "%s %s\n", vid, pid);
	if (write(fd, line, strlen(line)) < 0)
		log_msg(LOG_L_WARN, "failed to bind option driver for %s:%s: %s", vid, pid, strerror(errno));
	close(fd);
}

static void scan_usb_slot(const char *slot, struct scan_result *res)
{
	char slot_path[256], path[512], driver_path[512], driver[128];
	char vid_path[512], pid_path[512];
	struct port_rule rule;
	DIR *d;
	struct dirent *de;

	snprintf(slot_path, sizeof(slot_path), "/sys/bus/usb/devices/%s", slot);
	if (!is_dir(slot_path))
		return;
	snprintf(res->modem_path, sizeof(res->modem_path), "/sys/bus/usb/devices/%s/", slot);
	snprintf(vid_path, sizeof(vid_path), "%s/idVendor", slot_path);
	snprintf(pid_path, sizeof(pid_path), "%s/idProduct", slot_path);
	read_file_trim(vid_path, res->vid, sizeof(res->vid));
	read_file_trim(pid_path, res->pid, sizeof(res->pid));
	load_port_rule(res->vid, res->pid, &rule);
	if (rule.option_driver) {
		res->option_driver = 1;
		apply_option_driver(res->vid, res->pid);
	}

	d = opendir(slot_path);
	if (!d) {
		sl_free(&rule.include);
		return;
	}
	while ((de = readdir(d))) {
		const char *suffix;
		char if_port[32] = "";
		if (de->d_name[0] == '.')
			continue;
		if (strncmp(de->d_name, slot, strlen(slot)) || de->d_name[strlen(slot)] != ':')
			continue;
		suffix = strrchr(de->d_name, ':');
		if (suffix)
			snprintf(if_port, sizeof(if_port), "%s", suffix + 1);
		if (!interface_allowed(&rule, if_port)) {
			log_msg(LOG_L_DEBUG, "skip usb %s interface %s by modem_port_rule", slot, if_port);
			continue;
		}
		snprintf(driver_path, sizeof(driver_path), "%s/%s/driver", slot_path, de->d_name);
		if (!path_exists(driver_path) || readlink_basename(driver_path, driver, sizeof(driver)) < 0)
			continue;

		snprintf(path, sizeof(path), "%s/%s", slot_path, de->d_name);
		if (!strcmp(driver, "option") || !strcmp(driver, "cdc_acm") ||
		    !strcmp(driver, "qcserial") || !strcmp(driver, "usbserial_generic") ||
		    !strcmp(driver, "usbserial")) {
			struct str_list ttys;
			sl_init(&ttys);
			list_child_matching(path, "ttyUSB", &ttys);
			list_child_matching(path, "ttyACM", &ttys);
			for (size_t i = 0; i < ttys.len; i++) {
				char dev[160];
				snprintf(dev, sizeof(dev), "/dev/%s", ttys.items[i]);
				sl_add(&res->at_ports, dev);
			}
			sl_free(&ttys);
		} else if (!strncmp(driver, "qmi_wwan", 8) || !strcmp(driver, "cdc_mbim") ||
			   strstr(driver, "cdc_ncm") || !strcmp(driver, "cdc_ether") ||
			   !strcmp(driver, "rndis_host")) {
			char net_path[512];
			snprintf(net_path, sizeof(net_path), "%s/net", path);
			list_net_devices(net_path, &res->net_devices);
		}
	}
	closedir(d);
	sl_free(&rule.include);
}

static void scan_associated_usb(const char *pcie_slot, struct scan_result *res)
{
	char usb_slot[128];
	char modem_path[sizeof(res->modem_path)];
	size_t net_len = res->net_devices.len;

	get_slot_option(pcie_slot, "associated_usb", usb_slot, sizeof(usb_slot));
	if (usb_slot[0]) {
		snprintf(modem_path, sizeof(modem_path), "%s", res->modem_path);
		scan_usb_slot(usb_slot, res);
		snprintf(res->modem_path, sizeof(res->modem_path), "%s", modem_path);
		sl_truncate(&res->net_devices, net_len);
	}
}

static void scan_pcie_slot(const char *slot, struct scan_result *res)
{
	char slot_path[256], path[512], short_slot[128];
	DIR *d;
	struct dirent *de;

	snprintf(slot_path, sizeof(slot_path), "/sys/bus/pci/devices/%s", slot);
	if (!is_dir(slot_path))
		return;
	snprintf(res->modem_path, sizeof(res->modem_path), "/sys/bus/pci/devices/%s/", slot);

	if (strlen(slot) > 4) {
		snprintf(short_slot, sizeof(short_slot), "%s", slot + 2);
		if (strlen(short_slot) > 2)
			short_slot[strlen(short_slot) - 2] = '\0';
		for (char *p = short_slot; *p; p++) {
			if (*p == ':')
				*p = '.';
		}
	} else {
		snprintf(short_slot, sizeof(short_slot), "%s", slot);
	}

	d = opendir(slot_path);
	if (d) {
		while ((de = readdir(d))) {
			char driver_path[512], driver[128];
			if (!strstr(de->d_name, short_slot))
				continue;
			snprintf(driver_path, sizeof(driver_path), "%s/%s/driver", slot_path, de->d_name);
			if (!path_exists(driver_path) || readlink_basename(driver_path, driver, sizeof(driver)) < 0)
				continue;
			if (!strcmp(driver, "mhi_netdev")) {
				snprintf(path, sizeof(path), "%s/%s/net", slot_path, de->d_name);
				list_net_devices(path, &res->net_devices);
			} else if (!strcmp(driver, "mhi_uci_q")) {
				struct str_list duns;
				snprintf(path, sizeof(path), "%s/%s/mhi_uci_q", slot_path, de->d_name);
				sl_init(&duns);
				list_child_matching(path, "mhi_DUN", &duns);
				for (size_t i = 0; i < duns.len; i++) {
					char dev[160];
					snprintf(dev, sizeof(dev), "/dev/%s", duns.items[i]);
					sl_add(&res->at_ports, dev);
					sl_add(&res->pcie_at_ports, dev);
				}
				sl_free(&duns);
			}
		}
		closedir(d);
	}

	snprintf(path, sizeof(path), "%s/mhi0/wwan/wwan0", slot_path);
	if (is_dir(path)) {
		struct str_list ats;
		sl_init(&ats);
		list_child_matching(path, "wwan0at", &ats);
		for (size_t i = 0; i < ats.len; i++) {
			char dev[160];
			snprintf(dev, sizeof(dev), "/dev/%s", ats.items[i]);
			sl_add(&res->at_ports, dev);
			sl_add(&res->pcie_at_ports, dev);
		}
		sl_free(&ats);
	}

	snprintf(path, sizeof(path), "%s/wwan", slot_path);
	if (is_dir(path)) {
		DIR *wd = opendir(path);
		if (wd) {
			while ((de = readdir(wd))) {
				char wwan_path[512];
				if (strncmp(de->d_name, "wwan", 4))
					continue;
				sl_add(&res->net_devices, de->d_name);
				snprintf(wwan_path, sizeof(wwan_path), "%s/%s", path, de->d_name);
				struct str_list ats;
				sl_init(&ats);
				list_child_matching(wwan_path, de->d_name, &ats);
				for (size_t i = 0; i < ats.len; i++) {
					if (strstr(ats.items[i], "at")) {
						char dev[160];
						snprintf(dev, sizeof(dev), "/dev/%s", ats.items[i]);
						sl_add(&res->at_ports, dev);
						sl_add(&res->pcie_at_ports, dev);
					}
				}
				sl_free(&ats);
			}
			closedir(wd);
		}
	}
}

static int at_command(const char *port, const char *cmd, int fast, int timeout, char *out, size_t out_len)
{
	int pipefd[2];
	pid_t pid;
	size_t used = 0;
	int status = 0;
	time_t start;
	const char *script =
		". /usr/share/qmodem/modem_util.sh; "
		"if [ \"$1\" = 1 ]; then "
		"fastat \"$2\" \"$3\"; "
		"else at \"$2\" \"$3\"; fi";

	if (out_len)
		out[0] = '\0';
	if (pipe(pipefd) < 0)
		return -1;

	pid = fork();
	if (pid < 0) {
		close(pipefd[0]);
		close(pipefd[1]);
		return -1;
	}
	if (pid == 0) {
		setpgid(0, 0);
		dup2(pipefd[1], STDOUT_FILENO);
		dup2(pipefd[1], STDERR_FILENO);
		close(pipefd[0]);
		close(pipefd[1]);
		execl("/bin/sh", "sh", "-c", script, "qmodem-at", fast ? "1" : "0", port, cmd, NULL);
		_exit(127);
	}

	close(pipefd[1]);
	fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL, 0) | O_NONBLOCK);
	start = time(NULL);
	for (;;) {
		fd_set rfds;
		struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 };
		char tmp[512];
		ssize_t n;
		pid_t r;

		FD_ZERO(&rfds);
		FD_SET(pipefd[0], &rfds);
		if (select(pipefd[0] + 1, &rfds, NULL, NULL, &tv) > 0) {
			while ((n = read(pipefd[0], tmp, sizeof(tmp))) > 0) {
				if (out_len > 1 && used < out_len - 1) {
					size_t copy = (size_t)n;
					if (copy > out_len - 1 - used)
						copy = out_len - 1 - used;
					memcpy(out + used, tmp, copy);
					used += copy;
					out[used] = '\0';
				}
			}
		}
		r = waitpid(pid, &status, WNOHANG);
		if (r == pid)
			break;
		if (timeout > 0 && time(NULL) - start >= timeout) {
			kill(-pid, SIGTERM);
			usleep(200000);
			if (waitpid(pid, &status, WNOHANG) == 0)
				kill(-pid, SIGKILL);
			waitpid(pid, &status, 0);
			close(pipefd[0]);
			log_msg(LOG_L_WARN, "AT timeout port=%s cmd=%s", port, cmd);
			return -2;
		}
	}
	close(pipefd[0]);
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

struct probe_ctx {
	const char *port;
	int ok;
};

static void *probe_port_thread(void *arg)
{
	struct probe_ctx *ctx = arg;
	char res[QMODEM_MAX_REPLY];
	ctx->ok = 0;
	if (!path_exists(ctx->port))
		return NULL;
	{
		char json[256];
		char *argv[] = { "ubus", "call", "at-daemon", "close", json, NULL };
		snprintf(json, sizeof(json), "{ \"at_port\": \"%s\" }", ctx->port);
		run_exec(argv, 2);
	}
	if (at_command(ctx->port, "ATI", 1, g.at_timeout_fast, res, sizeof(res)) == 0 &&
	    (strstr(res, "OK") || strstr(res, "ATI")))
		ctx->ok = 1;
	return NULL;
}

static void validate_ports(struct scan_result *res)
{
	size_t n = res->at_ports.len;
	pthread_t *threads = calloc(n, sizeof(*threads));
	struct probe_ctx *ctx = calloc(n, sizeof(*ctx));
	if (!threads || !ctx) {
		free(threads);
		free(ctx);
		return;
	}
	for (size_t start = 0; start < n; start += (size_t)g.at_probe_workers) {
		size_t end = start + (size_t)g.at_probe_workers;
		if (end > n)
			end = n;
		for (size_t i = start; i < end; i++) {
			ctx[i].port = res->at_ports.items[i];
			pthread_create(&threads[i], NULL, probe_port_thread, &ctx[i]);
		}
		for (size_t i = start; i < end; i++) {
			pthread_join(threads[i], NULL);
			if (ctx[i].ok) {
				sl_add(&res->valid_at_ports, res->at_ports.items[i]);
				if (!res->preferred_at[0])
					snprintf(res->preferred_at, sizeof(res->preferred_at), "%s", res->at_ports.items[i]);
			}
		}
	}
	for (size_t i = 0; i < res->pcie_at_ports.len; i++) {
		if (sl_contains(&res->valid_at_ports, res->pcie_at_ports.items[i])) {
			snprintf(res->preferred_at, sizeof(res->preferred_at), "%s", res->pcie_at_ports.items[i]);
			break;
		}
	}
	free(threads);
	free(ctx);
}

static void normalize_model_name(char *name, size_t len)
{
	char lower[256];
	size_t j = 0;
	for (size_t i = 0; name[i] && j + 1 < sizeof(lower); i++)
		lower[j++] = (char)tolower((unsigned char)name[i]);
	lower[j] = '\0';

	if (strstr(lower, "nl668")) snprintf(name, len, "nl668");
	else if (strstr(lower, "nl678")) snprintf(name, len, "nl678");
	else if (strstr(lower, "em120k")) snprintf(name, len, "em120k");
	else if (strstr(lower, "fm350-gl")) snprintf(name, len, "fm350-gl");
	else if (strstr(lower, "fm190w-gl")) snprintf(name, len, "fm190w-gl");
	else if (strstr(lower, "rm500u-ea")) snprintf(name, len, "rm500u-ea");
	else if (strstr(lower, "mv31-w") || strstr(lower, "t99w175")) snprintf(name, len, "t99w175");
	else if (strstr(lower, "t99w373")) snprintf(name, len, "t99w373");
	else if (strstr(lower, "dp25-42843-47")) snprintf(name, len, "t99w640");
	else if (strstr(lower, "sim8380g")) snprintf(name, len, "SIM8380G-M2");
	else if (strstr(lower, "rg200u-cn")) snprintf(name, len, "rg200u-cn");
	else if (strstr(lower, "nu313-m2")) snprintf(name, len, "srm821");
	else if (strstr(lower, "m601")) snprintf(name, len, "n510m");
	else snprintf(name, len, "%s", lower);
}

static int load_profile(const char *slot_type, const char *name, struct modem_profile *profile)
{
	json_object *support, *type_obj, *obj, *modes;
	memset(profile, 0, sizeof(*profile));
	sl_init(&profile->modes);
	if (!json_get_obj(g.support_json, "modem_support", &support) ||
	    !json_get_obj(support, slot_type, &type_obj) ||
	    !json_get_obj(type_obj, name, &obj))
		return -1;
	snprintf(profile->name, sizeof(profile->name), "%s", name);
	snprintf(profile->manufacturer, sizeof(profile->manufacturer), "%s", json_get_string_default(obj, "manufacturer", ""));
	snprintf(profile->platform, sizeof(profile->platform), "%s", json_get_string_default(obj, "platform", ""));
	snprintf(profile->pdp_index, sizeof(profile->pdp_index), "%s", json_get_string_default(obj, "pdp_index", ""));
	snprintf(profile->wcdma_band, sizeof(profile->wcdma_band), "%s", json_get_string_default(obj, "wcdma_band", ""));
	snprintf(profile->lte_band, sizeof(profile->lte_band), "%s", json_get_string_default(obj, "lte_band", ""));
	snprintf(profile->nsa_band, sizeof(profile->nsa_band), "%s", json_get_string_default(obj, "nsa_band", ""));
	snprintf(profile->sa_band, sizeof(profile->sa_band), "%s", json_get_string_default(obj, "sa_band", ""));
	if (json_get_obj(obj, "modes", &modes) && json_object_is_type(modes, json_type_array)) {
		int n = json_object_array_length(modes);
		for (int i = 0; i < n; i++) {
			json_object *v = json_object_array_get_idx(modes, i);
			if (v)
				sl_add(&profile->modes, json_object_get_string(v));
		}
	}
	return 0;
}

static int match_profile_by_id(const char *slot_type, const char *vid, const char *pid, struct modem_profile *profile)
{
	json_object *support, *type_obj;
	char id[32];
	if (!vid[0] || !pid[0])
		return -1;
	snprintf(id, sizeof(id), "%s:%s", vid, pid);
	if (!json_get_obj(g.support_json, "modem_support", &support) ||
	    !json_get_obj(support, slot_type, &type_obj))
		return -1;
	json_object_object_foreach(type_obj, key, val) {
		const char *cfg_id = json_get_string_default(val, "id", "");
		if (!strcmp(cfg_id, id))
			return load_profile(slot_type, key, profile);
	}
	return -1;
}

static int extract_candidate_lines(const char *res, struct str_list *names)
{
	char *copy = strdup(res ? res : "");
	char *save = NULL;
	char *line;
	if (!copy)
		return -1;
	for (line = strtok_r(copy, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
		trim(line);
		if (!*line || !strcmp(line, "OK") || !strncmp(line, "AT", 2))
			continue;
		if (strstr(line, "+CGMM:")) {
			char *p = strchr(line, ':');
			if (p) {
				p++;
				trim(p);
				if (*p == '"')
					p++;
				char *q = strchr(p, '"');
				if (q)
					*q = '\0';
				sl_add(names, p);
			}
		} else {
			sl_add(names, line);
		}
	}
	free(copy);
	return 0;
}

static int detect_profile(const char *slot_type, struct scan_result *res, struct modem_profile *profile)
{
	const char *cmds[] = { "AT+CGMM", "AT+CGMM?", "AT+GMM" };
	for (size_t i = 0; i < res->valid_at_ports.len; i++) {
		for (size_t c = 0; c < sizeof(cmds) / sizeof(cmds[0]); c++) {
			char reply[QMODEM_MAX_REPLY];
			struct str_list names;
			sl_init(&names);
			if (at_command(res->valid_at_ports.items[i], cmds[c], 0, g.at_timeout_model, reply, sizeof(reply)) != 0) {
				sl_free(&names);
				continue;
			}
			extract_candidate_lines(reply, &names);
			for (size_t n = 0; n < names.len; n++) {
				char name[128];
				snprintf(name, sizeof(name), "%s", names.items[n]);
				normalize_model_name(name, sizeof(name));
				if (!load_profile(slot_type, name, profile)) {
					sl_free(&names);
					return 0;
				}
			}
			sl_free(&names);
		}
	}
	return match_profile_by_id(slot_type, res->vid, res->pid, profile);
}

static void join_list(const struct str_list *l, char *out, size_t len)
{
	size_t used = 0;
	out[0] = '\0';
	for (size_t i = 0; i < l->len; i++) {
		int n = snprintf(out + used, used < len ? len - used : 0, "%s%s", i ? " " : "", l->items[i]);
		if (n < 0)
			return;
		used += (size_t)n;
		if (used >= len)
			return;
	}
}

static void exec_post_init(const char *section)
{
	char *argv[] = { "/usr/share/qmodem/modem_hook.sh", (char *)section, "post_init", NULL };
	run_exec(argv, 60);
}

static void reload_network(void)
{
	char *argv[] = { "/etc/init.d/qmodem_network", "reload", NULL };
	run_exec(argv, 60);
}

static int add_modem(const char *slot, const char *slot_type)
{
	struct scan_result res;
	struct modem_profile profile;
	char section[128], key[256], existing[64], fixed[16];
	char orig_network[512] = "", orig_at[128] = "", orig_state[64] = "", orig_name[128] = "";
	char net_join[512], default_alias[128] = "", default_metric[32] = "", led_script[128] = "";
	int existed;

	memset(&res, 0, sizeof(res));
	sl_init(&res.net_devices);
	sl_init(&res.at_ports);
	sl_init(&res.pcie_at_ports);
	sl_init(&res.valid_at_ports);
	section_from_slot(slot, section, sizeof(section));

	snprintf(key, sizeof(key), "qmodem.%s.fixed_device", section);
	uci_get(key, fixed, sizeof(fixed));
	if (!strcmp(fixed, "1")) {
		log_msg(LOG_L_INFO, "skip fixed device slot=%s section=%s", slot, section);
		exec_post_init(section);
		goto out_success;
	}

	if (!strcmp(slot_type, "usb")) {
		scan_usb_slot(slot, &res);
	} else if (!strcmp(slot_type, "pcie")) {
		scan_pcie_slot(slot, &res);
		scan_associated_usb(slot, &res);
	} else {
		goto out_fail;
	}

	if (!res.net_devices.len) {
		log_msg(LOG_L_INFO, "slot=%s type=%s has no net device yet", slot, slot_type);
		goto out_fail;
	}
	validate_ports(&res);
	if (!res.valid_at_ports.len) {
		log_msg(LOG_L_INFO, "slot=%s type=%s has no valid AT port yet ports=%zu", slot, slot_type, res.at_ports.len);
		goto out_fail;
	}
	if (detect_profile(slot_type, &res, &profile) != 0) {
		log_msg(LOG_L_WARN, "slot=%s type=%s modem profile not matched", slot, slot_type);
		goto out_fail;
	}

	join_list(&res.net_devices, net_join, sizeof(net_join));
	pthread_mutex_lock(&uci_lock);
	snprintf(key, sizeof(key), "qmodem.%s", section);
	existed = !uci_get(key, existing, sizeof(existing)) && existing[0];
	if (existed) {
		snprintf(key, sizeof(key), "qmodem.%s.network", section);
		uci_get(key, orig_network, sizeof(orig_network));
		snprintf(key, sizeof(key), "qmodem.%s.at_port", section);
		uci_get(key, orig_at, sizeof(orig_at));
		snprintf(key, sizeof(key), "qmodem.%s.state", section);
		uci_get(key, orig_state, sizeof(orig_state));
		snprintf(key, sizeof(key), "qmodem.%s.name", section);
		uci_get(key, orig_name, sizeof(orig_name));
		snprintf(key, sizeof(key), "qmodem.%s.modes", section); uci_del(key);
		snprintf(key, sizeof(key), "qmodem.%s.valid_at_ports", section); uci_del(key);
		snprintf(key, sizeof(key), "qmodem.%s.tty_devices", section); uci_del(key);
		snprintf(key, sizeof(key), "qmodem.%s.net_devices", section); uci_del(key);
		snprintf(key, sizeof(key), "qmodem.%s.ports", section); uci_del(key);
		snprintf(key, sizeof(key), "qmodem.%s.state", section); uci_set(key, "enabled");
	} else {
		char modem_count_s[32] = "", metric[32];
		int modem_count = 0;
		get_slot_option(slot, "alias", default_alias, sizeof(default_alias));
		get_slot_option(slot, "default_metric", default_metric, sizeof(default_metric));
		get_slot_option(slot, "led_script", led_script, sizeof(led_script));
		uci_get("qmodem.main.modem_count", modem_count_s, sizeof(modem_count_s));
		if (modem_count_s[0])
			modem_count = atoi(modem_count_s);
		modem_count++;
		snprintf(modem_count_s, sizeof(modem_count_s), "%d", modem_count);
		uci_set("qmodem.main.modem_count", modem_count_s);
		snprintf(key, sizeof(key), "qmodem.%s", section); uci_set(key, "modem-device");
		if (default_alias[0]) { snprintf(key, sizeof(key), "qmodem.%s.alias", section); uci_set(key, default_alias); }
		if (led_script[0]) { snprintf(key, sizeof(key), "qmodem.%s.led_script", section); uci_set(key, led_script); }
		snprintf(metric, sizeof(metric), "%d", modem_count + 10);
		if (default_metric[0])
			snprintf(metric, sizeof(metric), "%s", default_metric);
		snprintf(key, sizeof(key), "qmodem.%s.path", section); uci_set(key, res.modem_path);
		snprintf(key, sizeof(key), "qmodem.%s.data_interface", section); uci_set(key, slot_type);
		snprintf(key, sizeof(key), "qmodem.%s.enable_dial", section); uci_set(key, "1");
		snprintf(key, sizeof(key), "qmodem.%s.soft_reboot", section); uci_set(key, "1");
		snprintf(key, sizeof(key), "qmodem.%s.extend_prefix", section); uci_set(key, "1");
		snprintf(key, sizeof(key), "qmodem.%s.pdp_type", section); uci_set(key, "ipv4v6");
		snprintf(key, sizeof(key), "qmodem.%s.state", section); uci_set(key, "enabled");
		snprintf(key, sizeof(key), "qmodem.%s.metric", section); uci_set(key, metric);
	}

	snprintf(key, sizeof(key), "qmodem.%s.name", section); uci_set(key, profile.name);
	snprintf(key, sizeof(key), "qmodem.%s.network", section); uci_set(key, net_join);
	snprintf(key, sizeof(key), "qmodem.%s.manufacturer", section); uci_set(key, profile.manufacturer);
	snprintf(key, sizeof(key), "qmodem.%s.platform", section); uci_set(key, profile.platform);
	snprintf(key, sizeof(key), "qmodem.%s.suggest_pdp_index", section); uci_set(key, profile.pdp_index);
	if (profile.wcdma_band[0]) { snprintf(key, sizeof(key), "qmodem.%s.wcdma_band", section); uci_set(key, profile.wcdma_band); }
	if (profile.lte_band[0]) { snprintf(key, sizeof(key), "qmodem.%s.lte_band", section); uci_set(key, profile.lte_band); }
	if (profile.nsa_band[0]) { snprintf(key, sizeof(key), "qmodem.%s.nsa_band", section); uci_set(key, profile.nsa_band); }
	if (profile.sa_band[0]) { snprintf(key, sizeof(key), "qmodem.%s.sa_band", section); uci_set(key, profile.sa_band); }
	for (size_t i = 0; i < profile.modes.len; i++) {
		snprintf(key, sizeof(key), "qmodem.%s.modes", section);
		uci_add_list(key, profile.modes.items[i]);
	}
	for (size_t i = 0; i < res.valid_at_ports.len; i++) {
		snprintf(key, sizeof(key), "qmodem.%s.valid_at_ports", section);
		uci_add_list(key, res.valid_at_ports.items[i]);
	}
	snprintf(key, sizeof(key), "qmodem.%s.at_port", section);
	uci_set(key, res.preferred_at[0] ? res.preferred_at : res.valid_at_ports.items[0]);
	for (size_t i = 0; i < res.at_ports.len; i++) {
		snprintf(key, sizeof(key), "qmodem.%s.ports", section);
		uci_add_list(key, res.at_ports.items[i]);
	}
	if (res.option_driver) {
		snprintf(key, sizeof(key), "qmodem.%s.option_driver", section);
		uci_set(key, "1");
	}
	uci_commit("qmodem");
	pthread_mutex_unlock(&uci_lock);

	{
		char rundir[256];
		snprintf(rundir, sizeof(rundir), QMODEM_RUN_DIR "/%s_dir", section);
		mkdir(QMODEM_RUN_DIR, 0755);
		mkdir(rundir, 0755);
	}
	exec_post_init(section);
	if (!existed || strcmp(orig_network, net_join) || strcmp(orig_at, res.preferred_at) ||
	    strcmp(orig_state, "enabled") || strcmp(orig_name, profile.name))
		reload_network();

	log_msg(LOG_L_INFO, "added modem section=%s name=%s type=%s ports=%zu valid=%zu",
		section, profile.name, slot_type, res.at_ports.len, res.valid_at_ports.len);
	sl_free(&profile.modes);
out_success:
	sl_free(&res.net_devices);
	sl_free(&res.at_ports);
	sl_free(&res.pcie_at_ports);
	sl_free(&res.valid_at_ports);
	return 0;

out_fail:
	sl_free(&res.net_devices);
	sl_free(&res.at_ports);
	sl_free(&res.pcie_at_ports);
	sl_free(&res.valid_at_ports);
	return 1;
}

static void remove_modem(const char *section)
{
	char key[256], existing[64], count_s[32];
	int count = 0;
	snprintf(key, sizeof(key), "qmodem.%s", section);
	if (uci_get(key, existing, sizeof(existing)) || !existing[0])
		return;
	pthread_mutex_lock(&uci_lock);
	uci_get("qmodem.main.modem_count", count_s, sizeof(count_s));
	if (count_s[0])
		count = atoi(count_s);
	if (count > 0)
		count--;
	snprintf(count_s, sizeof(count_s), "%d", count);
	uci_set("qmodem.main.modem_count", count_s);
	snprintf(key, sizeof(key), "qmodem.%s", section); uci_del(key);
	snprintf(key, sizeof(key), "network.%s", section); uci_del(key);
	snprintf(key, sizeof(key), "network.%sv6", section); uci_del(key);
	snprintf(key, sizeof(key), "dhcp.%s", section); uci_del(key);
	uci_commit("network");
	uci_commit("dhcp");
	uci_commit("qmodem");
	pthread_mutex_unlock(&uci_lock);
	log_msg(LOG_L_INFO, "removed modem section=%s", section);
}

static void disable_slot(const char *slot)
{
	char section[128], key[256];
	char *argv_reorder[] = { "uci", "-q", "reorder", key, NULL };
	section_from_slot(slot, section, sizeof(section));
	pthread_mutex_lock(&uci_lock);
	snprintf(key, sizeof(key), "qmodem.%s=1", section);
	run_exec(argv_reorder, 3);
	snprintf(key, sizeof(key), "qmodem.%s.state", section);
	uci_set(key, "disabled");
	uci_commit("qmodem");
	pthread_mutex_unlock(&uci_lock);
	log_msg(LOG_L_INFO, "disabled slot=%s section=%s", slot, section);
}

static void scan_usb_all(void)
{
	DIR *d = opendir("/sys/class/net");
	struct dirent *de;
	struct str_list slots;
	sl_init(&slots);
	if (!d)
		return;
	while ((de = readdir(d))) {
		char dev_path[512], real[512], slot[128] = "";
		if (de->d_name[0] == '.')
			continue;
		if (strncmp(de->d_name, "usb", 3) && strncmp(de->d_name, "eth", 3) && strncmp(de->d_name, "wwan", 4))
			continue;
		snprintf(dev_path, sizeof(dev_path), "/sys/class/net/%s/device", de->d_name);
		if (!realpath(dev_path, real))
			continue;
		if (!strstr(real, "usb"))
			continue;
		{
			char tmp[512], *save = NULL, *tok;
			snprintf(tmp, sizeof(tmp), "%s", real);
			for (tok = strtok_r(tmp, "/", &save); tok; tok = strtok_r(NULL, "/", &save)) {
				if (strchr(tok, '-') && !strchr(tok, ':'))
					snprintf(slot, sizeof(slot), "%s", tok);
			}
		}
		if (slot[0])
			sl_add(&slots, slot);
	}
	closedir(d);
	for (size_t i = 0; i < slots.len; i++)
		add_modem(slots.items[i], "usb");
	sl_free(&slots);
}

static void scan_pcie_all(void)
{
	DIR *d;
	struct dirent *de;
	struct str_list slots;
	sl_init(&slots);
	{
		int fd = open("/sys/bus/pci/rescan", O_WRONLY);
		if (fd >= 0) {
			if (write(fd, "1\n", 2) < 0)
				log_msg(LOG_L_DEBUG, "failed to trigger pci rescan: %s", strerror(errno));
			close(fd);
			sleep(1);
		}
	}
	d = opendir("/sys/class/net");
	if (!d)
		return;
	while ((de = readdir(d))) {
		char dev_path[512], real[512], tmp[512], *save = NULL, *tok, last[128] = "";
		if (de->d_name[0] == '.')
			continue;
		if (strncmp(de->d_name, "rmnet", 5) && strncmp(de->d_name, "wwan", 4))
			continue;
		snprintf(dev_path, sizeof(dev_path), "/sys/class/net/%s/device", de->d_name);
		if (!realpath(dev_path, real))
			continue;
		if (!strstr(real, "pci"))
			continue;
		snprintf(tmp, sizeof(tmp), "%s", real);
		for (tok = strtok_r(tmp, "/", &save); tok; tok = strtok_r(NULL, "/", &save)) {
			if (strchr(tok, ':') && strchr(tok, '.'))
				snprintf(last, sizeof(last), "%s", tok);
		}
		if (last[0])
			sl_add(&slots, last);
	}
	closedir(d);
	for (size_t i = 0; i < slots.len; i++)
		add_modem(slots.items[i], "pcie");
	sl_free(&slots);
}

static int event_key(enum event_type type, const char *a, const char *b, char *out, size_t len)
{
	switch (type) {
	case EV_ADD: return snprintf(out, len, "add:%s:%s", b, a);
	case EV_REMOVE: return snprintf(out, len, "remove:%s", a);
	case EV_DISABLE: return snprintf(out, len, "disable:%s", a);
	case EV_SCAN: return snprintf(out, len, "scan:%s", a && *a ? a : "all");
	}
	return -1;
}

static int queue_has_key(const char *key)
{
	for (struct event *e = g.queue_head; e; e = e->next) {
		if (!strcmp(e->key, key))
			return 1;
	}
	return 0;
}

static void queue_remove_pending_add_for_slot(const char *slot)
{
	struct event *prev = NULL, *e = g.queue_head;

	while (e) {
		struct event *next = e->next;
		if (e->type == EV_ADD && !strcmp(e->slot, slot)) {
			if (prev)
				prev->next = next;
			else
				g.queue_head = next;
			if (g.queue_tail == e)
				g.queue_tail = prev;
			g.queue_len--;
			free(e);
		} else {
			prev = e;
		}
		e = next;
	}
}

static int enqueue_event_ex(enum event_type type, const char *arg, const char *slot_type, int delay_sec, int attempts)
{
	struct event *e = calloc(1, sizeof(*e));
	if (!e)
		return -1;
	e->type = type;
	if (arg)
		snprintf(type == EV_REMOVE ? e->section : e->slot,
			 type == EV_REMOVE ? sizeof(e->section) : sizeof(e->slot),
			 "%s", arg);
	if (slot_type)
		snprintf(e->slot_type, sizeof(e->slot_type), "%s", slot_type);
	if (delay_sec < 0)
		delay_sec = 0;
	e->not_before = time(NULL) + delay_sec;
	e->attempts = attempts;
	event_key(type, arg, slot_type, e->key, sizeof(e->key));

	pthread_mutex_lock(&g.queue_lock);
	if (type == EV_DISABLE)
		queue_remove_pending_add_for_slot(arg);
	if (queue_has_key(e->key) || (!attempts && sl_contains(&g.active_keys, e->key))) {
		pthread_mutex_unlock(&g.queue_lock);
		free(e);
		return 1;
	}
	if (!g.queue_head || e->not_before < g.queue_head->not_before) {
		e->next = g.queue_head;
		g.queue_head = e;
		if (!g.queue_tail)
			g.queue_tail = e;
	} else {
		struct event *cur = g.queue_head;
		while (cur->next && cur->next->not_before <= e->not_before)
			cur = cur->next;
		e->next = cur->next;
		cur->next = e;
		if (!e->next)
			g.queue_tail = e;
	}
	g.queue_len++;
	pthread_cond_signal(&g.queue_cond);
	pthread_mutex_unlock(&g.queue_lock);
	log_msg(LOG_L_INFO, "queued %s delay=%d attempts=%d", e->key, delay_sec, attempts);
	return 0;
}

static int enqueue_event(enum event_type type, const char *arg, const char *slot_type, int delay_sec)
{
	return enqueue_event_ex(type, arg, slot_type, delay_sec, 0);
}

static struct event *dequeue_event(void)
{
	struct event *e;
	pthread_mutex_lock(&g.queue_lock);
	for (;;) {
		time_t now;
		struct timespec ts;

		while (!g.stop && !g.queue_head)
			pthread_cond_wait(&g.queue_cond, &g.queue_lock);
		if (g.stop) {
			pthread_mutex_unlock(&g.queue_lock);
			return NULL;
		}

		e = g.queue_head;
		now = time(NULL);
		if (e->not_before <= now)
			break;
		ts.tv_sec = e->not_before;
		ts.tv_nsec = 0;
		pthread_cond_timedwait(&g.queue_cond, &g.queue_lock, &ts);
	}

	g.queue_head = e->next;
	if (!g.queue_head)
		g.queue_tail = NULL;
	g.queue_len--;
	g.active_jobs++;
	sl_add(&g.active_keys, e->key);
	pthread_mutex_unlock(&g.queue_lock);
	e->next = NULL;
	return e;
}

static void finish_event_key(const char *key)
{
	pthread_mutex_lock(&g.queue_lock);
	if (g.active_jobs > 0)
		g.active_jobs--;
	for (size_t i = 0; i < g.active_keys.len; i++) {
		if (!strcmp(g.active_keys.items[i], key)) {
			free(g.active_keys.items[i]);
			memmove(&g.active_keys.items[i], &g.active_keys.items[i + 1],
				(g.active_keys.len - i - 1) * sizeof(g.active_keys.items[0]));
			g.active_keys.len--;
			break;
		}
	}
	pthread_mutex_unlock(&g.queue_lock);
}

static void process_event(struct event *e)
{
	log_msg(LOG_L_INFO, "processing %s attempts=%d", e->key, e->attempts);
	switch (e->type) {
	case EV_ADD:
		if (add_modem(e->slot, e->slot_type) != 0) {
			if (e->attempts < g.add_retry_max) {
				log_msg(LOG_L_INFO, "retry add slot=%s type=%s next_delay=%d attempt=%d/%d",
					e->slot, e->slot_type, g.add_retry_delay, e->attempts + 1, g.add_retry_max);
				enqueue_event_ex(EV_ADD, e->slot, e->slot_type, g.add_retry_delay, e->attempts + 1);
			} else {
				log_msg(LOG_L_WARN, "give up add slot=%s type=%s after %d attempts",
					e->slot, e->slot_type, e->attempts);
			}
		}
		break;
	case EV_REMOVE:
		remove_modem(e->section);
		break;
	case EV_DISABLE:
		disable_slot(e->slot);
		break;
	case EV_SCAN:
		if (!strcmp(e->slot, "usb"))
			scan_usb_all();
		else if (!strcmp(e->slot, "pcie"))
			scan_pcie_all();
		else {
			scan_pcie_all();
			scan_usb_all();
		}
		break;
	}
}

static void *worker_thread(void *arg)
{
	(void)arg;
	for (;;) {
		struct event *e = dequeue_event();
		if (!e)
			return NULL;
		process_event(e);
		finish_event_key(e->key);
		free(e);
	}
}

static void handle_client(int fd)
{
	char buf[QMODEM_MAX_LINE];
	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	char cmd[64], a[128], b[128], c[128];
	int rc = -1;
	int delay_sec = 0;
	if (n <= 0)
		return;
	buf[n] = '\0';
	trim(buf);
	cmd[0] = a[0] = b[0] = c[0] = '\0';
	sscanf(buf, "%63s %127s %127s %127s", cmd, a, b, c);
	if (!strcmp(cmd, "add") && a[0] && b[0]) {
		delay_sec = c[0] ? atoi(c) : 0;
		rc = enqueue_event(EV_ADD, a, b, delay_sec);
	} else if (!strcmp(cmd, "remove") && a[0]) {
		delay_sec = b[0] ? atoi(b) : 0;
		rc = enqueue_event(EV_REMOVE, a, NULL, delay_sec);
	} else if (!strcmp(cmd, "disable") && a[0]) {
		delay_sec = b[0] ? atoi(b) : 0;
		rc = enqueue_event(EV_DISABLE, a, NULL, delay_sec);
	} else if (!strcmp(cmd, "scan")) {
		delay_sec = b[0] ? atoi(b) : 0;
		rc = enqueue_event(EV_SCAN, a[0] ? a : "all", NULL, delay_sec);
	}
	else if (!strcmp(cmd, "set-log-level") && a[0]) {
		g.log_level = parse_log_level(a);
		rc = 0;
	} else if (!strcmp(cmd, "status")) {
		pthread_mutex_lock(&g.queue_lock);
		dprintf(fd, "{\"queue\":%d,\"active\":%d,\"workers\":%d}\n", g.queue_len, g.active_jobs, g.scan_workers);
		pthread_mutex_unlock(&g.queue_lock);
		return;
	}
	if (rc == 0)
		dprintf(fd, "{\"code\":0,\"message\":\"queued\"}\n");
	else if (rc == 1)
		dprintf(fd, "{\"code\":0,\"message\":\"deduplicated\"}\n");
	else
		dprintf(fd, "{\"code\":1,\"message\":\"invalid request\"}\n");
}

static int setup_socket(void)
{
	int fd;
	struct sockaddr_un addr;
	mkdir(QMODEM_RUN_DIR, 0755);
	unlink(QMODEM_SCAND_SOCKET);
	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", QMODEM_SCAND_SOCKET);
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return -1;
	}
	chmod(QMODEM_SCAND_SOCKET, 0666);
	if (listen(fd, 32) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static void load_config_defaults(void)
{
	char val[64];
	const char *env_level;
	g.scan_workers = 4;
	g.at_probe_workers = 4;
	g.at_timeout_fast = 2;
	g.at_timeout_model = 8;
	g.add_retry_delay = 8;
	g.add_retry_max = 5;
	g.log_level = LOG_L_INFO;
	if (!uci_get("qmodem.main.scan_workers", val, sizeof(val)) && atoi(val) > 0)
		g.scan_workers = atoi(val);
	if (!uci_get("qmodem.main.at_probe_workers", val, sizeof(val)) && atoi(val) > 0)
		g.at_probe_workers = atoi(val);
	if (!uci_get("qmodem.main.at_timeout_fast", val, sizeof(val)) && atoi(val) > 0)
		g.at_timeout_fast = atoi(val);
	if (!uci_get("qmodem.main.at_timeout_model", val, sizeof(val)) && atoi(val) > 0)
		g.at_timeout_model = atoi(val);
	if (!uci_get("qmodem.main.add_retry_delay", val, sizeof(val)) && atoi(val) >= 0)
		g.add_retry_delay = atoi(val);
	if (!uci_get("qmodem.main.add_retry_max", val, sizeof(val)) && atoi(val) >= 0)
		g.add_retry_max = atoi(val);
	if (!uci_get("qmodem.main.scan_log_level", val, sizeof(val)) && val[0])
		g.log_level = parse_log_level(val);
	env_level = getenv("QMODEM_SCAN_LOG_LEVEL");
	if (env_level && *env_level)
		g.log_level = parse_log_level(env_level);
}

static void sig_handler(int signo)
{
	(void)signo;
	g.stop = 1;
	pthread_cond_broadcast(&g.queue_cond);
}

int main(int argc, char **argv)
{
	int sockfd;
	pthread_t *threads;

	(void)argc;
	(void)argv;
	openlog("modem_scand", LOG_PID, LOG_DAEMON);
	memset(&g, 0, sizeof(g));
	pthread_mutex_init(&g.queue_lock, NULL);
	pthread_cond_init(&g.queue_cond, NULL);
	sl_init(&g.active_keys);
	load_config_defaults();

	g.support_json = json_object_from_file(QMODEM_SUPPORT_JSON);
	g.port_rule_json = json_object_from_file(QMODEM_PORT_RULE_JSON);
	if (!g.support_json || !g.port_rule_json) {
		log_msg(LOG_L_ERR, "failed to load modem json files");
		return 1;
	}

	signal(SIGTERM, sig_handler);
	signal(SIGINT, sig_handler);
	sockfd = setup_socket();
	if (sockfd < 0) {
		syslog(LOG_ERR, "failed to setup socket %s: %s", QMODEM_SCAND_SOCKET, strerror(errno));
		return 1;
	}

	threads = calloc((size_t)g.scan_workers, sizeof(*threads));
	if (!threads)
		return 1;
	for (int i = 0; i < g.scan_workers; i++)
		pthread_create(&threads[i], NULL, worker_thread, NULL);

	log_msg(LOG_L_NOTICE, "modem_scand started workers=%d at_timeout_fast=%d at_timeout_model=%d add_retry_delay=%d add_retry_max=%d",
		g.scan_workers, g.at_timeout_fast, g.at_timeout_model, g.add_retry_delay, g.add_retry_max);

	while (!g.stop) {
		int cfd = accept(sockfd, NULL, NULL);
		if (cfd < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		handle_client(cfd);
		close(cfd);
	}

	close(sockfd);
	unlink(QMODEM_SCAND_SOCKET);
	pthread_mutex_lock(&g.queue_lock);
	g.stop = 1;
	pthread_cond_broadcast(&g.queue_cond);
	pthread_mutex_unlock(&g.queue_lock);
	for (int i = 0; i < g.scan_workers; i++)
		pthread_join(threads[i], NULL);
	free(threads);
	if (g.support_json)
		json_object_put(g.support_json);
	if (g.port_rule_json)
		json_object_put(g.port_rule_json);
	sl_free(&g.active_keys);
	closelog();
	return 0;
}
