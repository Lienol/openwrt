#include "ubus_client.h"
#include "utils.h"


static ubus_client_t g_ubus_client = {0};

int ubus_client_init(ubus_client_t *client) {
    if (!client) {
        return -1;
    }
    
    client->ctx = ubus_connect(NULL);
    if (!client->ctx) {
        err_msg("Failed to connect to ubus");
        return -1;
    }
    
    client->connected = 1;
    dbg_msg("Connected to ubus successfully");
    return 0;
}

void ubus_client_cleanup(ubus_client_t *client) {
    if (client && client->ctx) {
        ubus_free(client->ctx);
        client->ctx = NULL;
        client->connected = 0;
        dbg_msg("Disconnected from ubus");
    }
}

static uint32_t find_service_id(struct ubus_context *ctx, const char *service_name) {
    uint32_t id;
    int ret = ubus_lookup_id(ctx, service_name, &id);
    if (ret != UBUS_STATUS_OK) {
        err_msg("Failed to find service %s: %s", service_name, ubus_strerror(ret));
        return 0;
    }
    return id;
}

int ubus_at_open_device(ubus_client_t *client, const char *device_path, 
                        int baud_rate, int data_bits, int parity, int stop_bits) {
    if (!client || !client->connected || !device_path) {
        return -1;
    }
    
    uint32_t service_id = find_service_id(client->ctx, UBUS_AT_DAEMON_SERVICE);
    if (!service_id) {
        return -1;
    }
    
    struct blob_buf b = {0};
    blob_buf_init(&b, 0);
    blobmsg_add_string(&b, "at_port", device_path);
    blobmsg_add_u32(&b, "baudrate", baud_rate);
    blobmsg_add_u32(&b, "databits", data_bits);
    blobmsg_add_u32(&b, "parity", parity);
    blobmsg_add_u32(&b, "stopbits", stop_bits);
    
    int ret = ubus_invoke(client->ctx, service_id, "open", b.head, NULL, NULL, 5000);
    blob_buf_free(&b);
    
    if (ret != UBUS_STATUS_OK) {
        err_msg("Failed to open AT device via ubus: %s", ubus_strerror(ret));
        return -1;
    }
    
    dbg_msg("Opened AT device %s via ubus", device_path);
    return 0;
}

int ubus_at_close_device(ubus_client_t *client, const char *device_path) {
    if (!client || !client->connected || !device_path) {
        return -1;
    }
    
    uint32_t service_id = find_service_id(client->ctx, UBUS_AT_DAEMON_SERVICE);
    if (!service_id) {
        return -1;
    }
    
    struct blob_buf b = {0};
    blob_buf_init(&b, 0);
    blobmsg_add_string(&b, "at_port", device_path);
    
    int ret = ubus_invoke(client->ctx, service_id, "close", b.head, NULL, NULL, 5000);
    blob_buf_free(&b);
    
    if (ret != UBUS_STATUS_OK) {
        err_msg("Failed to close AT device via ubus: %s", ubus_strerror(ret));
        return -1;
    }
    
    dbg_msg("Closed AT device %s via ubus", device_path);
    return 0;
}

static void ubus_sendat_callback(struct ubus_request *req, int type, struct blob_attr *msg) {
    ubus_at_response_t *response = (ubus_at_response_t *)req->priv;
    
    if (!response || !msg) {
        return;
    }
    
    struct blob_attr *tb[4];
    static const struct blobmsg_policy response_policy[] = {
        [0] = { .name = "response", .type = BLOBMSG_TYPE_STRING },
        [1] = { .name = "status", .type = BLOBMSG_TYPE_STRING },
        [2] = { .name = "end_flag_matched", .type = BLOBMSG_TYPE_STRING },
        [3] = { .name = "response_time_ms", .type = BLOBMSG_TYPE_INT32 },
    };
    
    blobmsg_parse(response_policy, 4, tb, blob_data(msg), blob_len(msg));
    
    if (tb[0]) {
        const char *resp_str = blobmsg_get_string(tb[0]);
        response->response = strdup(resp_str);
    }
    
    if (tb[1]) {
        const char *status_str = blobmsg_get_string(tb[1]);
        // Convert string status to integer: "success" -> 0, others -> -1
        response->status = (strcmp(status_str, "success") == 0) ? 0 : -1;
    }
    
    if (tb[2]) {
        const char *end_flag = blobmsg_get_string(tb[2]);
        response->end_flag_matched = strdup(end_flag);
    }
    
    if (tb[3]) {
        response->response_time_ms = blobmsg_get_u32(tb[3]);
    }
}

