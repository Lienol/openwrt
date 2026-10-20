#include "ubus_at_daemon.h"

#include <assert.h>
#include <pty.h>

at_daemon_ctx_t g_daemon_ctx;
static pthread_mutex_t done_mutex = PTHREAD_MUTEX_INITIALIZER;
static int sender_done;

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

static void assert_match(at_port_instance_t *port, const char *line,
                         int expected)
{
    char matched[64] = { 0 };
    assert(check_end_flags(port, line, matched) == expected);
    if (expected)
        assert(matched[0] != '\0');
}

void process_incoming_data(at_port_instance_t *port, const char *data)
{
    (void)port;
    (void)data;
}

typedef struct {
    at_port_instance_t *port;
    at_response_t response;
    int result;
} sender_state_t;

static void *sender_worker(void *arg)
{
    sender_state_t *state = arg;
    state->result = send_at_command_with_response(state->port, "AT+SAFE", 2,
                                                   NULL, 0, &state->response);
    pthread_mutex_lock(&done_mutex);
    sender_done = 1;
    pthread_mutex_unlock(&done_mutex);
    return NULL;
}

static void *modem_worker(void *arg)
{
    int fd = *(int *)arg;
    char command[9];
    size_t used = 0;

    while (used < sizeof(command)) {
        ssize_t count = read(fd, command + used, sizeof(command) - used);
        assert(count > 0);
        used += (size_t)count;
    }
    assert(memcmp(command, "AT+SAFE\r\n", sizeof(command)) == 0);
    assert(write(fd, "BROKEN\r\n", 8) == 8);
    usleep(150000);
    pthread_mutex_lock(&done_mutex);
    assert(sender_done == 0);
    pthread_mutex_unlock(&done_mutex);
    assert(write(fd, "OK\r\n", 4) == 4);
    return NULL;
}

static void init_port(at_port_instance_t *port, int fd)
{
    memset(port, 0, sizeof(*port));
    strcpy(port->port_path, "pty-terminal");
    port->fd = fd;
    port->is_open = 1;
    port->restart_epoch = 21;
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
    sender_state_t sender_state = { 0 };
    pthread_t reader;
    pthread_t sender;
    pthread_t modem;
    at_line_event_t event;
    const char expected[] = "BROKEN\r\nOK\r\n";

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
    parse_end_flags(&port, " OK , CONNECT , +READY: ");
    assert_match(&port, "OK", 1);
    assert_match(&port, "  OK  ", 1);
    assert_match(&port, "OKAY", 0);
    assert_match(&port, "BROKEN OK", 0);
    assert_match(&port, "CONNECT 9600", 1);
    assert_match(&port, "DISCONNECT", 0);
    assert_match(&port, "+READY: 7", 1);
    assert_match(&port, "+READY:7", 0);
    assert_match(&port, "X+READY: 7", 0);
    sender_state.port = &port;
    pthread_mutex_lock(&port.state_mutex);
    assert(pthread_create(&port.reader_thread, NULL, reader_thread_func, &port) == 0);
    port.reader_thread_valid = 1;
    reader = port.reader_thread;
    pthread_mutex_unlock(&port.state_mutex);
    assert(pthread_create(&modem, NULL, modem_worker, &master_fd) == 0);
    assert(pthread_create(&sender, NULL, sender_worker, &sender_state) == 0);
    assert(pthread_join(sender, NULL) == 0);
    assert(pthread_join(modem, NULL) == 0);

    assert(sender_state.result == 0);
    assert(sender_state.response.status == 0);
    assert(strcmp(sender_state.response.end_flag_matched, "OK") == 0);
    assert(sender_state.response.response_len == (int)(sizeof(expected) - 1U));
    assert(memcmp(sender_state.response.response, expected,
                  sizeof(expected) - 1U) == 0);
    assert(at_line_event_dequeue(&g_daemon_ctx.line_events, &event) == 1);
    assert(strcmp(event.line, "BROKEN") == 0);
    assert(event.correlation == AT_CORRELATION_RESPONSE);
    assert(at_line_event_dequeue(&g_daemon_ctx.line_events, &event) == 1);
    assert(strcmp(event.line, "OK") == 0);
    assert(event.correlation == AT_CORRELATION_TERMINAL);

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
    puts("PASS delayed PTY BROKEN is response and exact OK is terminal");
    return 0;
}
