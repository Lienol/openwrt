#include <assert.h>
#include <poll.h>

#include "ubus_at_daemon.h"

at_daemon_ctx_t g_daemon_ctx;
static size_t sent_events;

static fake_blob_field_t *field_by_name(struct blob_buf *b, const char *name)
{
    for (size_t i = 0; i < b->count; i++) {
        if (strcmp(b->fields[i].name, name) == 0)
            return &b->fields[i];
    }
    assert(!"missing blob field");
    return NULL;
}

int ubus_send_event(struct ubus_context *ctx, const char *id,
                    struct blob_attr *msg)
{
    struct blob_buf *b = (struct blob_buf *)msg;
    (void)ctx;
    assert(strcmp(id, "qmodem.at.line") == 0);
    assert(b->count == 8);
    if (sent_events == 0) {
        assert(strcmp(field_by_name(b, "port")->string, "/dev/ttyFAKE0") == 0);
        assert(field_by_name(b, "restart_epoch")->u64 == 77);
        assert(field_by_name(b, "sequence")->u64 == 1);
        assert(field_by_name(b, "monotonic_ms")->u64 > 0);
        assert(strcmp(field_by_name(b, "raw_line")->string, "LINE-00") == 0);
        assert(field_by_name(b, "raw_line")->length == 8);
        assert(field_by_name(b, "command_id")->u64 == 9);
        assert(strcmp(field_by_name(b, "correlation")->string, "response") == 0);
        assert(field_by_name(b, "drop_count")->u64 == 0);
    }
    sent_events++;
    return 0;
}

#include "../src/line_events.c"

int main(void)
{
    at_port_instance_t port = { 0 };
    struct pollfd pfd;

    strcpy(port.port_path, "/dev/ttyFAKE0");
    port.restart_epoch = 77;
    assert(pthread_mutex_init(&port.event_state_mutex, NULL) == 0);
    assert(at_line_events_init(&g_daemon_ctx.line_events) == 0);
    assert(at_line_events_register_uloop(&g_daemon_ctx.line_events) == 0);
    assert(g_daemon_ctx.line_events.notify_fd.registered == 1);

    for (unsigned int i = 0; i < 65; i++) {
        char line[16];
        int length = snprintf(line, sizeof(line), "LINE-%02u", i);
        assert(length == 7);
        at_line_event_enqueue(&g_daemon_ctx.line_events, &port, line,
                              (size_t)length, 9, AT_CORRELATION_RESPONSE);
    }

    g_daemon_ctx.line_events.notify_fd.cb(&g_daemon_ctx.line_events.notify_fd,
                                           ULOOP_READ);
    assert(sent_events == AT_LINE_EVENT_DRAIN_BUDGET);
    assert(g_daemon_ctx.line_events.count == 1);
    pfd.fd = g_daemon_ctx.line_events.notify_pipe[0];
    pfd.events = POLLIN;
    assert(poll(&pfd, 1, 0) == 1);
    assert((pfd.revents & POLLIN) != 0);

    g_daemon_ctx.line_events.notify_fd.cb(&g_daemon_ctx.line_events.notify_fd,
                                           ULOOP_READ);
    assert(sent_events == 65);
    assert(g_daemon_ctx.line_events.count == 0);
    at_line_events_cleanup(&g_daemon_ctx.line_events);
    pthread_mutex_destroy(&port.event_state_mutex);
    puts("PASS production ubus blob fields and 64-item uloop callback rearm");
    return 0;
}
