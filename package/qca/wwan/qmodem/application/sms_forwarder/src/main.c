#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <syslog.h>
#include <json-c/json.h>
#include "sms_forwarder.h"

static volatile int g_running = 1;
static sms_forwarder_config_t g_config;

static void signal_handler(int sig) {
    switch (sig) {
        case SIGTERM:
        case SIGINT:
            syslog(LOG_INFO, "Received signal %d, shutting down", sig);
            g_running = 0;
            break;
        case SIGCHLD:
            wait(NULL);
            break;
    }
}

static void setup_signals() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGCHLD, signal_handler);
    signal(SIGPIPE, SIG_IGN);
}

static int parse_config_file(const char *config_file, sms_forwarder_config_t *config) {
    FILE *fp = fopen(config_file, "r");
    if (!fp) {
        syslog(LOG_ERR, "Cannot open config file: %s", config_file);
        return -1;
    }

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    char *json_string = malloc(size + 1);
    if (!json_string) {
        fclose(fp);
        syslog(LOG_ERR, "Memory allocation failed");
        return -1;
    }
    
    fread(json_string, 1, size, fp);
    json_string[size] = '\0';
    fclose(fp);

    json_object *root = json_tokener_parse(json_string);
    free(json_string);

    if (!root) {
        syslog(LOG_ERR, "Invalid JSON in config file");
        return -1;
    }

    // Initialize config structure
    memset(config, 0, sizeof(sms_forwarder_config_t));

    // Check if root is an array (new format) or object (old format)
    if (json_object_is_type(root, json_type_array)) {
        // New format: array of modem configurations
        int array_len = json_object_array_length(root);
        config->modem_count = (array_len > MAX_API_COUNT) ? MAX_API_COUNT : array_len;
        
        for (int i = 0; i < config->modem_count; i++) {
            json_object *modem_obj = json_object_array_get_idx(root, i);
            if (!modem_obj) continue;
            
            // Set defaults
            config->modems[i].poll_interval = 30;
            config->modems[i].delete_after_forward = 0;
            config->modems[i].api_count = 0;
            
            // Parse modem_port
            json_object *obj;
            const char *str_val;
            
            if (json_object_object_get_ex(modem_obj, "modem_port", &obj)) {
                str_val = json_object_get_string(obj);
                if (str_val) {
                    strncpy(config->modems[i].modem_port, str_val, sizeof(config->modems[i].modem_port) - 1);
                    config->modems[i].modem_port[sizeof(config->modems[i].modem_port) - 1] = '\0';
                }
            }
            
            if (json_object_object_get_ex(modem_obj, "poll_interval", &obj)) {
                config->modems[i].poll_interval = json_object_get_int(obj);
            }
            
            if (json_object_object_get_ex(modem_obj, "delete_after_forward", &obj)) {
                config->modems[i].delete_after_forward = json_object_get_boolean(obj);
            }
            
            // Parse apis array
            json_object *apis_array;
            if (json_object_object_get_ex(modem_obj, "apis", &apis_array) && json_object_is_type(apis_array, json_type_array)) {
                int api_array_len = json_object_array_length(apis_array);
                config->modems[i].api_count = (api_array_len > MAX_API_COUNT) ? MAX_API_COUNT : api_array_len;
                
                for (int j = 0; j < config->modems[i].api_count; j++) {
                    json_object *api_obj = json_object_array_get_idx(apis_array, j);
                    if (!api_obj) continue;
                    
                    if (json_object_object_get_ex(api_obj, "api_type", &obj)) {
                        str_val = json_object_get_string(obj);
                        if (str_val) {
                            strncpy(config->modems[i].apis[j].api_type, str_val, sizeof(config->modems[i].apis[j].api_type) - 1);
                            config->modems[i].apis[j].api_type[sizeof(config->modems[i].apis[j].api_type) - 1] = '\0';
                        }
                    }
                    
                    if (json_object_object_get_ex(api_obj, "api_config", &obj)) {
                        const char *api_config_str = json_object_to_json_string(obj);
                        if (api_config_str) {
                            strncpy(config->modems[i].apis[j].api_config, api_config_str, sizeof(config->modems[i].apis[j].api_config) - 1);
                            config->modems[i].apis[j].api_config[sizeof(config->modems[i].apis[j].api_config) - 1] = '\0';
                        }
                    }
                }
            }
        }
    } else {
        // Old format: single modem configuration - convert to new format
        config->modem_count = 1;
        config->modems[0].poll_interval = 30;
        config->modems[0].delete_after_forward = 0;
        config->modems[0].api_count = 1;
        
        json_object *obj;
        const char *str_val;
        
        if (json_object_object_get_ex(root, "modem_port", &obj)) {
            str_val = json_object_get_string(obj);
            if (str_val) {
                strncpy(config->modems[0].modem_port, str_val, sizeof(config->modems[0].modem_port) - 1);
                config->modems[0].modem_port[sizeof(config->modems[0].modem_port) - 1] = '\0';
            }
        }
        
        if (json_object_object_get_ex(root, "poll_interval", &obj)) {
            config->modems[0].poll_interval = json_object_get_int(obj);
        }
        
        if (json_object_object_get_ex(root, "api_type", &obj)) {
            str_val = json_object_get_string(obj);
            if (str_val) {
                strncpy(config->modems[0].apis[0].api_type, str_val, sizeof(config->modems[0].apis[0].api_type) - 1);
                config->modems[0].apis[0].api_type[sizeof(config->modems[0].apis[0].api_type) - 1] = '\0';
            }
        }
        
        if (json_object_object_get_ex(root, "api_config", &obj)) {
            const char *api_config_str = json_object_to_json_string(obj);
            if (api_config_str) {
                strncpy(config->modems[0].apis[0].api_config, api_config_str, sizeof(config->modems[0].apis[0].api_config) - 1);
                config->modems[0].apis[0].api_config[sizeof(config->modems[0].apis[0].api_config) - 1] = '\0';
            }
        }
        
        if (json_object_object_get_ex(root, "delete_after_forward", &obj)) {
            config->modems[0].delete_after_forward = json_object_get_boolean(obj);
        }
    }

    json_object_put(root);
    return 0;
}

