#ifndef UBUS_AT_DAEMON_H
#define UBUS_AT_DAEMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <pthread.h>
#include <regex.h>
#include <time.h>
#include <stdint.h>
#ifndef QMODEM_HOST_TEST
#include <json-c/json.h>
#include <libubus.h>
#include <libubox/uloop.h>
#include <libubox/blobmsg_json.h>
#else
struct ubus_context;
struct ubus_object { int unused; };
#endif

#include "const.h"

// AT command response structure
typedef struct at_response {
    char response[MAX_BUFFER_SIZE];
    int response_len;
    int status;  // 0: success, -1: timeout, -2: error
    char end_flag_matched[64];
    struct timespec start_time;
    struct timespec end_time;
    long response_time_ms;  // Response time in milliseconds
} at_response_t;

// AT command queue item
typedef struct at_queue_item {
    char at_cmd[MAX_AT_CMD_SIZE];
    char raw_content[MAX_AT_CMD_SIZE];
    int timeout;
    char end_flag[64];
    int is_raw;
    struct at_queue_item *next;
} at_queue_item_t;

// Event callback structure
typedef struct event_callback {
    char callback_script[MAX_SCRIPT_PATH_SIZE];
    char callback_reg[MAX_REGEX_SIZE];
    char callback_prefix[MAX_PREFIX_SIZE];
    regex_t compiled_regex;
    int has_regex;
    int match_all;
    struct event_callback *next;
} event_callback_t;

typedef enum {
    AT_CORRELATION_IDLE,
    AT_CORRELATION_RESPONSE,
    AT_CORRELATION_TERMINAL,
    AT_CORRELATION_AMBIGUOUS
} at_correlation_t;

typedef struct {
    char port[MAX_PORT_PATH_SIZE];
    uint64_t epoch;
    uint64_t sequence;
    uint64_t monotonic_ms;
    char line[MAX_AT_LINE_SIZE];
    size_t line_len;
    uint64_t command_id;
    at_correlation_t correlation;
    uint64_t drop_count;
} at_line_event_t;

typedef struct {
    at_line_event_t entries[AT_LINE_QUEUE_CAPACITY];
    size_t head;
    size_t count;
    uint64_t drop_count;
    uint64_t pending_drop_count;
    pthread_mutex_t mutex;
    int notify_pipe[2];
#ifndef QMODEM_HOST_TEST
    struct uloop_fd notify_fd;
#endif
} at_line_event_queue_t;

typedef void (*at_line_event_publisher_t)(const at_line_event_t *event,
                                          void *opaque);

// AT port instance
typedef struct at_port_instance {
    char port_path[MAX_PORT_PATH_SIZE];
    int fd;
    struct termios termios_config;
    
    // Port configuration for reconnection
    int configured_baudrate;
    int configured_databits;
    int configured_parity;
    int configured_stopbits;
    
    // Thread and synchronization
    pthread_t reader_thread;
    pthread_mutex_t lifecycle_mutex;
    pthread_mutex_t state_mutex;
    int reader_thread_valid;
    pthread_mutex_t queue_mutex;
    pthread_mutex_t write_mutex;
    pthread_cond_t queue_cond;
    
    // Queue and buffer
    at_queue_item_t *queue_head;
    at_queue_item_t *queue_tail;
    char read_buffer[MAX_BUFFER_SIZE];
    int buffer_pos;
    
    // Response handling
    at_response_t current_response;
    pthread_mutex_t response_mutex;
    pthread_mutex_t event_state_mutex;
    pthread_cond_t response_cond;
    int waiting_for_response;
    uint64_t restart_epoch;
    uint64_t line_sequence;
    uint64_t next_command_id;
    uint64_t active_command_id;
    char expected_end_flags[5][64];  // Support multiple end flags
    int num_end_flags;
    
    // Event callbacks
    event_callback_t *callbacks;
    
    // Status
    int is_open;
    int should_stop;
    
    // Port monitoring
    time_t last_check_time;
    int check_interval;  // in seconds
    
    struct at_port_instance *next;
} at_port_instance_t;

static inline void at_port_event_state_snapshot(at_port_instance_t *port,
                                                uint64_t *epoch,
                                                uint64_t *sequence)
{
    pthread_mutex_lock(&port->event_state_mutex);
    *epoch = port->restart_epoch;
    *sequence = port->line_sequence;
    pthread_mutex_unlock(&port->event_state_mutex);
}

static inline void at_port_next_line_event_state(at_port_instance_t *port,
                                                 uint64_t *epoch,
                                                 uint64_t *sequence)
{
    pthread_mutex_lock(&port->event_state_mutex);
    port->line_sequence++;
    *epoch = port->restart_epoch;
    *sequence = port->line_sequence;
    pthread_mutex_unlock(&port->event_state_mutex);
}

