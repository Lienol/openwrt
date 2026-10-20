#include "ubus_at_daemon.h"

#include <assert.h>
#include <pty.h>

at_daemon_ctx_t g_daemon_ctx;

static pthread_mutex_t gate_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_cond = PTHREAD_COND_INITIALIZER;
static at_port_instance_t *gate_port;
static pthread_t gated_reader;
static int gate_armed;
static int reader_at_state_lock;
static int release_reader;
static int join_started;
static int self_close_seen;

int __real_pthread_mutex_lock(pthread_mutex_t *mutex);
int __real_pthread_join(pthread_t thread, void **retval);

static struct timespec deadline_after_ms(long milliseconds)
{
    struct timespec deadline;

    assert(clock_gettime(CLOCK_REALTIME, &deadline) == 0);
    deadline.tv_sec += milliseconds / 1000;
    deadline.tv_nsec += (milliseconds % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000L;
    }
    return deadline;
}

int __wrap_pthread_mutex_lock(pthread_mutex_t *mutex)
{
    assert(__real_pthread_mutex_lock(&gate_mutex) == 0);
    if (gate_armed && gate_port != NULL &&
        pthread_equal(pthread_self(), gated_reader)) {
        reader_at_state_lock = 1;
        assert(pthread_cond_broadcast(&gate_cond) == 0);
        while (!release_reader)
            assert(pthread_cond_wait(&gate_cond, &gate_mutex) == 0);
        gate_armed = 0;
    }
    assert(pthread_mutex_unlock(&gate_mutex) == 0);
    return __real_pthread_mutex_lock(mutex);
}

int __wrap_pthread_join(pthread_t thread, void **retval)
{
    assert(__real_pthread_mutex_lock(&gate_mutex) == 0);
    if (gate_port != NULL && pthread_equal(thread, gated_reader)) {
        join_started = 1;
        release_reader = 1;
        assert(pthread_cond_broadcast(&gate_cond) == 0);
    }
    assert(pthread_mutex_unlock(&gate_mutex) == 0);
    return __real_pthread_join(thread, retval);
}

void clear_event_callbacks(at_port_instance_t *port)
{
    (void)port;
}

void process_incoming_data(at_port_instance_t *port, const char *data)
{
    if (strcmp(data, "SELF_CLOSE") != 0)
        return;
    close_at_port(port);
    assert(__real_pthread_mutex_lock(&gate_mutex) == 0);
    self_close_seen = 1;
    assert(pthread_cond_broadcast(&gate_cond) == 0);
    assert(pthread_mutex_unlock(&gate_mutex) == 0);
}

static void wait_for_flag(int *flag, const char *failure)
{
    struct timespec deadline = deadline_after_ms(2000);

    assert(__real_pthread_mutex_lock(&gate_mutex) == 0);
    while (!*flag) {
        int result = pthread_cond_timedwait(&gate_cond, &gate_mutex, &deadline);
        if (result == ETIMEDOUT) {
            fprintf(stderr, "TIMEOUT: %s\n", failure);
            assert(result != ETIMEDOUT);
        }
        assert(result == 0);
    }
    assert(pthread_mutex_unlock(&gate_mutex) == 0);
}

static void wait_for_open_state(at_port_instance_t *port, int expected_open,
                                const char *failure)
{
    struct timespec deadline = deadline_after_ms(2000);

    for (;;) {
        int is_open;

        assert(__real_pthread_mutex_lock(&port->state_mutex) == 0);
        is_open = port->is_open;
        assert(pthread_mutex_unlock(&port->state_mutex) == 0);
        if (is_open == expected_open)
            return;
        {
            struct timespec now;
            assert(clock_gettime(CLOCK_REALTIME, &now) == 0);
            if (now.tv_sec > deadline.tv_sec ||
                (now.tv_sec == deadline.tv_sec && now.tv_nsec >= deadline.tv_nsec)) {
                fprintf(stderr, "TIMEOUT: %s\n", failure);
                assert(0);
            }
        }
        usleep(1000);
    }
}

static void *close_worker(void *arg)
{
    close_at_port(arg);
    return NULL;
}

static void *open_worker(void *arg)
{
    at_port_instance_t *port = arg;
    intptr_t result = open_at_port(port, 115200, 8, 0, 1);
    return (void *)(intptr_t)result;
}

