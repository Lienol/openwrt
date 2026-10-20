#include "ubus_at_daemon.h"

#include <assert.h>
#include <pty.h>

at_daemon_ctx_t g_daemon_ctx;
static pthread_t reader_identity;
static int callback_count;
static pthread_mutex_t callback_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t callback_cond = PTHREAD_COND_INITIALIZER;

int open_at_port(at_port_instance_t *port, int baudrate, int databits,
                 int parity, int stopbits)
{
    (void)port; (void)baudrate; (void)databits; (void)parity; (void)stopbits;
    return -1;
}

void process_incoming_data(at_port_instance_t *port, const char *data)
{
    assert(pthread_equal(pthread_self(), reader_identity));
    assert(pthread_mutex_trylock(&port->queue_mutex) == 0);
    pthread_mutex_unlock(&port->queue_mutex);
    assert(data[0] != '\0');
    pthread_mutex_lock(&g_daemon_ctx.line_events.mutex);
    assert(g_daemon_ctx.line_events.count > 0);
    pthread_mutex_unlock(&g_daemon_ctx.line_events.mutex);
    pthread_mutex_lock(&callback_mutex);
    callback_count++;
    pthread_cond_signal(&callback_cond);
    pthread_mutex_unlock(&callback_mutex);
}

static void init_port(at_port_instance_t *port, int fd)
{
    memset(port, 0, sizeof(*port));
    strcpy(port->port_path, "pty-baseline");
    port->fd = fd;
    port->is_open = 1;
    port->restart_epoch = 1;
    pthread_mutex_init(&port->event_state_mutex, NULL);
    pthread_mutex_init(&port->lifecycle_mutex, NULL);
    pthread_mutex_init(&port->state_mutex, NULL);
    pthread_mutex_init(&port->queue_mutex, NULL);
    pthread_mutex_init(&port->write_mutex, NULL);
    pthread_mutex_init(&port->response_mutex, NULL);
    pthread_cond_init(&port->response_cond, NULL);
    assert(at_line_events_init(&g_daemon_ctx.line_events) == 0);
}

static void *modem_peer(void *arg)
{
    int fd = *(int *)arg;
    char command[32];
    size_t used = 0;
    const char response[] = "AT+CSQ\r\n\r\n+CSQ: 19,99\r\nRING\r\n"
                            "+CLIP: \"123\",129\r\nOK\r\n";
    const size_t chunks[] = { 7, 1, 13, 2, 9, 5 };
    size_t sent = 0;
    while (used < 8) {
        ssize_t n = read(fd, command + used, 8 - used);
        assert(n > 0);
        used += (size_t)n;
    }
    assert(memcmp(command, "AT+CSQ\r\n", 8) == 0);
    for (size_t i = 0; i < sizeof(chunks) / sizeof(chunks[0]); i++) {
        assert(write(fd, response + sent, chunks[i]) == (ssize_t)chunks[i]);
        sent += chunks[i];
        usleep(2000);
    }
    assert(write(fd, response + sent, sizeof(response) - 1U - sent) ==
           (ssize_t)(sizeof(response) - 1U - sent));
    return NULL;
}

int main(void)
{
    int master_fd, slave_fd;
    at_port_instance_t port;
    at_response_t response;
    pthread_t reader, peer;
    const char expected[] = "AT+CSQ\r\n\r\n+CSQ: 19,99\r\nRING\r\n"
                            "+CLIP: \"123\",129\r\nOK\r\n";
    const char *event_lines[] = { "+CSQ: 19,99", "RING",
                                  "+CLIP: \"123\",129", "OK" };
    const at_correlation_t correlations[] = {
        AT_CORRELATION_RESPONSE, AT_CORRELATION_AMBIGUOUS,
        AT_CORRELATION_AMBIGUOUS, AT_CORRELATION_TERMINAL
    };

    assert(openpty(&master_fd, &slave_fd, NULL, NULL, NULL) == 0);
    assert(fcntl(slave_fd, F_SETFL, fcntl(slave_fd, F_GETFL) | O_NONBLOCK) == 0);
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
    reader_identity = reader;
    pthread_mutex_unlock(&port.state_mutex);
    assert(pthread_create(&peer, NULL, modem_peer, &master_fd) == 0);
    assert(send_at_command_with_response(&port, "AT+CSQ", 2, NULL, 0,
                                         &response) == 0);
    assert(response.response_len == (int)(sizeof(expected) - 1));
    assert(memcmp(response.response, expected, sizeof(expected) - 1) == 0);
    assert(strcmp(response.end_flag_matched, "OK") == 0);
    assert(response.status == 0);

    for (size_t i = 0; i < 4; i++) {
        at_line_event_t event;
        assert(at_line_event_dequeue(&g_daemon_ctx.line_events, &event) == 1);
        assert(strcmp(event.line, event_lines[i]) == 0);
        assert(event.line_len == strlen(event_lines[i]));
        assert(event.epoch == 1);
        assert(event.sequence == i + 1U);
        assert(event.command_id == 1);
        assert(event.correlation == correlations[i]);
        assert(event.drop_count == 0);
    }
    {
        struct timespec deadline;
        clock_gettime(CLOCK_REALTIME, &deadline);
        deadline.tv_sec++;
        pthread_mutex_lock(&callback_mutex);
        while (callback_count < 4)
            assert(pthread_cond_timedwait(&callback_cond, &callback_mutex,
                                          &deadline) == 0);
        pthread_mutex_unlock(&callback_mutex);
    }

    assert(send_at_command_with_response(&port, "AT+HANG", 1, NULL, 0,
                                         &response) == -1);
    assert(response.status == -1);
    assert(port.waiting_for_response == 0);
    assert(port.active_command_id == 0);

    pthread_join(peer, NULL);
    pthread_mutex_lock(&port.state_mutex);
    port.should_stop = 1;
    pthread_mutex_unlock(&port.state_mutex);
    pthread_join(reader, NULL);
    close(master_fd);
    close(slave_fd);
    at_line_events_cleanup(&g_daemon_ctx.line_events);
    pthread_mutex_destroy(&port.event_state_mutex);
    pthread_mutex_destroy(&port.state_mutex);
    pthread_mutex_destroy(&port.lifecycle_mutex);
    puts("PASS byte-identical partial PTY response and ordered interleaved events");
    return 0;
}
