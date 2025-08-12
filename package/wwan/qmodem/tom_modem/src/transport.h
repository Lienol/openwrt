#ifndef _TRANSPORT_H_
#define _TRANSPORT_H_

#include "modem_types.h"
#include "ttydevice.h"
#include "utils.h"
#ifdef ENABLE_UBUS_DAEMON
#include "ubus_client.h"
#endif

// Transport operation function pointers
typedef struct {
    int (*send_at_with_response)(PROFILE_T *profile, const char *at_cmd, const char *end_flag, int is_raw, char **response_text);
    int (*send_at_only)(PROFILE_T *profile, const char *at_cmd, int is_raw);
    int (*open_device)(PROFILE_T *profile, void *ctx);
    int (*close_device)(PROFILE_T *profile, void *ctx);
} transport_ops_t;

// Transport context structure
typedef struct {
    transport_type_t type;
    const transport_ops_t *ops;
    union {
        FDS_T *tty_fds;  // For TTY transport
#ifdef ENABLE_UBUS_DAEMON
        ubus_client_t *ubus_client;  // For UBUS transport
#endif
    } ctx;
} transport_t;

// Global transport functions
int transport_init(transport_t *transport, transport_type_t type);
void transport_cleanup(transport_t *transport);

// Unified transport operations
int transport_send_at_with_response(transport_t *transport, PROFILE_T *profile, 
                                   const char *at_cmd, const char *end_flag, 
                                   int is_raw, char **response_text);
int transport_send_at_only(transport_t *transport, PROFILE_T *profile, 
                          const char *at_cmd, int is_raw);
int transport_open_device(transport_t *transport, PROFILE_T *profile);
int transport_close_device(transport_t *transport, PROFILE_T *profile);

// TTY-specific operations
extern const transport_ops_t tty_transport_ops;

#ifdef ENABLE_UBUS_DAEMON
// UBUS-specific operations
extern const transport_ops_t ubus_transport_ops;
#endif

#endif // _TRANSPORT_H_