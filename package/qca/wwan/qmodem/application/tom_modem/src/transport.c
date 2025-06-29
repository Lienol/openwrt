#include "transport.h"
#include "utils.h"
#include "operations.h"

// TTY transport operations implementation
static int tty_send_at_with_response(PROFILE_T *profile, const char *at_cmd, const char *end_flag, int is_raw, char **response_text) {
    FDS_T *fds = (FDS_T *)profile->transport_ctx;
    if (!fds || !fds->fdo || !fds->fdi) {
        err_msg("TTY device not opened");
        return COMM_ERROR;
    }

    int w_ret, r_ret;
    AT_MESSAGE_T message = {0};

    if (is_raw) {
        char *binary_cmd = malloc(strlen(at_cmd) / 2 + 1);
        if (!binary_cmd) {
            err_msg("Memory allocation failed");
            return COMM_ERROR;
        }
        
        int hex_ret = str_to_hex((char*)at_cmd, binary_cmd);
        if (hex_ret) {
            free(binary_cmd);
            err_msg("Invalid hex string");
            return INVALID_HEX;
        }
        
        w_ret = tty_write_raw(fds->fdo, binary_cmd);
        free(binary_cmd);
    } else {
        w_ret = tty_write(fds->fdo, at_cmd);
    }

    if (w_ret) {
        err_msg("Failed to write AT command");
        return w_ret;
    }

    if (end_flag) {
        r_ret = tty_read_keyword(fds->fdi, &message, (char*)end_flag, profile);
    } else {
        r_ret = tty_read(fds->fdi, &message, profile);
    }

    if (r_ret && r_ret != KEYWORD_NOT_MATCH) {
        dbg_msg("Error reading AT response, error code: %d", r_ret);
        if (message.message) {
            free(message.message);
        }
        return r_ret;
    }

    if (response_text && message.message) {
        *response_text = message.message;
    } else if (message.message) {
        free(message.message);
    }

    return (r_ret == KEYWORD_NOT_MATCH) ? r_ret : SUCCESS;
}

static int tty_send_at_only(PROFILE_T *profile, const char *at_cmd, int is_raw) {
    FDS_T *fds = (FDS_T *)profile->transport_ctx;
    if (!fds || !fds->fdo) {
        err_msg("TTY device not opened");
        return COMM_ERROR;
    }

    int w_ret;
    if (is_raw) {
        char *binary_cmd = malloc(strlen(at_cmd) / 2 + 1);
        if (!binary_cmd) {
            err_msg("Memory allocation failed");
            return COMM_ERROR;
        }
        
        int hex_ret = str_to_hex((char*)at_cmd, binary_cmd);
        if (hex_ret) {
            free(binary_cmd);
            err_msg("Invalid hex string");
            return INVALID_HEX;
        }
        
        w_ret = tty_write_raw(fds->fdo, binary_cmd);
        free(binary_cmd);
    } else {
        w_ret = tty_write(fds->fdo, at_cmd);
    }

    return w_ret;
}

static int tty_open_device_transport(PROFILE_T *profile, void *ctx) {
    FDS_T *fds = (FDS_T *)ctx;
    return tty_open_device(profile, fds);
}

static int tty_close_device_transport(PROFILE_T *profile, void *ctx) {
    FDS_T *fds = (FDS_T *)ctx;
    if (fds && fds->tty_fd >= 0) {
        if (tcsetattr(fds->tty_fd, TCSANOW, &fds->old_termios) != 0) {
            err_msg("Error restoring old tty attributes");
        }
        tcflush(fds->tty_fd, TCIOFLUSH);
        close(fds->tty_fd);
        fds->tty_fd = -1;
    }
    return SUCCESS;
}

const transport_ops_t tty_transport_ops = {
    .send_at_with_response = tty_send_at_with_response,
    .send_at_only = tty_send_at_only,
    .open_device = tty_open_device_transport,
    .close_device = tty_close_device_transport
};

#ifdef ENABLE_UBUS_DAEMON
// UBUS transport operations implementation  
static int ubus_send_at_with_response_transport(PROFILE_T *profile, const char *at_cmd, const char *end_flag, int is_raw, char **response_text) {
    ubus_client_t *client = (ubus_client_t *)profile->transport_ctx;
    if (!client || !client->connected) {
        err_msg("UBUS client not connected");
        return COMM_ERROR;
    }
    
    ubus_at_response_t response;
    int result = ubus_send_at_command(client, profile->tty_dev, at_cmd, 
                                     profile->timeout, end_flag, is_raw, &response);
    
    if (result == 0 && response_text && response.response) {
        *response_text = strdup(response.response);
    }

    if (result != 0) {
        err_msg("UBUS AT command failed with status: %d", response.status);
        ubus_at_response_free(&response);
        return COMM_ERROR;
    }
    
    ubus_at_response_free(&response);
    return SUCCESS;
}

static int ubus_send_at_only_transport(PROFILE_T *profile, const char *at_cmd, int is_raw) {
    ubus_client_t *client = (ubus_client_t *)profile->transport_ctx;
    if (!client || !client->connected) {
        err_msg("UBUS client not connected");
        return COMM_ERROR;
    }
    
    int result = ubus_send_at_command_only(client, profile->tty_dev, at_cmd, is_raw);
    
    if (result != 0) {
        err_msg("UBUS AT command (sendonly) failed with result: %d", result);
        return COMM_ERROR;
    }
    
    return SUCCESS;
}