static inline void at_port_advance_restart_epoch(at_port_instance_t *port)
{
    pthread_mutex_lock(&port->event_state_mutex);
    port->restart_epoch++;
    pthread_mutex_unlock(&port->event_state_mutex);
}

// Global context
typedef struct {
    struct ubus_context *ctx;
    struct ubus_object obj;
    at_port_instance_t *ports;
    pthread_mutex_t ports_mutex;
    at_line_event_queue_t line_events;
    uint64_t daemon_epoch;
    
    // Port monitoring thread
    pthread_t monitor_thread;
    int monitor_should_stop;
} at_daemon_ctx_t;

// Function declarations
at_port_instance_t *find_port_instance(const char *port_path);
at_port_instance_t *create_port_instance(const char *port_path);
void destroy_port_instance(at_port_instance_t *port);

int open_at_port(at_port_instance_t *port, int baudrate, int databits, int parity, int stopbits);
void close_at_port(at_port_instance_t *port);

int send_at_command_with_response(at_port_instance_t *port, const char *cmd, int timeout, const char *end_flag, int is_raw, at_response_t *response);
int send_at_command(at_port_instance_t *port, const char *cmd, int timeout, const char *end_flag, int is_raw);
int send_at_command_only(at_port_instance_t *port, const char *cmd, int is_raw);
void *reader_thread_func(void *arg);
void parse_end_flags(at_port_instance_t *port, const char *end_flag_str);
int check_end_flags(at_port_instance_t *port, const char *line, char *matched_flag);

int at_line_events_init(at_line_event_queue_t *queue);
void at_line_events_cleanup(at_line_event_queue_t *queue);
void at_line_event_enqueue(at_line_event_queue_t *queue, at_port_instance_t *port,
                           const char *line, size_t line_len,
                           uint64_t command_id, at_correlation_t correlation);
int at_line_event_dequeue(at_line_event_queue_t *queue, at_line_event_t *event);
size_t at_line_events_consume(at_line_event_queue_t *queue, size_t budget,
                              at_line_event_publisher_t publisher, void *opaque);
const char *at_correlation_name(at_correlation_t correlation);
#ifndef QMODEM_HOST_TEST
int at_line_events_register_uloop(at_line_event_queue_t *queue);
#endif

void add_event_callback(at_port_instance_t *port, const char *script, const char *regex, const char *prefix);
void remove_event_callback(at_port_instance_t *port, const char *script);
void clear_event_callbacks(at_port_instance_t *port);
void process_incoming_data(at_port_instance_t *port, const char *data);

int load_config_from_json(const char *json_path);
char *hex_to_string(const char *hex_str);

// Port monitoring functions
void *port_monitor_thread_func(void *arg);
void check_and_reconnect_port(at_port_instance_t *port);
void start_port_monitor(void);
void stop_port_monitor(void);

#ifndef QMODEM_HOST_TEST
// Ubus method handlers
static int ubus_open_method(struct ubus_context *ctx, struct ubus_object *obj,
                           struct ubus_request_data *req, const char *method,
                           struct blob_attr *msg);
static int ubus_sendat_method(struct ubus_context *ctx, struct ubus_object *obj,
                             struct ubus_request_data *req, const char *method,
                             struct blob_attr *msg);
static int ubus_list_method(struct ubus_context *ctx, struct ubus_object *obj,
                           struct ubus_request_data *req, const char *method,
                           struct blob_attr *msg);
static int ubus_close_method(struct ubus_context *ctx, struct ubus_object *obj,
                            struct ubus_request_data *req, const char *method,
                            struct blob_attr *msg);
static int ubus_event_callback_method(struct ubus_context *ctx, struct ubus_object *obj,
                                     struct ubus_request_data *req, const char *method,
                                     struct blob_attr *msg);
static int ubus_event_callback_list_method(struct ubus_context *ctx, struct ubus_object *obj,
                                          struct ubus_request_data *req, const char *method,
                                          struct blob_attr *msg);
static int ubus_event_callback_remove_method(struct ubus_context *ctx, struct ubus_object *obj,
                                            struct ubus_request_data *req, const char *method,
                                            struct blob_attr *msg);
static int ubus_event_callback_clear_method(struct ubus_context *ctx, struct ubus_object *obj,
                                           struct ubus_request_data *req, const char *method,
                                           struct blob_attr *msg);
static int ubus_load_conf_method(struct ubus_context *ctx, struct ubus_object *obj,
                                struct ubus_request_data *req, const char *method,
                                struct blob_attr *msg);
#endif

extern at_daemon_ctx_t g_daemon_ctx;

#endif // UBUS_AT_DAEMON_H
