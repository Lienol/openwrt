/*
    Copyright 2023 Quectel Wireless Solutions Co.,Ltd

    Quectel hereby grants customers of Quectel a license to use, modify,
    distribute and publish the Software in binary form provided that
    customers shall have no right to reverse engineer, reverse assemble,
    decompile or reduce to source code form any portion of the Software.
    Under no circumstances may customers modify, demonstrate, use, deliver
    or disclose any portion of the Software in source code form.
*/

#ifndef SAHARA_H
#define SAHARA_H

#define Q_SAHARA_RAW_BUF_SZ (4*1024)
#define Q_SAHARA_STATUS_ZERO 0x00
#define Q_SAHARA_MODE_ZERO 0x00
#define Q_SAHARA_MODE_ONE 0x01

#define Q_SAHARA_ZERO 0x00
#define Q_SAHARA_ONE 0x01
#define Q_SAHARA_TWO 0x02
#define Q_SAHARA_THREE 0x03
#define Q_SAHARA_FOUR 0x04
#define Q_SAHARA_FIVE 0x05
#define Q_SAHARA_SEVEN 0x07
#define Q_SAHARA_EIGHTEEN 0x12
#define Q_SAHARA_NINETEEN 0x13

typedef struct
{
  uint32_t q_cmd;
  uint32_t q_len;
} q_sahara_packet_h;

struct sahara_pkt
{
    q_sahara_packet_h q_header;

    union
    {
        struct
        {
            uint32_t q_ver;
            uint32_t q_ver_sup;
            uint32_t q_cmd_packet_len;
            uint32_t q_mode;
        } q_sahara_hello_packet;
        struct
        {
            uint32_t q_ver;
            uint32_t q_ver_sup;
            uint32_t q_status;
            uint32_t q_mode;
            uint32_t q_reserve1;
            uint32_t q_reserve2;
            uint32_t q_reserve3;
            uint32_t q_reserve4;
            uint32_t q_reserve5;
            uint32_t q_reserve6;
        } q_sahara_hello_packet_response;
        struct
        {
            uint32_t q_image_id;
            uint32_t q_data_offset;
            uint32_t q_data_length;
        } q_sahara_read_packet_data;
        struct
        {
            uint32_t q_image_id;
            uint32_t q_status;
        } q_sahara_end_packet_image_tx;
        struct
        {
        } q_sahara_done_packet;
        struct
        {
            uint32_t q_image_tx_status;
        } q_sahara_done_packet_response;
        struct
        {
            uint64_t q_image_id;
            uint64_t q_data_offset;
            uint64_t q_data_length;
        } q_sahara_read_packet_data_64bit;
        struct
        {
        } q_sahara_reset_packet;
        struct
        {
        } q_sahara_reset_packet_response;
    };
};
#endif
