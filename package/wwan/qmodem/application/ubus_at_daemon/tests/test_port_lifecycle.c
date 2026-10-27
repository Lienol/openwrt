#include "ubus_at_daemon.h"

#include <assert.h>
#include <pty.h>

at_daemon_ctx_t g_daemon_ctx;

void *reader_thread_func(void *arg)
{
    at_port_instance_t *port = arg;
    for (;;) {
        int fd;
        int should_stop;

        pthread_mutex_lock(&port->state_mutex);
        fd = port->fd;
        should_stop = port->should_stop;
        if (fd == -2)
            port->is_open = 0;
        pthread_mutex_unlock(&port->state_mutex);
        if (should_stop || fd == -2)
            return NULL;
        usleep(1000);
    }
}

void clear_event_callbacks(at_port_instance_t *port)
{
    (void)port;
}

static at_port_instance_t *create_and_open(const char *path,
                                           uint64_t daemon_epoch)
{
    at_port_instance_t *port;
    uint64_t epoch;
    uint64_t sequence;

    g_daemon_ctx.daemon_epoch = daemon_epoch;
    port = create_port_instance(path);
    assert(port != NULL);
    at_port_event_state_snapshot(port, &epoch, &sequence);
    assert(epoch == daemon_epoch);
    assert(sequence == 0);
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    at_port_event_state_snapshot(port, &epoch, &sequence);
    assert(epoch == daemon_epoch + 1U);
    return port;
}

int main(void)
{
    int master_fd;
    int slave_fd;
    char slave_name[128];
    at_port_instance_t *port;
    uint64_t first_open_epoch;
    uint64_t reopened_epoch;
    uint64_t second_daemon_epoch = 9000;
    uint64_t second_open_epoch;
    uint64_t sequence;
    pthread_t first_reader;

    assert(openpty(&master_fd, &slave_fd, slave_name, NULL, NULL) == 0);
    assert(pthread_mutex_init(&g_daemon_ctx.ports_mutex, NULL) == 0);

    port = create_and_open(slave_name, 4000);
    at_port_event_state_snapshot(port, &first_open_epoch, &sequence);
    first_reader = port->reader_thread;
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    at_port_event_state_snapshot(port, &reopened_epoch, &sequence);
    assert(reopened_epoch == first_open_epoch);
    assert(pthread_equal(port->reader_thread, first_reader));
    close_at_port(port);
    pthread_mutex_lock(&port->state_mutex);
    assert(!port->is_open);
    pthread_mutex_unlock(&port->state_mutex);
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    at_port_event_state_snapshot(port, &reopened_epoch, &sequence);
    assert(reopened_epoch == first_open_epoch + 1U);
    destroy_port_instance(port);

    port = create_and_open(slave_name, 7000);
    pthread_mutex_lock(&port->state_mutex);
    port->fd = -2;
    pthread_mutex_unlock(&port->state_mutex);
    usleep(10000);
    assert(open_at_port(port, 115200, 8, 0, 1) == 0);
    pthread_mutex_lock(&port->state_mutex);
    assert(port->reader_thread_valid == 1);
    pthread_mutex_unlock(&port->state_mutex);
    close_at_port(port);
    close_at_port(port);
    destroy_port_instance(port);

    port = create_and_open(slave_name, second_daemon_epoch);
    at_port_event_state_snapshot(port, &second_open_epoch, &sequence);
    assert(second_open_epoch != first_open_epoch);
    assert(second_open_epoch != reopened_epoch);
    destroy_port_instance(port);

    pthread_mutex_destroy(&g_daemon_ctx.ports_mutex);
    close(slave_fd);
    close(master_fd);
    printf("PASS real PTY epochs first=%llu reopen=%llu daemon2=%llu\n",
           (unsigned long long)first_open_epoch,
           (unsigned long long)reopened_epoch,
           (unsigned long long)second_open_epoch);
    return 0;
}
