#include "ubus_at_daemon.h"

#include <assert.h>

#define ITERATIONS 20000U

at_daemon_ctx_t g_daemon_ctx;
static pthread_barrier_t start_barrier;

static void wait_at_barrier(void)
{
    int result = pthread_barrier_wait(&start_barrier);
    assert(result == 0 || result == PTHREAD_BARRIER_SERIAL_THREAD);
}

void *reader_thread_func(void *arg)
{
    (void)arg;
    return NULL;
}

void clear_event_callbacks(at_port_instance_t *port)
{
    (void)port;
}

static void *lifecycle_worker(void *arg)
{
    at_port_instance_t *port = arg;
    wait_at_barrier();
    for (unsigned int i = 0; i < ITERATIONS; i++)
        at_port_advance_restart_epoch(port);
    return NULL;
}

static void *reader_worker(void *arg)
{
    at_port_instance_t *port = arg;
    wait_at_barrier();
    for (unsigned int i = 0; i < ITERATIONS; i++)
        at_line_event_enqueue(&g_daemon_ctx.line_events, port, "RING", 4, 0,
                              AT_CORRELATION_IDLE);
    return NULL;
}

static void *status_worker(void *arg)
{
    at_port_instance_t *port = arg;
    uint64_t prior_epoch = 0;
    uint64_t prior_sequence = 0;

    wait_at_barrier();
    for (unsigned int i = 0; i < ITERATIONS; i++) {
        uint64_t epoch;
        uint64_t sequence;
        at_port_event_state_snapshot(port, &epoch, &sequence);
        assert(epoch >= prior_epoch);
        assert(sequence >= prior_sequence);
        prior_epoch = epoch;
        prior_sequence = sequence;
    }
    return NULL;
}

int main(void)
{
    at_port_instance_t *port;
    pthread_t lifecycle;
    pthread_t reader;
    pthread_t status;
    uint64_t epoch;
    uint64_t sequence;

    assert(pthread_mutex_init(&g_daemon_ctx.ports_mutex, NULL) == 0);
    assert(at_line_events_init(&g_daemon_ctx.line_events) == 0);
    g_daemon_ctx.daemon_epoch = 1234;
    port = create_port_instance("concurrency-test");
    assert(port != NULL);
    assert(pthread_barrier_init(&start_barrier, NULL, 3) == 0);
    assert(pthread_create(&lifecycle, NULL, lifecycle_worker, port) == 0);
    assert(pthread_create(&reader, NULL, reader_worker, port) == 0);
    assert(pthread_create(&status, NULL, status_worker, port) == 0);
    assert(pthread_join(lifecycle, NULL) == 0);
    assert(pthread_join(reader, NULL) == 0);
    assert(pthread_join(status, NULL) == 0);

    at_port_event_state_snapshot(port, &epoch, &sequence);
    assert(epoch == 1234U + ITERATIONS);
    assert(sequence == ITERATIONS);
    assert(g_daemon_ctx.line_events.count == AT_LINE_QUEUE_CAPACITY);
    assert(g_daemon_ctx.line_events.drop_count ==
           ITERATIONS - AT_LINE_QUEUE_CAPACITY);

    pthread_barrier_destroy(&start_barrier);
    destroy_port_instance(port);
    at_line_events_cleanup(&g_daemon_ctx.line_events);
    pthread_mutex_destroy(&g_daemon_ctx.ports_mutex);
    puts("PASS barrier lifecycle/reader/status stress uses coherent event state snapshots");
    return 0;
}
