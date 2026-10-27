#include "ubus_at_daemon.h"

#include <assert.h>
#include <poll.h>

typedef struct {
    at_line_event_queue_t *queue;
    at_port_instance_t *port;
    size_t published;
    size_t inject_remaining;
} publisher_state_t;

static void continuous_publisher(const at_line_event_t *event, void *opaque)
{
    publisher_state_t *state = opaque;
    assert(event->line_len > 0);
    state->published++;
    if (state->inject_remaining > 0) {
        state->inject_remaining--;
        at_line_event_enqueue(state->queue, state->port, "CONT", 4, 0,
                              AT_CORRELATION_IDLE);
    }
}

int main(void)
{
    at_line_event_queue_t queue;
    at_port_instance_t port = { 0 };
    at_line_event_t event;
    char oversized[MAX_AT_LINE_SIZE];

    strcpy(port.port_path, "/dev/ttyTEST0");
    port.restart_epoch = 7;
    assert(pthread_mutex_init(&port.event_state_mutex, NULL) == 0);
    assert(at_line_events_init(&queue) == 0);
    for (unsigned int i = 0; i < 300; i++) {
        char line[32];
        int length = snprintf(line, sizeof(line), "+TEST: %u", i);
        assert(length > 0);
        at_line_event_enqueue(&queue, &port, line, (size_t)length, 0,
                              AT_CORRELATION_IDLE);
    }
    assert(queue.count == AT_LINE_QUEUE_CAPACITY);
    assert(queue.drop_count == 44);
    assert(at_line_event_dequeue(&queue, &event) == 1);
    assert(event.sequence == 45);
    assert(event.drop_count == 44);
    for (unsigned int sequence = 46; sequence <= 300; sequence++) {
        assert(at_line_event_dequeue(&queue, &event) == 1);
        assert(event.sequence == sequence);
        assert(event.drop_count == 0);
    }
    assert(event.drop_count == 0);
    assert(at_line_event_dequeue(&queue, &event) == 0);

    memset(oversized, 'X', sizeof(oversized));
    at_line_event_enqueue(&queue, &port, oversized, sizeof(oversized), 0,
                          AT_CORRELATION_IDLE);
    assert(queue.count == 0);
    assert(queue.drop_count == 45);
    {
        uint64_t epoch;
        uint64_t sequence;
        at_port_event_state_snapshot(&port, &epoch, &sequence);
        assert(epoch == 7);
        assert(sequence == 301);
    }

    at_port_advance_restart_epoch(&port);
    at_line_event_enqueue(&queue, &port, "RING", 4, 0,
                          AT_CORRELATION_IDLE);
    assert(at_line_event_dequeue(&queue, &event) == 1);
    assert(event.epoch == 8);
    assert(event.sequence == 302);
    assert(event.drop_count == 45);
    assert(event.monotonic_ms > 0);
    assert(strcmp(at_correlation_name(AT_CORRELATION_AMBIGUOUS),
                  "ambiguous") == 0);

    {
        publisher_state_t state = {
            .queue = &queue,
            .port = &port,
            .inject_remaining = 32,
        };
        struct pollfd pfd = { .fd = queue.notify_pipe[0], .events = POLLIN };

        for (unsigned int i = 0; i < 8; i++)
            at_line_event_enqueue(&queue, &port, "SEED", 4, 0,
                                  AT_CORRELATION_IDLE);
        assert(at_line_events_consume(&queue, 4, continuous_publisher,
                                      &state) == 4);
        assert(state.published == 4);
        assert(queue.count == 8);
        assert(poll(&pfd, 1, 0) == 1);
        assert((pfd.revents & POLLIN) != 0);

        state.inject_remaining = 0;
        while (queue.count > 0)
            assert(at_line_events_consume(&queue, 4, continuous_publisher,
                                          &state) <= 4);
        assert(state.published == 12);
    }

    at_line_events_cleanup(&queue);
    pthread_mutex_destroy(&port.event_state_mutex);
    puts("PASS overflow/drop oversized line and bounded production drain rearm");
    return 0;
}
