#ifndef SMS_FORWARDER_H
#define SMS_FORWARDER_H

#include <time.h>

#define SMS_BUFFER_SIZE 65536
#define MAX_PATH_LEN 256
#define MAX_CONFIG_LEN 1024
#define MAX_CONTENT_LEN 512
#define MAX_SENDER_LEN 64
#define MAX_API_COUNT 10

#define USE_CURL 1
#define USE_WGET 2
#define USE_NONE 0

typedef struct {
    char api_type[64];
    char api_config[MAX_CONFIG_LEN];
} api_config_t;

typedef struct {
    char modem_port[MAX_PATH_LEN];
    int poll_interval;
    api_config_t apis[MAX_API_COUNT];
    int api_count;
    int delete_after_forward;
} modem_config_t;

typedef struct {
    modem_config_t modems[MAX_API_COUNT];
    int modem_count;
} sms_forwarder_config_t;

typedef struct {
    int index;
    char sender[MAX_SENDER_LEN];
    time_t timestamp;
    char content[MAX_CONTENT_LEN];
    int reference;
    int total;
    int part;
} sms_message_t;

typedef struct {
    char *content;
    char sender[MAX_SENDER_LEN];
    time_t timestamp;
    int *indices;
    int index_count;
} processed_sms_t;

#endif
