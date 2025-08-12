#include "ubus_at_daemon.h"

#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))

at_daemon_ctx_t g_daemon_ctx;

// Policy for open method
enum {
    OPEN_AT_PORT,
    OPEN_BAUDRATE,
    OPEN_DATABITS,
    OPEN_PARITY,
    OPEN_STOPBITS,
    OPEN_TIMEOUT,
    __OPEN_MAX
};

static const struct blobmsg_policy open_policy[] = {
    [OPEN_AT_PORT] = { .name = JSON_AT_PORT, .type = BLOBMSG_TYPE_STRING },
    [OPEN_BAUDRATE] = { .name = JSON_BAUDRATE, .type = BLOBMSG_TYPE_INT32 },
    [OPEN_DATABITS] = { .name = JSON_DATABITS, .type = BLOBMSG_TYPE_INT32 },
    [OPEN_PARITY] = { .name = JSON_PARITY, .type = BLOBMSG_TYPE_INT32 },
    [OPEN_STOPBITS] = { .name = JSON_STOPBITS, .type = BLOBMSG_TYPE_INT32 },
    [OPEN_TIMEOUT] = { .name = JSON_TIMEOUT, .type = BLOBMSG_TYPE_INT32 },
};

// Policy for sendat method
enum {
    SENDAT_AT_PORT,
    SENDAT_TIMEOUT,
    SENDAT_END_FLAG,
    SENDAT_AT_CMD,
    SENDAT_RAW_AT_CONTENT,
    SENDAT_SENDONLY,
    __SENDAT_MAX
};

static const struct blobmsg_policy sendat_policy[] = {
    [SENDAT_AT_PORT] = { .name = JSON_AT_PORT, .type = BLOBMSG_TYPE_STRING },
    [SENDAT_TIMEOUT] = { .name = JSON_TIMEOUT, .type = BLOBMSG_TYPE_INT32 },
    [SENDAT_END_FLAG] = { .name = "end_flag", .type = BLOBMSG_TYPE_STRING },
    [SENDAT_AT_CMD] = { .name = "at_cmd", .type = BLOBMSG_TYPE_STRING },
    [SENDAT_RAW_AT_CONTENT] = { .name = "raw_at_content", .type = BLOBMSG_TYPE_STRING },
    [SENDAT_SENDONLY] = { .name = "sendonly", .type = BLOBMSG_TYPE_BOOL },
};

// Policy for close method
enum {
    CLOSE_AT_PORT,
    __CLOSE_MAX
};

static const struct blobmsg_policy close_policy[] = {
    [CLOSE_AT_PORT] = { .name = JSON_AT_PORT, .type = BLOBMSG_TYPE_STRING },
};