static int check_dependencies() {
    // Check if curl is available
    if (system("which curl > /dev/null 2>&1") == 0) {
        return USE_CURL;
    }
    
    // Check if wget is available
    if (system("which wget > /dev/null 2>&1") == 0) {
        return USE_WGET;
    }
    
    syslog(LOG_WARNING, "Neither curl nor wget found, only custom scripts will work");
    return USE_NONE;
}

static char* read_sms_from_modem(const char *modem_port) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "tom_modem -d %s -u -o u 2>/dev/null", modem_port);
    
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        syslog(LOG_ERR, "Failed to execute tom_modem command");
        return NULL;
    }
    
    char *result = malloc(SMS_BUFFER_SIZE);
    if (!result) {
        pclose(fp);
        syslog(LOG_ERR, "Memory allocation failed");
        return NULL;
    }
    
    size_t total_read = 0;
    size_t bytes_read;
    
    while ((bytes_read = fread(result + total_read, 1, SMS_BUFFER_SIZE - total_read - 1, fp)) > 0) {
        total_read += bytes_read;
        if (total_read >= SMS_BUFFER_SIZE - 1) {
            break;
        }
    }
    
    result[total_read] = '\0';
    pclose(fp);
    
    if (total_read == 0) {
        free(result);
        return NULL;
    }
    
    return result;
}

static int delete_sms_from_modem(const char *modem_port, int *indices, int count) {
    if (!indices || count <= 0) {
        return 0;
    }
    
    for (int i = 0; i < count; i++) {
        char cmd[256];
        snprintf(cmd, sizeof(cmd), "tom_modem -d %s -u -o d -i %d 2>/dev/null", 
                 modem_port, indices[i]);
        
        int ret = system(cmd);
        if (ret != 0) {
            syslog(LOG_WARNING, "Failed to delete SMS at index %d from modem", indices[i]);
        } else {
            syslog(LOG_INFO, "Successfully deleted SMS at index %d from modem", indices[i]);
        }
    }
    
    return 0;
}

