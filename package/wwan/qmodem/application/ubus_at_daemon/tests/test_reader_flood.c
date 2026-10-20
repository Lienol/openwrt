#include "ubus_at_daemon.h"

#include <assert.h>
#include <pty.h>

at_daemon_ctx_t g_daemon_ctx;

int open_at_port(at_port_instance_t *port, int baudrate, int databits,
                 int parity, int stopbits)
{
    (void)port;
    (void)baudrate;
    (void)databits;
    (void)parity;
    (void)stopbits;
    return -1;
}

void process_incoming_data(at_port_instance_t *port, const char *data)
{
    (void)port;
    (void)data;
}

static void init_port(at_port_instance_t *port, int fd)
{
    memset(port, 0, sizeof(*port));
    strcpy(port->port_path, "pty-flood");
    port->fd = fd;
    port->is_open = 1;
    port->restart_epoch = 17;
    assert(pthread_mutex_init(&port->event_state_mutex, NULL) == 0);
    assert(pthread_mutex_init(&port->lifecycle_mutex, NULL) == 0);
    assert(pthread_mutex_init(&port->state_mutex, NULL) == 0);
    assert(pthread_mutex_init(&port->queue_mutex, NULL) == 0);
    assert(pthread_mutex_init(&port->write_mutex, NULL) == 0);
    assert(pthread_mutex_init(&port->response_mutex, NULL) == 0);
    assert(pthread_cond_init(&port->response_cond, NULL) == 0);
    assert(at_line_events_init(&g_daemon_ctx.line_events) == 0);
}

int main(void)
{
    int master_fd;
    int slave_fd;
    at_port_instance_t port;
    at_line_event_t event;
    pthread_t reader;

    assert(openpty(&master_fd, &slave_fd, NULL, NULL, NULL) == 0);
    assert(fcntl(slave_fd, F_SETFL,
                 fcntl(slave_fd, F_GETFL) | O_NONBLOCK) == 0);
    {
        struct termios options;
        assert(tcgetattr(slave_fd, &options) == 0);
        cfmakeraw(&options);
        assert(tcsetattr(slave_fd, TCSANOW, &options) == 0);
    }
    init_port(&port, slave_fd);
    pthread_mutex_lock(&port.state_mutex);
    assert(pthread_create(&port.reader_thread, NULL, reader_thread_func, &port) == 0);
    port.reader_thread_valid = 1;
    reader = port.reader_thread;
    pthread_mutex_unlock(&port.state_mutex);

    for (unsigned int i = 0; i < 300; i++) {
        char line[32];
        int length = snprintf(line, sizeof(line), "FLOOD-%03u\r\n", i);
        assert(length > 0);
        assert(write(master_fd, line, (size_t)length) == length);
    }

    for (unsigned int attempt = 0; attempt < 500; attempt++) {
        uint64_t drops;
        size_t count;
        pthread_mutex_lock(&g_daemon_ctx.line_events.mutex);
        drops = g_daemon_ctx.line_events.drop_count;
        count = g_daemon_ctx.line_events.count;
        pthread_mutex_unlock(&g_daemon_ctx.line_events.mutex);
        if (drops == 44 && count == AT_LINE_QUEUE_CAPACITY)
            break;
        usleep(10000);
    }

    pthread_mutex_lock(&g_daemon_ctx.line_events.mutex);
    assert(g_daemon_ctx.line_events.count == AT_LINE_QUEUE_CAPACITY);
    assert(g_daemon_ctx.line_events.drop_count == 44);
    pthread_mutex_unlock(&g_daemon_ctx.line_events.mutex);

    for (unsigned int i = 44; i < 300; i++) {
        char expected[32];
        assert(at_line_event_dequeue(&g_daemon_ctx.line_events, &event) == 1);
        snprintf(expected, sizeof(expected), "FLOOD-%03u", i);
        assert(strcmp(event.line, expected) == 0);
        assert(event.sequence == i + 1U);
        assert(event.epoch == 17);
        assert(event.correlation == AT_CORRELATION_IDLE);
        if (i == 44)
            assert(event.drop_count == 44);
        else
            assert(event.drop_count == 0);
    }
    assert(event.drop_count == 0);
    assert(at_line_event_dequeue(&g_daemon_ctx.line_events, &event) == 0);

    pthread_mutex_lock(&port.state_mutex);
    port.should_stop = 1;
    pthread_mutex_unlock(&port.state_mutex);
    assert(pthread_join(reader, NULL) == 0);
    at_line_events_cleanup(&g_daemon_ctx.line_events);
    pthread_cond_destroy(&port.response_cond);
    pthread_mutex_destroy(&port.response_mutex);
    pthread_mutex_destroy(&port.write_mutex);
    pthread_mutex_destroy(&port.queue_mutex);
    pthread_mutex_destroy(&port.event_state_mutex);
    pthread_mutex_destroy(&port.state_mutex);
    pthread_mutex_destroy(&port.lifecycle_mutex);
    close(slave_fd);
    close(master_fd);
    puts("PASS real PTY reader flood retained ordered 256 events with gap/drop snapshots");
    return 0;
}
