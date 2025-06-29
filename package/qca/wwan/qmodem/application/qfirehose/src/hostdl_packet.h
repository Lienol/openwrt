/*
    Copyright 2023 Quectel Wireless Solutions Co.,Ltd

    Quectel hereby grants customers of Quectel a license to use, modify,
    distribute and publish the Software in binary form provided that
    customers shall have no right to reverse engineer, reverse assemble,
    decompile or reduce to source code form any portion of the Software.
    Under no circumstances may customers modify, demonstrate, use, deliver
    or disclose any portion of the Software in source code form.
*/

#ifndef _HOSTDL_PACKET_H_
#define _HOSTDL_PACKET_H_

#define UNFRAMED_MAX_DATA_LENGTH 1024
#define FRAMED_MAX_DATA_LENGTH 1024
#define NUMBER_OF_PACKETS 2
#define HOST_REPLY_BUFFER_SIZE 1024

#define PACKET_OVERHEAD_SIZE 7
#define CMD_SIZE 1
#define MAGIC_SIZE 32
#define VERSION_SIZE 1
#define COMPAT_VERSION_SIZE 1
#define BLOCK_SIZE_SIZE 4
#define FLASH_BASE_SIZE 4
#define FLASH_ID_LEN_SIZE 1
#define WINDOW_SIZE_SIZE 2
#define NUM_SECTORS_SIZE 2
#define FEATURE_BITS_SIZE 4

#define FLASH_ID_STRING_SIZE 32

#define REPLY_FIXED_SIZE                                                                           \
    (PACKET_OVERHEAD_SIZE + CMD_SIZE + MAGIC_SIZE + VERSION_SIZE + COMPAT_VERSION_SIZE +           \
     BLOCK_SIZE_SIZE + FLASH_BASE_SIZE + FLASH_ID_LEN_SIZE + WINDOW_SIZE_SIZE + NUM_SECTORS_SIZE + \
     FEATURE_BITS_SIZE + FLASH_ID_STRING_SIZE)

#define REPLY_BUFFER_SIZE HOST_REPLY_BUFFER_SIZE

#define MAX_SECTORS ((REPLY_BUFFER_SIZE - REPLY_FIXED_SIZE) / 4)

#define DEVICE_UNKNOWN 0xFF

#define MAX_PACKET_SIZE (UNFRAMED_MAX_DATA_LENGTH + 1 + 4 + 2 + 9)

#define STREAM_DLOAD_MAX_VER 0x04
#define STREAM_DLOAD_MIN_VER 0x02

#define UNFRAMED_DLOAD_MIN_VER 0x04

#define UART_DLOAD_MAX_VER 0x03

#if 0
#if defined(USE_UART_ONLY) && (STREAM_DLOAD_MAX_VER > UART_DLOAD_MAX_VER)
#warning UART does not support protocol versions beyond UART_DLOAD_MAX_VER. \
    Reverting to an earlier protocol version.
#undef STREAM_DLOAD_MAX_VER
#define STREAM_DLOAD_MAX_VER UART_DLOAD_MAX_VER
#endif
#endif

#define FEATURE_UNCOMPRESSED_DLOAD 0x00000001

#define FEATURE_NAND_PRIMARY_IMAGE 0x00000002
#define FEATURE_NAND_BOOTLOADER_IMAGE 0x00000004
#define FEATURE_NAND_MULTI_IMAGE 0x00000008

#define SUPPORTED_FEATURES (FEATURE_UNCOMPRESSED_DLOAD | FEATURE_NAND_MULTI_IMAGE)

#define READ_LEN 7

#define HELLO_REQ 0x01
#define HELLO_RSP 0x02
#define READ_RSP 0x04
#define WRITE_RSP 0x06
#define STREAM_WRITE_RSP 0x08
#define NOP_RSP 0x0A
#define RESET_RSP 0x0C
#define ERROR_RSP 0x0D
#define CMD_LOG 0x0E
#define UNLOCK_RSP 0x10
#define PWRDOWN_RSP 0x12
#define OPEN_RSP 0x14
#define CLOSE_RSP 0x16
#define SECURITY_MODE_RSP 0x18
#define PARTITION_TABLE_RSP 0x1A
#define OPEN_MULTI_IMAGE_RSP 0x1C
#define ERASE_RSP 0x1E

#define UNFRAMED_STREAM_WRITE_CMD 0x30
#define UNFRAMED_STREAM_WRITE_RSP 0x31
#define DUMMY_RSP 0x32

#define FIRST_COMMAND 0x01
#define LAST_COMMAND 0x31

#if (DUMMY_RSP != (LAST_COMMAND + 1))
#error LAST_COMMAND and DUMMY_RSP mismatch. Bailing out!
#endif

#define SIZE_MSG_LEN 64

#define HELLO_CMD_OFFSET 0
#define HELLO_MAGIC_NUM_OFFSET 1
#define HELLO_MAX_VER_OFFSET 33
#define HELLO_MIN_VER_OFFSET 34
#define HELLO_MAX_DATA_SZ_1_OFFSET 35
#define HELLO_MAX_DATA_SZ_2_OFFSET 36
#define HELLO_MAX_DATA_SZ_3_OFFSET 37
#define HELLO_MAX_DATA_SZ_4_OFFSET 38

#endif
