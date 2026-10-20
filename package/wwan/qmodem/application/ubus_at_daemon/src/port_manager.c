#include "ubus_at_daemon.h"

extern at_daemon_ctx_t g_daemon_ctx;

at_port_instance_t *find_port_instance(const char *port_path) {
    pthread_mutex_lock(&g_daemon_ctx.ports_mutex);
    
    at_port_instance_t *current = g_daemon_ctx.ports;
    while (current) {
        if (strcmp(current->port_path, port_path) == 0) {
            pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
            return current;
        }
        current = current->next;
    }
    
    pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
    return NULL;
}

at_port_instance_t *create_port_instance(const char *port_path) {
    at_port_instance_t *port = calloc(1, sizeof(at_port_instance_t));
    if (!port) {
        return NULL;
    }
    
    strncpy(port->port_path, port_path, MAX_PORT_PATH_SIZE - 1);
    port->fd = -1;
    port->is_open = 0;
    port->should_stop = 0;
    port->buffer_pos = 0;
    port->queue_head = NULL;
    port->queue_tail = NULL;
    port->callbacks = NULL;
    
    // Initialize configuration fields
    port->configured_baudrate = 0;
    port->configured_databits = 0;
    port->configured_parity = 0;
    port->configured_stopbits = 0;
    
    // Initialize monitoring fields
    port->last_check_time = time(NULL);
    port->check_interval = DEFAULT_CHECK_INTERVAL;
    
    pthread_mutex_init(&port->event_state_mutex, NULL);
    pthread_mutex_init(&port->lifecycle_mutex, NULL);
    pthread_mutex_init(&port->state_mutex, NULL);

    // Initialize response handling
    memset(&port->current_response, 0, sizeof(at_response_t));
    port->waiting_for_response = 0;
    port->num_end_flags = 0;
    port->restart_epoch = g_daemon_ctx.daemon_epoch;
    port->line_sequence = 0;
    port->next_command_id = 0;
    port->active_command_id = 0;
    
    pthread_mutex_init(&port->queue_mutex, NULL);
    pthread_mutex_init(&port->write_mutex, NULL);
    pthread_mutex_init(&port->response_mutex, NULL);
    pthread_cond_init(&port->queue_cond, NULL);
    pthread_cond_init(&port->response_cond, NULL);
    
    // Add to global ports list
    pthread_mutex_lock(&g_daemon_ctx.ports_mutex);
    port->next = g_daemon_ctx.ports;
    g_daemon_ctx.ports = port;
    pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
    
    return port;
}

void destroy_port_instance(at_port_instance_t *port) {
    if (!port) return;

    // Close the port
    close_at_port(port);
    
    // Clean up queue
    pthread_mutex_lock(&port->queue_mutex);
    at_queue_item_t *current = port->queue_head;
    while (current) {
        at_queue_item_t *next = current->next;
        free(current);
        current = next;
    }
    pthread_mutex_unlock(&port->queue_mutex);
    
    // Clean up callbacks
    clear_event_callbacks(port);
    
    // Destroy mutexes
    pthread_mutex_destroy(&port->queue_mutex);
    pthread_mutex_destroy(&port->write_mutex);
    pthread_mutex_destroy(&port->response_mutex);
    pthread_mutex_destroy(&port->event_state_mutex);
    pthread_mutex_destroy(&port->state_mutex);
    pthread_mutex_destroy(&port->lifecycle_mutex);
    pthread_cond_destroy(&port->queue_cond);
    pthread_cond_destroy(&port->response_cond);
    
    // Remove from global list
    pthread_mutex_lock(&g_daemon_ctx.ports_mutex);
    if (g_daemon_ctx.ports == port) {
        g_daemon_ctx.ports = port->next;
    } else {
        at_port_instance_t *prev = g_daemon_ctx.ports;
        while (prev && prev->next != port) {
            prev = prev->next;
        }
        if (prev) {
            prev->next = port->next;
        }
    }
    pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
    
    free(port);
}

static int stop_reader(at_port_instance_t *port)
{
    pthread_t reader_thread;
    int join_reader = 0;
    int reader_is_self = 0;

    pthread_mutex_lock(&port->state_mutex);
    if (port->reader_thread_valid) {
        port->should_stop = 1;
        reader_is_self = pthread_equal(pthread_self(), port->reader_thread);
        if (!reader_is_self) {
            reader_thread = port->reader_thread;
            port->reader_thread_valid = 0;
            memset(&port->reader_thread, 0, sizeof(port->reader_thread));
            join_reader = 1;
        }
    }
    pthread_mutex_unlock(&port->state_mutex);

    if (join_reader)
        pthread_join(reader_thread, NULL);

    return reader_is_self;
}

