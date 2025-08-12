#ifndef CONST_H
#define CONST_H

#include <termios.h>

// Default AT port settings
#define DEFAULT_BAUDRATE B115200
#define DEFAULT_DATABITS 8
#define DEFAULT_PARITY 0    // no parity
#define DEFAULT_STOPBITS 1
#define DEFAULT_TIMEOUT 5   // seconds

// Port monitoring settings
#define DEFAULT_CHECK_INTERVAL 30  // seconds
#define PORT_MONITOR_INTERVAL 5    // seconds

// Buffer sizes
#define MAX_AT_PORTS 32
#define MAX_BUFFER_SIZE 16384
#define MAX_QUEUE_SIZE 100
#define MAX_AT_CMD_SIZE 512
#define MAX_PORT_PATH_SIZE 64
#define MAX_SCRIPT_PATH_SIZE 256
#define MAX_REGEX_SIZE 128
#define MAX_PREFIX_SIZE 64
#define MAX_CALLBACKS 16

// AT command termination
#define AT_CMD_TERMINATOR "\r\n"
#define DEFAULT_END_FLAG "OK"

// Default end flags list
#define DEFAULT_END_FLAGS { "OK", "ERROR", "+CMS ERROR:", "+CME ERROR:", "NO CARRIER", NULL }

// JSON config keys
#define JSON_AT_PORT "at_port"
#define JSON_BAUDRATE "baudrate"
#define JSON_DATABITS "databits"
#define JSON_PARITY "parity"
#define JSON_STOPBITS "stopbits"
#define JSON_TIMEOUT "timeout"
#define JSON_CALLBACKS "event_callbacks"
#define JSON_CALLBACK_SCRIPT "callback_script"
#define JSON_CALLBACK_REG "callback_reg"
#define JSON_CALLBACK_PREFIX "callback_prefix"

#endif // CONST_H
