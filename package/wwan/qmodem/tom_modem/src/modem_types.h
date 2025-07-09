
#ifndef _MODEM_TYPES_H_
#define _MODEM_TYPES_H_
#include <stdio.h>
#include <termios.h>
#include <time.h>
//options
#define AT_CMD_S 'c'
#define TTY_DEV_S 'd'
#define BAUD_RATE_S 'b'
#define DATA_BITS_S 'B'
#define PARITY_S 'P'
#define STOP_BITS_S 'S'
#define FLOW_CONTROL_S 'F'
#define TIMEOUT_S 't'
#define OPERATION_S 'o'
#define DEBUG_S 'D'
#define SMS_PDU_S 'p'
#define SMS_INDEX_S 'i'
#define GREEDY_READ_S 'g'

#define AT_CMD_L "at_cmd"
#define TTY_DEV_L "tty_dev"
#define BAUD_RATE_L "baud_rate"
#define DATA_BITS_L "data_bits"
#define PARITY_L "parity"
#define STOP_BITS_L "stop_bits"
#define FLOW_CONTROL_L "flow_control"
#define TIMEOUT_L "timeout"
#define OPERATION_L "operation"
#define DEBUG_L "debug"
#define SMS_PDU_L "sms_pdu"
#define SMS_INDEX_L "sms_index"
#define GREEDY_READ_L "greedy_read"

//operations
#define AT_OP_S 'a'
#define AT_OP_L "at"
#define BINARY_AT_OP_S 'b'
#define BINARY_AT_OP_L "binary_at"
#define SMS_READ_OP_S 'r'
#define SMS_READ_OP_L "sms_read"
#define SMS_SEND_OP_S 's'
#define SMS_SEND_OP_L "sms_send"
#define SMS_DELETE_OP_S 'd'
#define SMS_DELETE_OP_L "sms_delete"
#ifdef USE_SEMAPHORE
#define CLEANUP_SEMAPHORE_OP_S 'C'
#define CLEANUP_SEMAPHORE_OP_L "cleanup"
#endif
#define SET_READ_STORAGE "AT+CPMS=\"%s\""
#define SET_PDU_FORMAT "AT+CMGF=0"
#define READ_ALL_SMS "AT+CMGL=4"
#define SEND_SMS "AT+CMGS=%d"
#define DELETE_SMS "AT+CMGD=%d"

#define SMS_BUF_SIZE 65536
#define LINE_BUF 1024
#define SMS_LIST_SIZE 128
#define COMMON_BUF_SIZE 65536
#define PHONE_NUMBER_SIZE 64
#define SMS_TEXT_SIZE 256
#define SMS_PDU_STR_SIZE 512
#define SMS_PDU_HEX_SIZE 512

// at_tool profile
typedef struct _PROFILE {
    // AT command
    // TTY device
    // Baud rate
    // Data bits
    // Parity
    // Stop bits
    // Flow control
    // Timeout
    // operation
    // debug mode
    char *at_cmd;
    char *tty_dev;
    int baud_rate;
    int data_bits;
    char *parity;
    int stop_bits;
    char *flow_control;
    int timeout;
    int op;
    int debug;
    char *sms_pdu;
    int sms_index;
    int greedy_read;
} PROFILE_T;


typedef struct _FDS {
    int tty_fd;
    struct termios old_termios;
    FILE *fdi;
    FILE *fdo;
} FDS_T;

typedef struct _SMS {
    int sms_index;
    int sms_lenght;
    int ref_number;
    int segment_number;
    time_t timestamp;
    int total_segments;
    int type;
    char *sender;
    char *sms_text;
    char *sms_pdu;
} SMS_T;

typedef struct _AT_MESSAGE {
    char *message;
    int len;
} AT_MESSAGE_T;

enum ERROR_CODES {
    COMM_ERROR = -1,
    SUCCESS = 0,
    KEYWORD_NOT_MATCH,
    TIMEOUT_WAITING_NEWLINE,
    INVALID_PARAM,
    INVALID_HEX,
    UNKNOWN_ERROR,
    BUFFER_OVERFLOW,
};

enum SMS_CHARSET {
    SMS_CHARSET_7BIT,
    SMS_CHARSET_UCS2
}; 

enum OPTIONS {
    AT_CMD,
    TTY_DEV,
    BAUD_RATE,
    DATA_BITS,
    PARITY,
    STOP_BITS,
    FLOW_CONTROL,
    TIMEOUT,
    OPERATION,
    DEBUG,
    SMS_PDU,
    SMS_INDEX,
    GREEDY_READ
};

enum OPERATIONS {
    NULL_OP,
    AT_OP,
    BINARY_AT_OP,
    SMS_READ_OP,
    SMS_SEND_OP,
    SMS_DELETE_OP,
    CLEANUP_SEMAPHORE_OP
};

#endif