static void mark_port_closed(at_port_instance_t *port)
{
    pthread_mutex_lock(&port->state_mutex);
    if (port->fd >= 0)
        close(port->fd);
    port->fd = -1;
    port->is_open = 0;
    pthread_mutex_unlock(&port->state_mutex);
}

int open_at_port(at_port_instance_t *port, int baudrate, int databits, int parity, int stopbits) {
    int fd;
    int already_open;

    pthread_mutex_lock(&port->lifecycle_mutex);
    pthread_mutex_lock(&port->state_mutex);
    already_open = port->is_open && port->fd >= 0 &&
                   port->reader_thread_valid &&
                   port->configured_baudrate == baudrate &&
                   port->configured_databits == databits &&
                   port->configured_parity == parity &&
                   port->configured_stopbits == stopbits &&
                   fcntl(port->fd, F_GETFL) != -1;
    pthread_mutex_unlock(&port->state_mutex);
    if (already_open) {
        pthread_mutex_unlock(&port->lifecycle_mutex);
        return 0;
    }
    if (stop_reader(port)) {
        pthread_mutex_unlock(&port->lifecycle_mutex);
        return -1;
    }
    mark_port_closed(port);

    // Check if file exists before trying to open
    if (access(port->port_path, F_OK) != 0) {
        fprintf(stderr, "Port file %s does not exist\n", port->port_path);
        pthread_mutex_unlock(&port->lifecycle_mutex);
        return -1;
    }
    
    fd = open(port->port_path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        fprintf(stderr, "Failed to open %s: %s\n", port->port_path, strerror(errno));
        pthread_mutex_unlock(&port->lifecycle_mutex);
        return -1;
    }
    
    // Configure terminal settings
    struct termios options;
    tcgetattr(fd, &options);
    
    // Set baud rate
    speed_t speed;
    switch (baudrate) {
        case 9600: speed = B9600; break;
        case 19200: speed = B19200; break;
        case 38400: speed = B38400; break;
        case 57600: speed = B57600; break;
        case 115200: speed = B115200; break;
        case 230400: speed = B230400; break;
        case 460800: speed = B460800; break;
        case 921600: speed = B921600; break;
        default: speed = DEFAULT_BAUDRATE; break;
    }
    cfsetispeed(&options, speed);
    cfsetospeed(&options, speed);
    
    // Configure data bits
    options.c_cflag &= ~CSIZE;
    switch (databits) {
        case 5: options.c_cflag |= CS5; break;
        case 6: options.c_cflag |= CS6; break;
        case 7: options.c_cflag |= CS7; break;
        case 8: options.c_cflag |= CS8; break;
        default: options.c_cflag |= CS8; break;
    }
    
    // Configure parity
    if (parity == 1) { // odd
        options.c_cflag |= PARENB | PARODD;
    } else if (parity == 2) { // even
        options.c_cflag |= PARENB;
        options.c_cflag &= ~PARODD;
    } else { // none
        options.c_cflag &= ~PARENB;
    }
    
    // Configure stop bits
    if (stopbits == 2) {
        options.c_cflag |= CSTOPB;
    } else {
        options.c_cflag &= ~CSTOPB;
    }
    
    // Other settings
    options.c_cflag |= CLOCAL | CREAD;
    options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    options.c_iflag &= ~(IXON | IXOFF | IXANY | ICRNL);
    options.c_oflag &= ~OPOST;
    
    options.c_cc[VMIN] = 0;
    options.c_cc[VTIME] = 1;
    
    tcsetattr(fd, TCSANOW, &options);
    at_port_advance_restart_epoch(port);
    port->buffer_pos = 0;

    pthread_mutex_lock(&port->state_mutex);
    port->termios_config = options;
    port->configured_baudrate = baudrate;
    port->configured_databits = databits;
    port->configured_parity = parity;
    port->configured_stopbits = stopbits;
    port->fd = fd;
    port->is_open = 1;
    port->should_stop = 0;

    // Start reader thread
    if (pthread_create(&port->reader_thread, NULL, reader_thread_func, port) != 0) {
        fprintf(stderr, "Failed to create reader thread for %s\n", port->port_path);
        close(fd);
        port->fd = -1;
        port->is_open = 0;
        port->should_stop = 1;
        pthread_mutex_unlock(&port->state_mutex);
        pthread_mutex_unlock(&port->lifecycle_mutex);
        return -1;
    }
    port->reader_thread_valid = 1;
    pthread_mutex_unlock(&port->state_mutex);
    pthread_mutex_unlock(&port->lifecycle_mutex);
    
    return 0;
}

