#include "ubus_at_daemon.h"
#include <time.h>
#include <errno.h>

extern at_daemon_ctx_t g_daemon_ctx;

char *hex_to_string(const char *hex_str) {
    size_t hex_len = strlen(hex_str);
    if (hex_len % 2 != 0) {
        return NULL; // Invalid hex string
    }
    
    size_t result_len = hex_len / 2;
    char *result = malloc(result_len + 1);
    if (!result) {
        return NULL;
    }
    
    for (size_t i = 0; i < result_len; i++) {
        char hex_byte[3] = {hex_str[i*2], hex_str[i*2+1], '\0'};
        result[i] = (char)strtol(hex_byte, NULL, 16);
    }
    result[result_len] = '\0';
    
    return result;
}

void parse_end_flags(at_port_instance_t *port, const char *end_flag_str) {
    port->num_end_flags = 0;
    
    if (end_flag_str == NULL || strlen(end_flag_str) == 0) {
        // Use default end flags - manually defined since macro expansion has issues
        const char *default_flags[] = { "OK", "ERROR", "+CMS ERROR:", "+CME ERROR:", "NO CARRIER", NULL };
        for (int i = 0; default_flags[i] != NULL && i < 5; i++) {
            strncpy(port->expected_end_flags[i], default_flags[i], 63);
            port->expected_end_flags[i][63] = '\0';
            port->num_end_flags++;
        }
    } else {
        // Parse comma-separated end flags
        char temp_str[512];
        strncpy(temp_str, end_flag_str, sizeof(temp_str) - 1);
        temp_str[sizeof(temp_str) - 1] = '\0';
        
        char *token = strtok(temp_str, ",");
        while (token != NULL && port->num_end_flags < 5) {
            // Trim whitespace from token
            while (*token && (*token == ' ' || *token == '\t')) {
                token++;
            }
            
            char *end = token + strlen(token) - 1;
            while (end > token && (*end == ' ' || *end == '\t')) {
                *end = '\0';
                end--;
            }
            
            if (strlen(token) > 0) {
                strncpy(port->expected_end_flags[port->num_end_flags], token, 63);
                port->expected_end_flags[port->num_end_flags][63] = '\0';
                port->num_end_flags++;
            }
            
            token = strtok(NULL, ",");
        }
        
        // If no valid flags were parsed, use default
        if (port->num_end_flags == 0) {
            const char *default_flags[] = { "OK", "ERROR", "+CMS ERROR:", "+CME ERROR:", "NO CARRIER", NULL };
            for (int i = 0; default_flags[i] != NULL && i < 5; i++) {
                strncpy(port->expected_end_flags[i], default_flags[i], 63);
                port->expected_end_flags[i][63] = '\0';
                port->num_end_flags++;
            }
        }
    }
}

