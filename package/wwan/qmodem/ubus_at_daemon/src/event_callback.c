#include "ubus_at_daemon.h"

void add_event_callback(at_port_instance_t *port, const char *script, const char *regex, const char *prefix) {
    event_callback_t *callback = calloc(1, sizeof(event_callback_t));
    if (!callback) {
        return;
    }
    
    strncpy(callback->callback_script, script, MAX_SCRIPT_PATH_SIZE - 1);
    
    callback->match_all = 1; // Default to match all
    callback->has_regex = 0;
    
    if (regex && strlen(regex) > 0) {
        strncpy(callback->callback_reg, regex, MAX_REGEX_SIZE - 1);
        if (regcomp(&callback->compiled_regex, regex, REG_EXTENDED) == 0) {
            callback->has_regex = 1;
            callback->match_all = 0;
        }
    } else if (prefix && strlen(prefix) > 0) {
        strncpy(callback->callback_prefix, prefix, MAX_PREFIX_SIZE - 1);
        callback->match_all = 0;
    }
    
    // Add to callback list
    callback->next = port->callbacks;
    port->callbacks = callback;
}

void remove_event_callback(at_port_instance_t *port, const char *script) {
    event_callback_t **current = &port->callbacks;
    
    while (*current) {
        if (strcmp((*current)->callback_script, script) == 0) {
            event_callback_t *to_remove = *current;
            *current = (*current)->next;
            
            if (to_remove->has_regex) {
                regfree(&to_remove->compiled_regex);
            }
            free(to_remove);
            return;
        }
        current = &(*current)->next;
    }
}

void clear_event_callbacks(at_port_instance_t *port) {
    event_callback_t *current = port->callbacks;
    
    while (current) {
        event_callback_t *next = current->next;
        
        if (current->has_regex) {
            regfree(&current->compiled_regex);
        }
        free(current);
        current = next;
    }
    
    port->callbacks = NULL;
}

void process_incoming_data(at_port_instance_t *port, const char *data) {
    event_callback_t *callback = port->callbacks;
    
    while (callback) {
        int should_trigger = 0;
        
        if (callback->match_all) {
            should_trigger = 1;
        } else if (callback->has_regex) {
            regmatch_t match;
            if (regexec(&callback->compiled_regex, data, 1, &match, 0) == 0) {
                should_trigger = 1;
            }
        } else if (strlen(callback->callback_prefix) > 0) {
            if (strncmp(data, callback->callback_prefix, strlen(callback->callback_prefix)) == 0) {
                should_trigger = 1;
            }
        }
        
        if (should_trigger) {
            // Execute callback script
            char command[MAX_SCRIPT_PATH_SIZE + MAX_BUFFER_SIZE + 32];
            snprintf(command, sizeof(command), "%s \"%s\"", callback->callback_script, data);
            
            pid_t pid = fork();
            if (pid == 0) {
                // Child process
                system(command);
                exit(0);
            } else if (pid > 0) {
                // Parent process - don't wait for child to avoid blocking
            }
        }
        
        callback = callback->next;
    }
}