void close_at_port(at_port_instance_t *port) {
    if (!port) return;
    pthread_mutex_lock(&port->lifecycle_mutex);
    stop_reader(port);
    mark_port_closed(port);
    pthread_mutex_unlock(&port->lifecycle_mutex);
}

// Port monitoring functions
void check_and_reconnect_port(at_port_instance_t *port) {
    time_t current_time = time(NULL);
    
    // Check if it's time to check this port
    if (current_time - port->last_check_time < port->check_interval) {
        return;
    }
    
    port->last_check_time = current_time;
    
    int is_open;
    int fd;
    int bad_fd = 0;
    int baudrate;
    int databits;
    int parity;
    int stopbits;

    pthread_mutex_lock(&port->state_mutex);
    is_open = port->is_open;
    fd = port->fd;
    baudrate = (port->configured_baudrate > 0) ? port->configured_baudrate : 115200;
    databits = (port->configured_databits > 0) ? port->configured_databits : DEFAULT_DATABITS;
    parity = port->configured_parity;
    stopbits = (port->configured_stopbits > 0) ? port->configured_stopbits : DEFAULT_STOPBITS;
    if (is_open && fd >= 0) {
        int test_result = fcntl(fd, F_GETFL);
        bad_fd = test_result == -1 && errno == EBADF;
    }
    pthread_mutex_unlock(&port->state_mutex);

    if (!is_open) {
        // Port is marked as closed, check if file exists and try to reopen
        if (access(port->port_path, F_OK) == 0) {
            // File exists, try to reopen
            fprintf(stdout, "Port %s exists but is closed, attempting to reopen...\n", port->port_path);
            
            if (open_at_port(port, baudrate, databits, parity, stopbits) == 0) {
                fprintf(stdout, "Successfully reopened port %s\n", port->port_path);
            } else {
                fprintf(stderr, "Failed to reopen port %s\n", port->port_path);
            }
        }
    } else {
        // Port is marked as open, verify it's still accessible
        if (access(port->port_path, F_OK) != 0) {
            // File no longer exists
            fprintf(stderr, "Port %s no longer exists, marking as closed\n", port->port_path);
            close_at_port(port);
        } else {
            if (bad_fd) {
                // File descriptor is bad, port needs to be reopened
                fprintf(stderr, "Port %s file descriptor is invalid, reopening...\n", port->port_path);
                close_at_port(port);

                if (open_at_port(port, baudrate, databits, parity, stopbits) == 0) {
                    fprintf(stdout, "Successfully reopened port %s after fd failure\n", port->port_path);
                } else {
                    fprintf(stderr, "Failed to reopen port %s after fd failure\n", port->port_path);
                }
            }
        }
    }
}

void *port_monitor_thread_func(void *arg) {
    (void)arg;
    while (!g_daemon_ctx.monitor_should_stop) {
        pthread_mutex_lock(&g_daemon_ctx.ports_mutex);
        
        at_port_instance_t *current = g_daemon_ctx.ports;
        while (current) {
            check_and_reconnect_port(current);
            current = current->next;
        }
        
        pthread_mutex_unlock(&g_daemon_ctx.ports_mutex);
        
        // Sleep for monitoring interval
        sleep(PORT_MONITOR_INTERVAL);
    }
    
    return NULL;
}

void start_port_monitor(void) {
    g_daemon_ctx.monitor_should_stop = 0;
    if (pthread_create(&g_daemon_ctx.monitor_thread, NULL, port_monitor_thread_func, NULL) != 0) {
        fprintf(stderr, "Failed to create port monitor thread\n");
    } else {
        fprintf(stdout, "Port monitor thread started\n");
    }
}

void stop_port_monitor(void) {
    g_daemon_ctx.monitor_should_stop = 1;
    if (g_daemon_ctx.monitor_thread) {
        pthread_join(g_daemon_ctx.monitor_thread, NULL);
        g_daemon_ctx.monitor_thread = 0;
        fprintf(stdout, "Port monitor thread stopped\n");
    }
}