static int ubus_open_device_transport(PROFILE_T *profile, void *ctx) {
    ubus_client_t *client = (ubus_client_t *)ctx;
    
    // Try to open the device
    int open_result = ubus_at_open_device(client, profile->tty_dev, 
                                        profile->baud_rate, profile->data_bits, 
                                        0, 1); // parity=0 (none), stopbits=1
    if (open_result != 0) {
        dbg_msg("Failed to open device %s via ubus", profile->tty_dev);
        return COMM_ERROR;
    } else {
        dbg_msg("Opened device %s via ubus", profile->tty_dev);
        return SUCCESS;
    }
}

static int ubus_close_device_transport(PROFILE_T *profile, void *ctx) {
    ubus_client_t *client = (ubus_client_t *)ctx;
    return ubus_at_close_device(client, profile->tty_dev);
}

const transport_ops_t ubus_transport_ops = {
    .send_at_with_response = ubus_send_at_with_response_transport,
    .send_at_only = ubus_send_at_only_transport,
    .open_device = ubus_open_device_transport,
    .close_device = ubus_close_device_transport
};
#endif

// Global transport functions implementation
int transport_init(transport_t *transport, transport_type_t type) {
    if (!transport) {
        return COMM_ERROR;
    }

    transport->type = type;
    
    switch (type) {
        case TRANSPORT_TTY:
            transport->ops = &tty_transport_ops;
            transport->ctx.tty_fds = malloc(sizeof(FDS_T));
            if (!transport->ctx.tty_fds) {
                err_msg("Failed to allocate TTY context");
                return COMM_ERROR;
            }
            memset(transport->ctx.tty_fds, 0, sizeof(FDS_T));
            break;
            
#ifdef ENABLE_UBUS_DAEMON
        case TRANSPORT_UBUS:
            transport->ops = &ubus_transport_ops;
            transport->ctx.ubus_client = malloc(sizeof(ubus_client_t));
            if (!transport->ctx.ubus_client) {
                err_msg("Failed to allocate UBUS context");
                return COMM_ERROR;
            }
            memset(transport->ctx.ubus_client, 0, sizeof(ubus_client_t));
            
            if (ubus_client_init(transport->ctx.ubus_client) != 0) {
                err_msg("Failed to initialize UBUS client");
                free(transport->ctx.ubus_client);
                return COMM_ERROR;
            }
            break;
#endif
            
        default:
            err_msg("Unsupported transport type: %d", type);
            return COMM_ERROR;
    }
    
    return SUCCESS;
}

void transport_cleanup(transport_t *transport) {
    if (!transport) {
        return;
    }

    switch (transport->type) {
        case TRANSPORT_TTY:
            if (transport->ctx.tty_fds) {
                free(transport->ctx.tty_fds);
                transport->ctx.tty_fds = NULL;
            }
            break;
            
#ifdef ENABLE_UBUS_DAEMON
        case TRANSPORT_UBUS:
            if (transport->ctx.ubus_client) {
                ubus_client_cleanup(transport->ctx.ubus_client);
                free(transport->ctx.ubus_client);
                transport->ctx.ubus_client = NULL;
            }
            break;
#endif
    }
}

// Unified transport operations
int transport_send_at_with_response(transport_t *transport, PROFILE_T *profile, 
                                   const char *at_cmd, const char *end_flag, 
                                   int is_raw, char **response_text) {
    if (!transport || !transport->ops || !transport->ops->send_at_with_response) {
        err_msg("Invalid transport or operations");
        return COMM_ERROR;
    }

    // Set transport context in profile
    switch (transport->type) {
        case TRANSPORT_TTY:
            profile->transport_ctx = transport->ctx.tty_fds;
            break;
#ifdef ENABLE_UBUS_DAEMON
        case TRANSPORT_UBUS:
            profile->transport_ctx = transport->ctx.ubus_client;
            break;
#endif
    }

    return transport->ops->send_at_with_response(profile, at_cmd, end_flag, is_raw, response_text);
}

int transport_send_at_only(transport_t *transport, PROFILE_T *profile, 
                          const char *at_cmd, int is_raw) {
    if (!transport || !transport->ops || !transport->ops->send_at_only) {
        err_msg("Invalid transport or operations");
        return COMM_ERROR;
    }

    // Set transport context in profile
    switch (transport->type) {
        case TRANSPORT_TTY:
            profile->transport_ctx = transport->ctx.tty_fds;
            break;
#ifdef ENABLE_UBUS_DAEMON
        case TRANSPORT_UBUS:
            profile->transport_ctx = transport->ctx.ubus_client;
            break;
#endif
    }

    return transport->ops->send_at_only(profile, at_cmd, is_raw);
}

int transport_open_device(transport_t *transport, PROFILE_T *profile) {
    if (!transport || !transport->ops || !transport->ops->open_device) {
        err_msg("Invalid transport or operations");
        return COMM_ERROR;
    }

    void *ctx = NULL;
    switch (transport->type) {
        case TRANSPORT_TTY:
            ctx = transport->ctx.tty_fds;
            break;
#ifdef ENABLE_UBUS_DAEMON
        case TRANSPORT_UBUS:
            ctx = transport->ctx.ubus_client;
            break;
#endif
    }

    return transport->ops->open_device(profile, ctx);
}

int transport_close_device(transport_t *transport, PROFILE_T *profile) {
    if (!transport || !transport->ops || !transport->ops->close_device) {
        err_msg("Invalid transport or operations");
        return COMM_ERROR;
    }

    void *ctx = NULL;
    switch (transport->type) {
        case TRANSPORT_TTY:
            ctx = transport->ctx.tty_fds;
            break;
#ifdef ENABLE_UBUS_DAEMON
        case TRANSPORT_UBUS:
            ctx = transport->ctx.ubus_client;
            break;
#endif
    }

    return transport->ops->close_device(profile, ctx);
}