// Ubus method: open
static int ubus_open_method(struct ubus_context *ctx, struct ubus_object *obj,
                           struct ubus_request_data *req, const char *method,
                           struct blob_attr *msg) {
    struct blob_attr *tb[__OPEN_MAX];
    const char *at_port;
    int baudrate = 115200;  // Default values from const.h
    int databits = DEFAULT_DATABITS;
    int parity = DEFAULT_PARITY;
    int stopbits = DEFAULT_STOPBITS;
    int timeout = DEFAULT_TIMEOUT;
    
    blobmsg_parse(open_policy, __OPEN_MAX, tb, blob_data(msg), blob_len(msg));
    
    if (!tb[OPEN_AT_PORT]) {
        return UBUS_STATUS_INVALID_ARGUMENT;
    }
    
    at_port = blobmsg_get_string(tb[OPEN_AT_PORT]);
    
    if (tb[OPEN_BAUDRATE])
        baudrate = blobmsg_get_u32(tb[OPEN_BAUDRATE]);
    if (tb[OPEN_DATABITS])
        databits = blobmsg_get_u32(tb[OPEN_DATABITS]);
    if (tb[OPEN_PARITY])
        parity = blobmsg_get_u32(tb[OPEN_PARITY]);
    if (tb[OPEN_STOPBITS])
        stopbits = blobmsg_get_u32(tb[OPEN_STOPBITS]);
    if (tb[OPEN_TIMEOUT])
        timeout = blobmsg_get_u32(tb[OPEN_TIMEOUT]);
    
    // Find existing port instance
    at_port_instance_t *port = find_port_instance(at_port);
    int is_new_port = (port == NULL);
    
    if (!port) {
        // Check if port file exists before creating instance
        if (access(at_port, F_OK) != 0) {
            struct blob_buf b = {};
            blob_buf_init(&b, 0);
            blobmsg_add_string(&b, "status", "error");
            blobmsg_add_string(&b, "message", "Port file does not exist");
            ubus_send_reply(ctx, req, b.head);
            blob_buf_free(&b);
            return UBUS_STATUS_OK;
        }
        
        port = create_port_instance(at_port);
        if (!port) {
            return UBUS_STATUS_NO_DATA;
        }
    }
    
    // Open the port
    int result = open_at_port(port, baudrate, databits, parity, stopbits);
    
    struct blob_buf b = {};
    blob_buf_init(&b, 0);
    
    if (result == 0) {
        blobmsg_add_string(&b, "status", "success");
        blobmsg_add_string(&b, "port", at_port);
        blobmsg_add_u32(&b, "baudrate", baudrate);
        blobmsg_add_u32(&b, "databits", databits);
        blobmsg_add_u32(&b, "parity", parity);
        blobmsg_add_u32(&b, "stopbits", stopbits);
        ubus_send_reply(ctx, req, b.head);
    } else {
        blobmsg_add_string(&b, "status", "error");
        blobmsg_add_string(&b, "message", "Failed to open port");
        ubus_send_reply(ctx, req, b.head);
        
        // If this was a new port instance and opening failed, remove it from the list
        if (is_new_port) {
            destroy_port_instance(port);
        }
    }
    
    blob_buf_free(&b);
    return UBUS_STATUS_OK;
}