int ubus_send_at_command(ubus_client_t *client, const char *device_path,
                         const char *at_cmd, int timeout, const char *end_flag,
                         int is_raw, ubus_at_response_t *response) {
    if (!client || !client->connected || !device_path || !at_cmd || !response) {
        return -1;
    }
    
    // Initialize response
    memset(response, 0, sizeof(ubus_at_response_t));
    response->status = -1;
    
    uint32_t service_id = find_service_id(client->ctx, UBUS_AT_DAEMON_SERVICE);
    if (!service_id) {
        return -1;
    }
    
    struct blob_buf b = {0};
    blob_buf_init(&b, 0);
    blobmsg_add_string(&b, "at_port", device_path);
    //add boolean for sendonly
    //blobmsg_add_u8(&b, "sendonly", 1);
    if (is_raw) {
        blobmsg_add_string(&b, "raw_at_content", at_cmd);
    } else {
        blobmsg_add_string(&b, "at_cmd", at_cmd);
    }
    
    blobmsg_add_u32(&b, "timeout", timeout);
    
    if (end_flag && strlen(end_flag) > 0) {
        blobmsg_add_string(&b, "end_flag", end_flag);
    }
    
    int ret = ubus_invoke(client->ctx, service_id, "sendat", b.head, 
                         ubus_sendat_callback, response, timeout * 1000 + 1000);
    blob_buf_free(&b);
    
    if (ret != UBUS_STATUS_OK) {
        err_msg("Failed to send AT command via ubus: %s", ubus_strerror(ret));
        return -1;
    }
    
    dbg_msg("Sent AT command via ubus: %s", at_cmd);
    return response->status;
}

int ubus_send_at_command_only(ubus_client_t *client, const char *device_path,
                              const char *at_cmd, int is_raw) {
    if (!client || !client->connected || !device_path || !at_cmd) {
        return -1;
    }
    
    uint32_t service_id = find_service_id(client->ctx, UBUS_AT_DAEMON_SERVICE);
    if (!service_id) {
        return -1;
    }
    
    struct blob_buf b = {0};
    blob_buf_init(&b, 0);
    blobmsg_add_string(&b, "at_port", device_path);
    blobmsg_add_u8(&b, "sendonly", 1);  // Set sendonly flag to true
    
    if (is_raw) {
        blobmsg_add_string(&b, "raw_at_content", at_cmd);
    } else {
        blobmsg_add_string(&b, "at_cmd", at_cmd);
    }
    
    blobmsg_add_u32(&b, "timeout", 1000);  // Set minimal timeout for sendonly mode
    
    int ret = ubus_invoke(client->ctx, service_id, "sendat", b.head, 
                         NULL, NULL, 2000);  // No callback needed for sendonly
    blob_buf_free(&b);
    
    if (ret != UBUS_STATUS_OK) {
        err_msg("Failed to send AT command (sendonly) via ubus: %s", ubus_strerror(ret));
        return -1;
    }
    
    dbg_msg("Sent AT command (sendonly) via ubus: %s", at_cmd);
    return 0;
}

void ubus_at_response_free(ubus_at_response_t *response) {
    if (response) {
        if (response->response) {
            free(response->response);
            response->response = NULL;
        }
        if (response->end_flag_matched) {
            free(response->end_flag_matched);
            response->end_flag_matched = NULL;
        }
    }
}

// Global ubus client functions for easy access
int init_global_ubus_client(void) {
    return ubus_client_init(&g_ubus_client);
}

void cleanup_global_ubus_client(void) {
    ubus_client_cleanup(&g_ubus_client);
}

ubus_client_t *get_global_ubus_client(void) {
    return &g_ubus_client;
}
