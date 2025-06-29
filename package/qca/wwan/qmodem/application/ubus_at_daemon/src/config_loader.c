#include "ubus_at_daemon.h"

extern at_daemon_ctx_t g_daemon_ctx;

int load_config_from_json(const char *json_path) {
    FILE *file = fopen(json_path, "r");
    if (!file) {
        fprintf(stderr, "Failed to open config file: %s\n", json_path);
        return -1;
    }
    
    // Read file content
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    char *content = malloc(file_size + 1);
    if (!content) {
        fclose(file);
        return -1;
    }
    
    fread(content, 1, file_size, file);
    content[file_size] = '\0';
    fclose(file);
    
    // Parse JSON
    json_object *root = json_tokener_parse(content);
    free(content);
    
    if (!root) {
        fprintf(stderr, "Failed to parse JSON config\n");
        return -1;
    }
    
    // Process each port configuration
    json_object *ports_array;
    if (json_object_object_get_ex(root, "ports", &ports_array) && 
        json_object_is_type(ports_array, json_type_array)) {
        
        int array_len = json_object_array_length(ports_array);
        for (int i = 0; i < array_len; i++) {
            json_object *port_config = json_object_array_get_idx(ports_array, i);
            if (!port_config) continue;
            
            // Get port path
            json_object *at_port_obj;
            if (!json_object_object_get_ex(port_config, JSON_AT_PORT, &at_port_obj)) {
                continue;
            }
            const char *at_port = json_object_get_string(at_port_obj);
            if (!at_port) continue;
            
            // Find or create port instance
            at_port_instance_t *port = find_port_instance(at_port);
            if (!port) {
                port = create_port_instance(at_port);
                if (!port) continue;
            }
            
            // Get terminal settings
            int baudrate = 115200, databits = 8, parity = 0, stopbits = 1;
            
            json_object *baudrate_obj;
            if (json_object_object_get_ex(port_config, JSON_BAUDRATE, &baudrate_obj)) {
                baudrate = json_object_get_int(baudrate_obj);
            }
            
            json_object *databits_obj;
            if (json_object_object_get_ex(port_config, JSON_DATABITS, &databits_obj)) {
                databits = json_object_get_int(databits_obj);
            }
            
            json_object *parity_obj;
            if (json_object_object_get_ex(port_config, JSON_PARITY, &parity_obj)) {
                parity = json_object_get_int(parity_obj);
            }
            
            json_object *stopbits_obj;
            if (json_object_object_get_ex(port_config, JSON_STOPBITS, &stopbits_obj)) {
                stopbits = json_object_get_int(stopbits_obj);
            }
            
            // Open the port
            if (open_at_port(port, baudrate, databits, parity, stopbits) != 0) {
                fprintf(stderr, "Failed to open port %s\n", at_port);
                continue;
            }
            
            // Process event callbacks
            json_object *callbacks_array;
            if (json_object_object_get_ex(port_config, JSON_CALLBACKS, &callbacks_array) &&
                json_object_is_type(callbacks_array, json_type_array)) {
                
                int cb_array_len = json_object_array_length(callbacks_array);
                for (int j = 0; j < cb_array_len; j++) {
                    json_object *callback_config = json_object_array_get_idx(callbacks_array, j);
                    if (!callback_config) continue;
                    
                    json_object *script_obj;
                    if (!json_object_object_get_ex(callback_config, JSON_CALLBACK_SCRIPT, &script_obj)) {
                        continue;
                    }
                    const char *script = json_object_get_string(script_obj);
                    if (!script) continue;
                    
                    const char *regex = NULL, *prefix = NULL;
                    
                    json_object *regex_obj;
                    if (json_object_object_get_ex(callback_config, JSON_CALLBACK_REG, &regex_obj)) {
                        regex = json_object_get_string(regex_obj);
                    }
                    
                    json_object *prefix_obj;
                    if (json_object_object_get_ex(callback_config, JSON_CALLBACK_PREFIX, &prefix_obj)) {
                        prefix = json_object_get_string(prefix_obj);
                    }
                    
                    add_event_callback(port, script, regex, prefix);
                }
            }
        }
    }
    
    json_object_put(root);
    return 0;
}