static int ubus_sendat_method(struct ubus_context *ctx, struct ubus_object *obj,
                             struct ubus_request_data *req, const char *method,
                             struct blob_attr *msg) {
    struct blob_attr *tb[__SENDAT_MAX];
    const char *at_port, *at_cmd = NULL, *raw_at_content = NULL, *end_flag = NULL;
    int timeout = DEFAULT_TIMEOUT;
    int is_raw = 0;
    int sendonly = 0;
    
    blobmsg_parse(sendat_policy, __SENDAT_MAX, tb, blob_data(msg), blob_len(msg));
    
    if (!tb[SENDAT_AT_PORT]) {
        return UBUS_STATUS_INVALID_ARGUMENT;
    }
    
    at_port = blobmsg_get_string(tb[SENDAT_AT_PORT]);
    
    if (tb[SENDAT_TIMEOUT])
        timeout = blobmsg_get_u32(tb[SENDAT_TIMEOUT]);
    if (tb[SENDAT_END_FLAG])
        end_flag = blobmsg_get_string(tb[SENDAT_END_FLAG]);
    if (tb[SENDAT_SENDONLY])
        sendonly = blobmsg_get_bool(tb[SENDAT_SENDONLY]);
    
    if (tb[SENDAT_AT_CMD]) {
        at_cmd = blobmsg_get_string(tb[SENDAT_AT_CMD]);
        is_raw = 0;
    } else if (tb[SENDAT_RAW_AT_CONTENT]) {
        raw_at_content = blobmsg_get_string(tb[SENDAT_RAW_AT_CONTENT]);
        is_raw = 1;
    } else {
        return UBUS_STATUS_INVALID_ARGUMENT;
    }
    
    // Find or create port instance
    at_port_instance_t *port = find_port_instance(at_port);
    if (!port) {
        port = create_port_instance(at_port);
        if (!port) {
            return UBUS_STATUS_NO_DATA;
        }
    }
    
    const char *cmd = is_raw ? raw_at_content : at_cmd;
    int result;
    at_response_t response;
    
    if (sendonly) {
        // Send only without waiting for response
        result = send_at_command_only(port, cmd, is_raw);
    } else {
        // Send AT command with response
        result = send_at_command_with_response(port, cmd, timeout, end_flag, is_raw, &response);
    }
    
    struct blob_buf b = {};
    blob_buf_init(&b, 0);
    
    blobmsg_add_string(&b, "port", at_port);
    blobmsg_add_string(&b, "command", cmd);
    blobmsg_add_u32(&b, "is_raw", is_raw);
    blobmsg_add_u32(&b, "sendonly", sendonly);
    
    if (sendonly) {
        // For send-only mode
        if (result == 0) {
            blobmsg_add_string(&b, "status", "success");
            blobmsg_add_string(&b, "message", "Command sent successfully");
        } else {
            blobmsg_add_string(&b, "status", "error");
            blobmsg_add_string(&b, "message", "Failed to send AT command");
        }
    } else {
        // For normal mode with response
        blobmsg_add_u32(&b, "timeout", timeout);
        blobmsg_add_string(&b, "end_flag", end_flag ? end_flag : "default");
        
        // Add debug info about end flags used
        void *end_flags_array = blobmsg_open_array(&b, "end_flags_used");
        for (int i = 0; i < port->num_end_flags; i++) {
            blobmsg_add_string(&b, NULL, port->expected_end_flags[i]);
        }
        blobmsg_close_array(&b, end_flags_array);
        
        if (result == 0) {
            blobmsg_add_string(&b, "status", "success");
            blobmsg_add_string(&b, "response", response.response);
            blobmsg_add_u32(&b, "response_length", response.response_len);
            blobmsg_add_string(&b, "end_flag_matched", response.end_flag_matched);
            blobmsg_add_u32(&b, "response_time_ms", response.response_time_ms);
        } else if (result == -1) {
            blobmsg_add_string(&b, "status", "timeout");
            blobmsg_add_string(&b, "message", "AT command timed out");
            blobmsg_add_u32(&b, "response_time_ms", response.response_time_ms);
            if (strlen(response.response) > 0) {
                blobmsg_add_string(&b, "partial_response", response.response);
            }
        } else {
            blobmsg_add_string(&b, "status", "error");
            blobmsg_add_string(&b, "message", "Failed to send AT command");
            blobmsg_add_u32(&b, "response_time_ms", response.response_time_ms);
        }
    }
    
    ubus_send_reply(ctx, req, b.head);
    blob_buf_free(&b);
    return UBUS_STATUS_OK;
}

// Ubus method: list
static int ubus_list_method(struct ubus_context *ctx, struct ubus_object *obj,
                           struct ubus_request_data *req, const char *method,
                           struct blob_attr *msg) {
    struct blob_buf b = {};
    blob_buf_init(&b, 0);
    
    void *array = blobmsg_open_array(&b, "ports");
    
    pthread_mutex_lock(&g_daemon_ctx.ports_mutex);
    at_port_instance_t *current = g_daemon_ctx.ports;
    
    while (current) {
        void *port_obj = blobmsg_open_table(&b, NULL);
        blobmsg_add_string(&b, "port", current->port_path);
        blobmsg_add_u32(&b, "is_open", current->is_open);
        if (current->is_open) {
            blobmsg_add_u32(&b, "fd", current->fd);
            if (current->configured_baudrate > 0) {
                blobmsg_add_u32(&b, "baudrate", current->configured_baudrate);
                blobmsg_add_u32(&b, "databits", current->configured_databits);
                blobmsg_add_u32(&b, "parity", current->configured_parity);
                blobmsg_add_u32(&b, "stopbits", current->configured_stopbits);
            }
        } else {
            // Check if file exists for closed ports
            if (access(current->port_path, F_OK) == 0) {
                blobmsg_add_string(&b, "file_status", "exists");
            } else {
                blobmsg_add_string(&b, "file_status", "missing");
            }
        }
        blobmsg_add_u32(&b, "last_check", (uint32_t)current->last_check_time);
        blobmsg_close_table(&b, port_obj);
        current = current->next;
    }
    
    pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
    blobmsg_close_array(&b, array);
    
    ubus_send_reply(ctx, req, b.head);
    blob_buf_free(&b);
    return UBUS_STATUS_OK;
}