int check_end_flags(at_port_instance_t *port, const char *line, char *matched_flag) {
    // Trim whitespace from line for better matching
    char trimmed_line[1024];
    strncpy(trimmed_line, line, sizeof(trimmed_line) - 1);
    trimmed_line[sizeof(trimmed_line) - 1] = '\0';
    
    // Remove leading and trailing whitespace
    char *start = trimmed_line;
    while (*start && (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n')) {
        start++;
    }
    
    char *end = start + strlen(start) - 1;
    while (end > start && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        *end = '\0';
        end--;
    }
    
    // Check each end flag
    for (int i = 0; i < port->num_end_flags; i++) {
        const char *flag = port->expected_end_flags[i];
        
        // For exact match flags like "OK", "ERROR"
        if (strcmp(start, flag) == 0) {
            if (matched_flag) {
                strcpy(matched_flag, flag);
            }
            return 1;
        }
        
        // For prefix match flags like "+CMS ERROR:", "+CME ERROR:"
        if (strncmp(start, flag, strlen(flag)) == 0) {
            if (matched_flag) {
                strcpy(matched_flag, flag);
            }
            return 1;
        }
        
        // For substring match (fallback for compatibility)
        if (strstr(start, flag) != NULL) {
            if (matched_flag) {
                strcpy(matched_flag, flag);
            }
            return 1;
        }
    }
    return 0;
}

int send_at_command_with_response(at_port_instance_t *port, const char *cmd, int timeout, const char *end_flag, int is_raw, at_response_t *response) {
    if (!port->is_open) {
        // Auto-open with default parameters
        if (open_at_port(port, 115200, 8, 0, 1) != 0) {
            return -1;
        }
    }
    
    if (!response) {
        return -1;
    }
    
    // Initialize response
    memset(response, 0, sizeof(at_response_t));
    response->status = -1;
    
    // Record start time
    clock_gettime(CLOCK_REALTIME, &response->start_time);
    
    // Parse end flags
    parse_end_flags(port, end_flag);
    
    pthread_mutex_lock(&port->response_mutex);
    
    // Clear previous response and prepare for new one
    memset(&port->current_response, 0, sizeof(at_response_t));
    port->current_response.start_time = response->start_time;
    port->waiting_for_response = 1;
    
    pthread_mutex_unlock(&port->response_mutex);
    
    // Send command
    pthread_mutex_lock(&port->write_mutex);
    
    char *send_data;
    size_t send_len;
    
    if (is_raw) {
        send_data = hex_to_string(cmd);
        if (!send_data) {
            pthread_mutex_unlock(&port->write_mutex);
            port->waiting_for_response = 0;
            return -1;
        }
        send_len = strlen(send_data);
    } else {
        send_len = strlen(cmd) + strlen(AT_CMD_TERMINATOR);
        send_data = malloc(send_len + 1);
        if (!send_data) {
            pthread_mutex_unlock(&port->write_mutex);
            port->waiting_for_response = 0;
            return -1;
        }
        strcpy(send_data, cmd);
        strcat(send_data, AT_CMD_TERMINATOR);
    }
    
    ssize_t written = write(port->fd, send_data, send_len);
    free(send_data);
    
    pthread_mutex_unlock(&port->write_mutex);
    
    if (written != (ssize_t)send_len) {
        port->waiting_for_response = 0;
        return -1;
    }
    
    // Wait for response
    pthread_mutex_lock(&port->response_mutex);
    
    struct timespec abs_timeout;
    clock_gettime(CLOCK_REALTIME, &abs_timeout);
    abs_timeout.tv_sec += timeout;
    
    int wait_result = 0;
    while (port->waiting_for_response && wait_result == 0) {
        wait_result = pthread_cond_timedwait(&port->response_cond, &port->response_mutex, &abs_timeout);
    }
    
    // Copy response
    *response = port->current_response;
    
    // Record end time and calculate response time
    clock_gettime(CLOCK_REALTIME, &response->end_time);
    
    long start_ms = response->start_time.tv_sec * 1000 + response->start_time.tv_nsec / 1000000;
    long end_ms = response->end_time.tv_sec * 1000 + response->end_time.tv_nsec / 1000000;
    response->response_time_ms = end_ms - start_ms;
    
    if (wait_result == ETIMEDOUT) {
        response->status = -1;  // timeout
        port->waiting_for_response = 0;
    }
    
    pthread_mutex_unlock(&port->response_mutex);
    
    return response->status;
}

int send_at_command(at_port_instance_t *port, const char *cmd, int timeout, const char *end_flag, int is_raw) {
    at_response_t response;
    return send_at_command_with_response(port, cmd, timeout, end_flag, is_raw, &response);
}

int send_at_command_only(at_port_instance_t *port, const char *cmd, int is_raw) {
    if (!port->is_open) {
        // Auto-open with default parameters
        if (open_at_port(port, 115200, 8, 0, 1) != 0) {
            return -1;
        }
    }
    
    // Send command without waiting for response
    pthread_mutex_lock(&port->write_mutex);
    
    char *send_data;
    size_t send_len;
    
    if (is_raw) {
        send_data = hex_to_string(cmd);
        if (!send_data) {
            pthread_mutex_unlock(&port->write_mutex);
            return -1;
        }
        send_len = strlen(send_data);
    } else {
        send_len = strlen(cmd);
        send_data = malloc(send_len + 1);
        if (!send_data) {
            pthread_mutex_unlock(&port->write_mutex);
            return -1;
        }
        strcpy(send_data, cmd);
    }
    
    ssize_t written = write(port->fd, send_data, send_len);
    free(send_data);
    
    pthread_mutex_unlock(&port->write_mutex);
    
    if (written != (ssize_t)send_len) {
        return -1;
    }
    
    return 0;  // Success - command sent
}

void *reader_thread_func(void *arg) {
    at_port_instance_t *port = (at_port_instance_t *)arg;
    char temp_buffer[1024];
    
    while (!port->should_stop) {
        if (!port->is_open) {
            usleep(100000); // 100ms
            continue;
        }
        
        ssize_t bytes_read = read(port->fd, temp_buffer, sizeof(temp_buffer) - 1);
        if (bytes_read > 0) {
            // First, handle response data if we're waiting for one
            pthread_mutex_lock(&port->response_mutex);
            if (port->waiting_for_response) {
                // Append new data to current response preserving original bytes
                int current_len = port->current_response.response_len;
                
                if (current_len + bytes_read < MAX_BUFFER_SIZE - 1) {
                    memcpy(port->current_response.response + current_len, temp_buffer, bytes_read);
                    port->current_response.response_len = current_len + bytes_read;
                    port->current_response.response[port->current_response.response_len] = '\0';
                }
            }
            pthread_mutex_unlock(&port->response_mutex);
            
            // Then handle buffer management and line processing
            pthread_mutex_lock(&port->queue_mutex);
            
            int remaining_space = MAX_BUFFER_SIZE - port->buffer_pos - 1;
            if (bytes_read <= remaining_space) {
                memcpy(port->read_buffer + port->buffer_pos, temp_buffer, bytes_read);
                port->buffer_pos += bytes_read;
                port->read_buffer[port->buffer_pos] = '\0';
                
                // Check for complete lines
                char *line_start = port->read_buffer;
                char *line_end;
                
                while ((line_end = strstr(line_start, "\r\n")) != NULL) {
                    *line_end = '\0';
                    
                    // Process the line
                    if (strlen(line_start) > 0) {
                        int is_echo = (strncmp(line_start, "AT", 2) == 0);
                        
                        // Check if we're waiting for a response and this line might be end flag
                        int should_check_end_flag = 0;
                        pthread_mutex_lock(&port->response_mutex);
                        if (port->waiting_for_response && !is_echo) {
                            should_check_end_flag = 1;
                        }
                        pthread_mutex_unlock(&port->response_mutex);
                        
                        if (should_check_end_flag) {
                            // Check for end flags
                            char matched_flag[64];
                            if (check_end_flags(port, line_start, matched_flag)) {
                                pthread_mutex_lock(&port->response_mutex);
                                if (port->waiting_for_response) {
                                    // Record end time
                                    clock_gettime(CLOCK_REALTIME, &port->current_response.end_time);
                                    
                                    strcpy(port->current_response.end_flag_matched, matched_flag);
                                    port->current_response.status = 0;  // success
                                    port->waiting_for_response = 0;
                                    pthread_cond_signal(&port->response_cond);
                                }
                                pthread_mutex_unlock(&port->response_mutex);
                            }
                        }
                        
                        // Process for event callbacks (only when not echo)
                        if (!is_echo) {
                            process_incoming_data(port, line_start);
                        }
                    }
                    
                    line_start = line_end + 2;
                }
                
                // Move remaining data to beginning of buffer
                if (line_start != port->read_buffer) {
                    int remaining_bytes = strlen(line_start);
                    memmove(port->read_buffer, line_start, remaining_bytes + 1);
                    port->buffer_pos = remaining_bytes;
                }
            } else {
                // Buffer overflow, reset
                port->buffer_pos = 0;
                port->read_buffer[0] = '\0';
            }
            
            pthread_mutex_unlock(&port->queue_mutex);
        } else if (bytes_read < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
            // Error reading, mark port as closed
            fprintf(stderr, "Error reading from port %s: %s, marking as closed\n", 
                    port->port_path, strerror(errno));
            port->is_open = 0;
            break;
        }
        
        usleep(10000); // 10ms
    }
    
    return NULL;
}
