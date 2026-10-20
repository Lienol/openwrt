#include "ubus_at_daemon.h"

static uint64_t monotonic_ms(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000U + (uint64_t)now.tv_nsec / 1000000U;
}

static void notify_consumer(at_line_event_queue_t *queue)
{
    char byte = 1;

    if (write(queue->notify_pipe[1], &byte, sizeof(byte)) < 0 && errno != EAGAIN)
        fprintf(stderr, "Failed to notify AT event consumer: %s\n",
                strerror(errno));
}

const char *at_correlation_name(at_correlation_t correlation)
{
    static const char *const names[] = {
        "idle", "response", "terminal", "ambiguous"
    };
    if ((unsigned int)correlation >= sizeof(names) / sizeof(names[0]))
        return "ambiguous";
    return names[correlation];
}

int at_line_events_init(at_line_event_queue_t *queue)
{
    memset(queue, 0, sizeof(*queue));
    queue->notify_pipe[0] = -1;
    queue->notify_pipe[1] = -1;
    if (pthread_mutex_init(&queue->mutex, NULL) != 0)
        return -1;
    if (pipe2(queue->notify_pipe, O_NONBLOCK | O_CLOEXEC) != 0) {
        pthread_mutex_destroy(&queue->mutex);
        return -1;
    }
    return 0;
}

void at_line_events_cleanup(at_line_event_queue_t *queue)
{
#ifndef QMODEM_HOST_TEST
    if (queue->notify_fd.registered)
        uloop_fd_delete(&queue->notify_fd);
#endif
    if (queue->notify_pipe[0] >= 0)
        close(queue->notify_pipe[0]);
    if (queue->notify_pipe[1] >= 0)
        close(queue->notify_pipe[1]);
    pthread_mutex_destroy(&queue->mutex);
}

void at_line_event_enqueue(at_line_event_queue_t *queue, at_port_instance_t *port,
                           const char *line, size_t line_len,
                           uint64_t command_id, at_correlation_t correlation)
{
    at_line_event_t *event;
    uint64_t epoch;
    uint64_t sequence;
    int overflowed = 0;

    at_port_next_line_event_state(port, &epoch, &sequence);

    if (line_len >= MAX_AT_LINE_SIZE) {
        pthread_mutex_lock(&queue->mutex);
        queue->drop_count++;
        queue->pending_drop_count = queue->drop_count;
        pthread_mutex_unlock(&queue->mutex);
        return;
    }

    pthread_mutex_lock(&queue->mutex);
    if (queue->count == AT_LINE_QUEUE_CAPACITY) {
        queue->head = (queue->head + 1U) % AT_LINE_QUEUE_CAPACITY;
        queue->count--;
        queue->drop_count++;
        queue->pending_drop_count = queue->drop_count;
        queue->entries[queue->head].drop_count = queue->pending_drop_count;
        overflowed = 1;
    }
    event = &queue->entries[(queue->head + queue->count) % AT_LINE_QUEUE_CAPACITY];
    memset(event, 0, sizeof(*event));
    memcpy(event->port, port->port_path, strnlen(port->port_path, sizeof(event->port) - 1));
    event->epoch = epoch;
    event->sequence = sequence;
    event->monotonic_ms = monotonic_ms();
    memcpy(event->line, line, line_len);
    event->line[line_len] = '\0';
    event->line_len = line_len;
    event->command_id = command_id;
    event->correlation = correlation;
    event->drop_count = overflowed ? 0 : queue->pending_drop_count;
    if (!overflowed && event->drop_count != 0)
        queue->pending_drop_count = 0;
    queue->count++;
    pthread_mutex_unlock(&queue->mutex);

    notify_consumer(queue);
}

int at_line_event_dequeue(at_line_event_queue_t *queue, at_line_event_t *event)
{
    int found = 0;
    pthread_mutex_lock(&queue->mutex);
    if (queue->count > 0) {
        *event = queue->entries[queue->head];
        queue->head = (queue->head + 1U) % AT_LINE_QUEUE_CAPACITY;
        queue->count--;
        if (event->drop_count != 0 &&
            event->drop_count == queue->drop_count)
            queue->pending_drop_count = 0;
        found = 1;
    }
    pthread_mutex_unlock(&queue->mutex);
    return found;
}

size_t at_line_events_consume(at_line_event_queue_t *queue, size_t budget,
                              at_line_event_publisher_t publisher, void *opaque)
{
    at_line_event_t event;
    char pending[64];
    size_t published = 0;
    int has_remaining;

    while (read(queue->notify_pipe[0], pending, sizeof(pending)) > 0)
        ;
    while (published < budget && at_line_event_dequeue(queue, &event)) {
        publisher(&event, opaque);
        published++;
    }

    pthread_mutex_lock(&queue->mutex);
    has_remaining = queue->count > 0;
    pthread_mutex_unlock(&queue->mutex);
    if (has_remaining)
        notify_consumer(queue);

    return published;
}

#ifndef QMODEM_HOST_TEST
static void publish_line_event(const at_line_event_t *event, void *opaque)
{
    struct ubus_context *ctx = opaque;
    struct blob_buf b = {};

    blob_buf_init(&b, 0);
    blobmsg_add_string(&b, "port", event->port);
    blobmsg_add_u64(&b, "restart_epoch", event->epoch);
    blobmsg_add_u64(&b, "sequence", event->sequence);
    blobmsg_add_u64(&b, "monotonic_ms", event->monotonic_ms);
    blobmsg_add_field(&b, BLOBMSG_TYPE_STRING, "raw_line",
                      event->line, event->line_len + 1U);
    blobmsg_add_u64(&b, "command_id", event->command_id);
    blobmsg_add_string(&b, "correlation",
                       at_correlation_name(event->correlation));
    blobmsg_add_u64(&b, "drop_count", event->drop_count);
    ubus_send_event(ctx, "qmodem.at.line", b.head);
    blob_buf_free(&b);
}

static void publish_line_events(struct uloop_fd *fd, unsigned int events)
{
    at_line_event_queue_t *queue =
        container_of(fd, at_line_event_queue_t, notify_fd);
    (void)events;

    at_line_events_consume(queue, AT_LINE_EVENT_DRAIN_BUDGET,
                           publish_line_event, g_daemon_ctx.ctx);
}

int at_line_events_register_uloop(at_line_event_queue_t *queue)
{
    queue->notify_fd.fd = queue->notify_pipe[0];
    queue->notify_fd.cb = publish_line_events;
    return uloop_fd_add(&queue->notify_fd, ULOOP_READ);
}
#endif