// Ubus method: close
static int ubus_close_method(struct ubus_context *ctx, struct ubus_object *obj,
                            struct ubus_request_data *req, const char *method,
                            struct blob_attr *msg) {
    struct blob_attr *tb[__CLOSE_MAX];
    const char *at_port;
    
    blobmsg_parse(close_policy, __CLOSE_MAX, tb, blob_data(msg), blob_len(msg));
    
    if (!tb[CLOSE_AT_PORT]) {
        return UBUS_STATUS_INVALID_ARGUMENT;
    }
    
    at_port = blobmsg_get_string(tb[CLOSE_AT_PORT]);
    
    at_port_instance_t *port = find_port_instance(at_port);
    
    struct blob_buf b = {};
    blob_buf_init(&b, 0);
    
    if (port) {
        close_at_port(port);
        destroy_port_instance(port);
        blobmsg_add_string(&b, "status", "success");
        blobmsg_add_string(&b, "port", at_port);
        blobmsg_add_string(&b, "message", "Port closed and removed");
    } else {
        blobmsg_add_string(&b, "status", "error");
        blobmsg_add_string(&b, "message", "Port not found");
    }
    
    ubus_send_reply(ctx, req, b.head);
    blob_buf_free(&b);
    return UBUS_STATUS_OK;
}

// Ubus methods table
static const struct ubus_method at_daemon_methods[] = {
    UBUS_METHOD("open", ubus_open_method, open_policy),
    UBUS_METHOD("sendat", ubus_sendat_method, sendat_policy),
    UBUS_METHOD_NOARG("list", ubus_list_method),
    UBUS_METHOD("close", ubus_close_method, close_policy),
};

static struct ubus_object_type at_daemon_object_type =
    UBUS_OBJECT_TYPE("at-daemon", at_daemon_methods);

static struct ubus_object at_daemon_object = {
    .name = "at-daemon",
    .type = &at_daemon_object_type,
    .methods = at_daemon_methods,
    .n_methods = ARRAY_SIZE(at_daemon_methods),
};

static void server_main(void) {
    uloop_init();
    
    g_daemon_ctx.ctx = ubus_connect(NULL);
    if (!g_daemon_ctx.ctx) {
        fprintf(stderr, "Failed to connect to ubus\n");
        return;
    }
    
    ubus_add_uloop(g_daemon_ctx.ctx);
    
    int ret = ubus_add_object(g_daemon_ctx.ctx, &at_daemon_object);
    if (ret) {
        fprintf(stderr, "Failed to add object: %s\n", ubus_strerror(ret));
        return;
    }
    
    g_daemon_ctx.obj = at_daemon_object;
    
    // Start port monitoring thread
    start_port_monitor();
    
    printf("ubus-at-daemon started\n");
    uloop_run();
    
    // Stop port monitoring thread
    stop_port_monitor();
    
    ubus_free(g_daemon_ctx.ctx);
    uloop_done();
}

int main(int argc, char **argv) {
    // Initialize global context
    memset(&g_daemon_ctx, 0, sizeof(g_daemon_ctx));
    g_daemon_ctx.ports = NULL;
    pthread_mutex_init(&g_daemon_ctx.ports_mutex, NULL);
    
    server_main();
    
    // Cleanup
    pthread_mutex_lock(&g_daemon_ctx.ports_mutex);
    at_port_instance_t *current = g_daemon_ctx.ports;
    while (current) {
        at_port_instance_t *next = current->next;
        destroy_port_instance(current);
        current = next;
    }
    pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
    
    pthread_mutex_destroy(&g_daemon_ctx.ports_mutex);
    
    return 0;
}