static void timed_join(pthread_t thread, void **retval, const char *failure)
{
    struct timespec deadline = deadline_after_ms(2000);
    int result = pthread_timedjoin_np(thread, retval, &deadline);

    if (result == ETIMEDOUT)
        fprintf(stderr, "TIMEOUT: %s\n", failure);
    assert(result == 0);
}

static at_port_instance_t *create_open_port(const char *path)
{
    at_port_instance_t *port = create_port_instance(path);

    assert(port != NULL);
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    return port;
}

static void prove_join_does_not_hold_reader_state_lock(const char *path)
{
    at_port_instance_t *port = create_open_port(path);
    pthread_t closer;

    assert(__real_pthread_mutex_lock(&gate_mutex) == 0);
    gate_port = port;
    gated_reader = port->reader_thread;
    gate_armed = 1;
    reader_at_state_lock = 0;
    release_reader = 0;
    join_started = 0;
    assert(pthread_mutex_unlock(&gate_mutex) == 0);

    wait_for_flag(&reader_at_state_lock,
                  "production reader did not reach its state lock barrier");
    assert(pthread_create(&closer, NULL, close_worker, port) == 0);
    wait_for_flag(&join_started, "close did not reach reader join");
    timed_join(closer, NULL,
               "close joined a production reader while holding its state lock");
    wait_for_open_state(port, 0, "close did not publish closed state");
    assert(__real_pthread_mutex_lock(&gate_mutex) == 0);
    gate_port = NULL;
    assert(pthread_mutex_unlock(&gate_mutex) == 0);
    destroy_port_instance(port);
}

static void force_reader_error(at_port_instance_t *port)
{
    int fd;

    assert(__real_pthread_mutex_lock(&port->state_mutex) == 0);
    fd = port->fd;
    assert(fd >= 0);
    assert(close(fd) == 0);
    assert(pthread_mutex_unlock(&port->state_mutex) == 0);
    wait_for_open_state(port, 0, "production reader did not publish fatal read exit");
}

static void prove_error_exit_reopen_and_monitor(const char *path)
{
    at_port_instance_t *port = create_open_port(path);

    force_reader_error(port);
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    force_reader_error(port);
    port->last_check_time = 0;
    port->check_interval = 0;
    check_and_reconnect_port(port);
    wait_for_open_state(port, 1, "monitor reconnect did not reopen the port");
    destroy_port_instance(port);
}

static void prove_serialized_concurrent_close_open(const char *path)
{
    at_port_instance_t *port = create_open_port(path);
    pthread_t closer;
    pthread_t opener;
    void *open_result;

    assert(pthread_create(&closer, NULL, close_worker, port) == 0);
    assert(pthread_create(&opener, NULL, open_worker, port) == 0);
    timed_join(closer, NULL, "concurrent close did not complete");
    timed_join(opener, &open_result, "concurrent open did not complete");
    assert((intptr_t)open_result == 0);
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    close_at_port(port);
    close_at_port(port);
    destroy_port_instance(port);
}

static void prove_reader_self_close_then_reopen(int master_fd, const char *path)
{
    static const char self_close_line[] = "SELF_CLOSE\r\n";
    at_port_instance_t *port = create_open_port(path);

    self_close_seen = 0;
    assert(write(master_fd, self_close_line, sizeof(self_close_line) - 1) ==
           (ssize_t)(sizeof(self_close_line) - 1));
    wait_for_flag(&self_close_seen, "reader did not complete self-close");
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    destroy_port_instance(port);
}

int main(void)
{
    int master_fd;
    int slave_fd;
    char slave_name[128];

    assert(openpty(&master_fd, &slave_fd, slave_name, NULL, NULL) == 0);
    assert(pthread_mutex_init(&g_daemon_ctx.ports_mutex, NULL) == 0);
    assert(at_line_events_init(&g_daemon_ctx.line_events) == 0);
    g_daemon_ctx.daemon_epoch = 5000;

    prove_join_does_not_hold_reader_state_lock(slave_name);
    prove_error_exit_reopen_and_monitor(slave_name);
    prove_serialized_concurrent_close_open(slave_name);
    prove_reader_self_close_then_reopen(master_fd, slave_name);

    at_line_events_cleanup(&g_daemon_ctx.line_events);
    assert(pthread_mutex_destroy(&g_daemon_ctx.ports_mutex) == 0);
    assert(close(slave_fd) == 0);
    assert(close(master_fd) == 0);
    printf("PASS production reader bounded close/reopen lifecycle matrix\n");
    return 0;
}
