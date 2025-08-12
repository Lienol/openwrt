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
    
    // Initialize response handling
    memset(&port->current_response, 0, sizeof(at_response_t));
    port->waiting_for_response = 0;
    port->num_end_flags = 0;
    
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
    
    // Stop the reader thread
    port->should_stop = 1;
    if (port->reader_thread) {
        pthread_join(port->reader_thread, NULL);
    }
    
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

int open_at_port(at_port_instance_t *port, int baudrate, int databits, int parity, int stopbits) {
    if (port->is_open) {
        close_at_port(port);
    }
    
    // Check if file exists before trying to open
    if (access(port->port_path, F_OK) != 0) {
        fprintf(stderr, "Port file %s does not exist\n", port->port_path);
        return -1;
    }
    
    port->fd = open(port->port_path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (port->fd < 0) {
        fprintf(stderr, "Failed to open %s: %s\n", port->port_path, strerror(errno));
        return -1;
    }
    
    // Configure terminal settings
    struct termios options;
    tcgetattr(port->fd, &options);
    
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
    
    tcsetattr(port->fd, TCSANOW, &options);
    port->termios_config = options;
    
    // Store configuration for potential reconnection
    port->configured_baudrate = baudrate;
    port->configured_databits = databits;
    port->configured_parity = parity;
    port->configured_stopbits = stopbits;
    
    port->is_open = 1;
    port->should_stop = 0;
    port->buffer_pos = 0;
    
    // Start reader thread
    if (pthread_create(&port->reader_thread, NULL, reader_thread_func, port) != 0) {
        fprintf(stderr, "Failed to create reader thread for %s\n", port->port_path);
        close(port->fd);
        port->fd = -1;
        port->is_open = 0;
        return -1;
    }
    
    return 0;
}

void close_at_port(at_port_instance_t *port) {
    if (!port->is_open) return;
    
    port->should_stop = 1;
    
    if (port->reader_thread) {
        pthread_join(port->reader_thread, NULL);
        port->reader_thread = 0;
    }
    
    if (port->fd >= 0) {
        close(port->fd);
        port->fd = -1;
    }
    
    port->is_open = 0;
}

// Port monitoring functions
void check_and_reconnect_port(at_port_instance_t *port) {
    time_t current_time = time(NULL);
    
    // Check if it's time to check this port
    if (current_time - port->last_check_time < port->check_interval) {
        return;
    }
    
    port->last_check_time = current_time;
    
    if (!port->is_open) {
        // Port is marked as closed, check if file exists and try to reopen
        if (access(port->port_path, F_OK) == 0) {
            // File exists, try to reopen
            fprintf(stdout, "Port %s exists but is closed, attempting to reopen...\n", port->port_path);
            
            // Use stored configuration or defaults
            int baudrate = (port->configured_baudrate > 0) ? port->configured_baudrate : 115200;
            int databits = (port->configured_databits > 0) ? port->configured_databits : DEFAULT_DATABITS;
            int parity = port->configured_parity;
            int stopbits = (port->configured_stopbits > 0) ? port->configured_stopbits : DEFAULT_STOPBITS;
            
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
            // File exists, check if file descriptor is still valid
            if (port->fd >= 0) {
                // Try a simple write to test if the fd is still valid
                int test_result = fcntl(port->fd, F_GETFL);
                if (test_result == -1 && errno == EBADF) {
                    // File descriptor is bad, port needs to be reopened
                    fprintf(stderr, "Port %s file descriptor is invalid, reopening...\n", port->port_path);
                    close_at_port(port);
                    
                    // Use stored configuration or defaults
                    int baudrate = (port->configured_baudrate > 0) ? port->configured_baudrate : 115200;
                    int databits = (port->configured_databits > 0) ? port->configured_databits : DEFAULT_DATABITS;
                    int parity = port->configured_parity;
                    int stopbits = (port->configured_stopbits > 0) ? port->configured_stopbits : DEFAULT_STOPBITS;
                    
                    if (open_at_port(port, baudrate, databits, parity, stopbits) == 0) {
                        fprintf(stdout, "Successfully reopened port %s after fd failure\n", port->port_path);
                    } else {
                        fprintf(stderr, "Failed to reopen port %s after fd failure\n", port->port_path);
                    }
                }
            }
        }
    }
}

void *port_monitor_thread_func(void *arg) {
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
