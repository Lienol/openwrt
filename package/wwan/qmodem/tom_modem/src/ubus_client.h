#ifndef _UBUS_CLIENT_H_
#define _UBUS_CLIENT_H_

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "modem_types.h"

// Check if ubus is available
#include <json-c/json.h>
#include <libubus.h>
#include <libubox/blobmsg_json.h>

// ubus AT daemon service name
#define UBUS_AT_DAEMON_SERVICE "at-daemon"

// ubus client context
typedef struct {
    struct ubus_context *ctx;
    int connected;
} ubus_client_t;

// AT response structure for ubus
typedef struct {
    char *response;
    int status;
    char *end_flag_matched;
    long response_time_ms;
} ubus_at_response_t;

// Function declarations
int ubus_client_init(ubus_client_t *client);
void ubus_client_cleanup(ubus_client_t *client);

int ubus_at_open_device(ubus_client_t *client, const char *device_path, 
                        int baud_rate, int data_bits, int parity, int stop_bits);
int ubus_at_close_device(ubus_client_t *client, const char *device_path);

int ubus_send_at_command(ubus_client_t *client, const char *device_path,
                         const char *at_cmd, int timeout, const char *end_flag,
                         int is_raw, ubus_at_response_t *response);

int ubus_send_at_command_only(ubus_client_t *client, const char *device_path,
                              const char *at_cmd, int is_raw);

void ubus_at_response_free(ubus_at_response_t *response);

// Global ubus client functions for easy access
int init_global_ubus_client(void);
void cleanup_global_ubus_client(void);
ubus_client_t *get_global_ubus_client(void);

#endif // _UBUS_CLIENT_H_