static sms_message_t* parse_sms_json(const char *json_str, int *count) {
    json_object *root = json_tokener_parse(json_str);
    if (!root) {
        syslog(LOG_ERR, "Failed to parse SMS JSON");
        return NULL;
    }
    
    json_object *msg_array;
    if (!json_object_object_get_ex(root, "msg", &msg_array)) {
        json_object_put(root);
        return NULL;
    }
    
    int array_len = json_object_array_length(msg_array);
    if (array_len == 0) {
        json_object_put(root);
        *count = 0;
        return NULL;
    }
    
    sms_message_t *messages = malloc(array_len * sizeof(sms_message_t));
    if (!messages) {
        json_object_put(root);
        syslog(LOG_ERR, "Memory allocation failed for messages");
        *count = 0;
        return NULL;
    }
    *count = array_len;
    
    for (int i = 0; i < array_len; i++) {
        json_object *msg_obj = json_object_array_get_idx(msg_array, i);
        json_object *field;
        const char *str_val;
        
        memset(&messages[i], 0, sizeof(sms_message_t));
        
        if (json_object_object_get_ex(msg_obj, "index", &field)) {
            messages[i].index = json_object_get_int(field);
        }
        
        if (json_object_object_get_ex(msg_obj, "sender", &field)) {
            str_val = json_object_get_string(field);
            if (str_val) {
                strncpy(messages[i].sender, str_val, sizeof(messages[i].sender) - 1);
                messages[i].sender[sizeof(messages[i].sender) - 1] = '\0';
            }
        }
        
        if (json_object_object_get_ex(msg_obj, "timestamp", &field)) {
            messages[i].timestamp = json_object_get_int64(field);
        }
        
        if (json_object_object_get_ex(msg_obj, "content", &field)) {
            str_val = json_object_get_string(field);
            if (str_val) {
                strncpy(messages[i].content, str_val, sizeof(messages[i].content) - 1);
                messages[i].content[sizeof(messages[i].content) - 1] = '\0';
            }
        }
        
        if (json_object_object_get_ex(msg_obj, "reference", &field)) {
            messages[i].reference = json_object_get_int(field);
        }
        
        if (json_object_object_get_ex(msg_obj, "total", &field)) {
            messages[i].total = json_object_get_int(field);
        }
        
        if (json_object_object_get_ex(msg_obj, "part", &field)) {
            messages[i].part = json_object_get_int(field);
        }
    }
    
    json_object_put(root);
    return messages;
}

static int find_and_process_sms_groups(sms_message_t *messages, int count, processed_sms_t **processed, int *processed_count) {
    *processed = NULL;
    *processed_count = 0;
    
    if (!messages || count == 0) {
        return 0;
    }
    
    // Track which messages have been processed
    int *processed_flags = calloc(count, sizeof(int));
    if (!processed_flags) {
        syslog(LOG_ERR, "Memory allocation failed for processed flags");
        return -1;
    }
    
    processed_sms_t *temp_processed = malloc(count * sizeof(processed_sms_t));
    if (!temp_processed) {
        free(processed_flags);
        syslog(LOG_ERR, "Memory allocation failed for processed messages");
        return -1;
    }
    
    int temp_count = 0;
    
    // First, process single part messages
    for (int i = 0; i < count; i++) {
        if (processed_flags[i] || messages[i].total > 1) {
            continue;
        }
        
        // Single part message
        temp_processed[temp_count].content = malloc(strlen(messages[i].content) + 1);
        if (!temp_processed[temp_count].content) {
            syslog(LOG_ERR, "Memory allocation failed for single SMS content");
            continue;
        }
        strcpy(temp_processed[temp_count].content, messages[i].content);
        strcpy(temp_processed[temp_count].sender, messages[i].sender);
        temp_processed[temp_count].timestamp = messages[i].timestamp;
        
        temp_processed[temp_count].indices = malloc(sizeof(int));
        if (temp_processed[temp_count].indices) {
            temp_processed[temp_count].indices[0] = messages[i].index;
            temp_processed[temp_count].index_count = 1;
        } else {
            temp_processed[temp_count].index_count = 0;
        }
        
        processed_flags[i] = 1;
        temp_count++;
    }
    
    // Then, process multipart messages
    for (int i = 0; i < count; i++) {
        if (processed_flags[i] || messages[i].total <= 1) {
            continue;
        }
        
        int ref = messages[i].reference;
        char *sender = messages[i].sender;
        int total_parts = messages[i].total;
        
        // Collect all parts for this reference and sender
        sms_message_t *parts = malloc(total_parts * sizeof(sms_message_t));
        if (!parts) {
            syslog(LOG_ERR, "Memory allocation failed for SMS parts");
            continue;
        }
        
        int found_parts = 0;
        for (int j = 0; j < count; j++) {
            if (processed_flags[j]) continue;
            
            if (messages[j].reference == ref && 
                strcmp(messages[j].sender, sender) == 0 &&
                messages[j].total == total_parts) {
                parts[found_parts++] = messages[j];
            }
        }
        
        if (found_parts == total_parts) {
            // Sort parts by part number
            for (int x = 0; x < found_parts - 1; x++) {
                for (int y = x + 1; y < found_parts; y++) {
                    if (parts[x].part > parts[y].part) {
                        sms_message_t temp = parts[x];
                        parts[x] = parts[y];
                        parts[y] = temp;
                    }
                }
            }
            
            // Concatenate content
            int total_len = 0;
            for (int k = 0; k < found_parts; k++) {
                total_len += strlen(parts[k].content);
            }
            
            temp_processed[temp_count].content = malloc(total_len + 1);
            if (temp_processed[temp_count].content) {
                temp_processed[temp_count].content[0] = '\0';
                for (int k = 0; k < found_parts; k++) {
                    strcat(temp_processed[temp_count].content, parts[k].content);
                }
                
                strcpy(temp_processed[temp_count].sender, parts[0].sender);
                temp_processed[temp_count].timestamp = parts[0].timestamp;
                
                // Store indices for deletion
                temp_processed[temp_count].indices = malloc(found_parts * sizeof(int));
                if (temp_processed[temp_count].indices) {
                    for (int k = 0; k < found_parts; k++) {
                        temp_processed[temp_count].indices[k] = parts[k].index;
                    }
                    temp_processed[temp_count].index_count = found_parts;
                } else {
                    temp_processed[temp_count].index_count = 0;
                }
                
                // Mark all parts as processed
                for (int j = 0; j < count; j++) {
                    if (messages[j].reference == ref && 
                        strcmp(messages[j].sender, sender) == 0 &&
                        messages[j].total == total_parts) {
                        processed_flags[j] = 1;
                    }
                }
               
                temp_count++;
            }
        }
        
        free(parts);
    }
    
    free(processed_flags);
    
    if (temp_count > 0) {
        *processed = temp_processed;
        *processed_count = temp_count;
    } else {
        free(temp_processed);
    }
    
    return 0;
}

static int execute_callback(const char *api_type, const char *api_config, 
                           const char *sender, time_t timestamp, const char *content) {
    
    char time_str[32];
    struct tm *tm_info = localtime(&timestamp);
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);
    
    // Set environment variables
    setenv("SMS_SENDER", sender, 1);
    setenv("SMS_TIME", time_str, 1);
    setenv("SMS_CONTENT", content, 1);
    
    char script_path[256];
    char cmd[512];
    
    if (strcmp(api_type, "custom_script") == 0) {
        json_object *config_obj = json_tokener_parse(api_config);
        if (!config_obj) {
            syslog(LOG_ERR, "Invalid API config JSON");
            return -1;
        }
        
        json_object *script_obj;
        if (json_object_object_get_ex(config_obj, "script_path", &script_obj)) {
            strncpy(script_path, json_object_get_string(script_obj), sizeof(script_path) - 1);
        }
        json_object_put(config_obj);
        
        snprintf(cmd, sizeof(cmd), "%s", script_path);
    } else {
        snprintf(script_path, sizeof(script_path), "/usr/bin/sms_forward_%s.sh", api_type);
        snprintf(cmd, sizeof(cmd), "%s '%s'", script_path, api_config);
    }
    
    // Execute script
    int ret = system(cmd);
    if (ret != 0) {
        syslog(LOG_ERR, "Failed to execute callback script: %s", script_path);
        return -1;
    }
    
    syslog(LOG_INFO, "SMS forwarded successfully via %s", api_type);
    return 0;
}

static void process_sms_messages(modem_config_t *modem_config) {
    char *sms_json = read_sms_from_modem(modem_config->modem_port);
    if (!sms_json) {
        return;
    }
    
    int count;
    sms_message_t *messages = parse_sms_json(sms_json, &count);
    free(sms_json);
    
    if (!messages || count == 0) {
        return;
    }
    
    processed_sms_t *processed = NULL;
    int processed_count = 0;
    
    if (find_and_process_sms_groups(messages, count, &processed, &processed_count) == 0 && processed) {
        // Process all SMS messages
        for (int i = 0; i < processed_count; i++) {
            int success_count = 0;
            
            // Try to forward through all configured APIs
            for (int j = 0; j < modem_config->api_count; j++) {
                int ret = execute_callback(modem_config->apis[j].api_type, modem_config->apis[j].api_config,
                                processed[i].sender, processed[i].timestamp, processed[i].content);
                if (ret == 0) {
                    success_count++;
                }
            }
            
            // Delete SMS messages if at least one forwarding was successful and delete option is enabled
            if (success_count > 0 && modem_config->delete_after_forward && processed[i].indices) {
                delete_sms_from_modem(modem_config->modem_port, processed[i].indices, processed[i].index_count);
            }
            
            // Cleanup
            if (processed[i].content) {
                free(processed[i].content);
            }
            if (processed[i].indices) {
                free(processed[i].indices);
            }
        }
        
        free(processed);
    }
    
    free(messages);
}

int main(int argc, char *argv[]) {
    printf("SMS Forwarder starting...\n");
    fflush(stdout);
    
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <config_file>\n", argv[0]);
        return 1;
    }
    
    printf("Opening syslog...\n");
    fflush(stdout);
    openlog("sms_forwarder", LOG_PID, LOG_DAEMON);
    
    printf("Parsing config file: %s\n", argv[1]);
    fflush(stdout);
    
    // Parse configuration
    if (parse_config_file(argv[1], &g_config) < 0) {
        syslog(LOG_ERR, "Failed to parse config file: %s", argv[1]);
        printf("Failed to parse config file\n");
        return 1;
    }
    
    printf("Config parsed successfully\n");
    printf("Found %d modem(s) to monitor:\n", g_config.modem_count);
    for (int i = 0; i < g_config.modem_count; i++) {
        printf("  Modem %d: %s (poll: %ds, APIs: %d, delete: %s)\n", 
               i + 1, g_config.modems[i].modem_port, g_config.modems[i].poll_interval,
               g_config.modems[i].api_count, g_config.modems[i].delete_after_forward ? "yes" : "no");
        for (int j = 0; j < g_config.modems[i].api_count; j++) {
            printf("    API %d: %s\n", j + 1, g_config.modems[i].apis[j].api_type);
        }
    }
    fflush(stdout);
    
    // Check dependencies
    printf("Checking dependencies...\n");
    fflush(stdout);
    check_dependencies();
    
    // Setup signal handlers
    printf("Setting up signal handlers...\n");
    fflush(stdout);
    setup_signals();
    
    syslog(LOG_INFO, "SMS Forwarder started with config: %s, monitoring %d modems", argv[1], g_config.modem_count);
    printf("Entering main loop...\n");
    fflush(stdout);
    
    // Main loop
    while (g_running) {
        for (int i = 0; i < g_config.modem_count; i++) {
            process_sms_messages(&g_config.modems[i]);
        }
        
        // Find the minimum poll interval among all modems
        int min_poll_interval = g_config.modems[0].poll_interval;
        for (int i = 1; i < g_config.modem_count; i++) {
            if (g_config.modems[i].poll_interval < min_poll_interval) {
                min_poll_interval = g_config.modems[i].poll_interval;
            }
        }
        
        fflush(stdout);
        sleep(min_poll_interval);
    }
    
    syslog(LOG_INFO, "SMS Forwarder stopped");
    closelog();
    return 0;
}
