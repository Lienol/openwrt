#include "utils.h"

#ifdef USE_SEMAPHORE
void generate_semaphore_name(const char* filename, char* semaphore_name) {
    snprintf(semaphore_name, MAX_FILENAME_LEN, "%s%s", SEMAPHORE_PREFIX, filename);
    for (int i = 0; semaphore_name[i] != '\0'; i++) {
        if (semaphore_name[i] == '/') {
            semaphore_name[i] = '_';
        }
    }
}

int lock_at_port(char* filename){
    char semaphore_name[MAX_FILENAME_LEN];
    generate_semaphore_name(filename, semaphore_name);
    dbg_msg("semaphore_name: %s", semaphore_name);
    sem_t *sem = sem_open(semaphore_name, O_CREAT, 0644, 1);
    if (sem == SEM_FAILED) {
        perror("sem_open failed");
        return -1;
    }
    sem_wait(sem);
    return 0;
}

int unlock_at_port(char* filename){
    char semaphore_name[MAX_FILENAME_LEN];
    generate_semaphore_name(filename, semaphore_name);
    dbg_msg("semaphore_name: %s", semaphore_name);
    sem_t *sem = sem_open(semaphore_name, O_CREAT, 0644, 1);
    if (sem == SEM_FAILED) {
        perror("sem_open failed");
        return -1;
    }
    sem_post(sem);
    sem_close(sem);
    sem_unlink(semaphore_name);
    return 0;
}

#endif


static int char_to_hex(char c)
{
    // convert char to hex
    int is_digit, is_lower, is_upper;
    is_digit = c - '0';
    is_lower = c - 'a' + 10;
    is_upper = c - 'A' + 10;
    if (is_digit >= 0 && is_digit <= 9)
    {
        return is_digit;
    }
    else if (is_lower >= 10 && is_lower <= 15)
    {
        return is_lower;
    }
    else if (is_upper >= 10 && is_upper <= 15)
    {
        return is_upper;
    }
    else
    {
        return -1;
    }
}
int decode_pdu(SMS_T *sms)
{
    char sms_text[SMS_TEXT_SIZE] = {0};
    int tp_dcs;
    int skip_bytes;
    int pdu_str_len;
    unsigned char hex_pdu[SMS_PDU_HEX_SIZE] = {0};
    pdu_str_len = strlen(sms->sms_pdu);
    for (int i = 0; i < pdu_str_len; i += 2)
    {
        hex_pdu[i / 2] = char_to_hex(sms->sms_pdu[i]) << 4;
        hex_pdu[i / 2] |= char_to_hex(sms->sms_pdu[i + 1]);
    }
    int sms_len = pdu_decode(hex_pdu, pdu_str_len/2,
                             &sms->timestamp,
                             sms->sender, PHONE_NUMBER_SIZE,
                             sms_text, SMS_TEXT_SIZE,
                             &tp_dcs,
                             &sms->ref_number,
                             &sms->total_segments,
                             &sms->segment_number,
                             &skip_bytes);
    if (sms_len <= 0)
    {
        err_msg("Error decoding pdu");
        return sms_len;
    }
    sms->sms_lenght = sms_len;

    switch ((tp_dcs / 4) % 4)
    {
    case 0:
        { 
            // GSM 7 bit
            sms->type = SMS_CHARSET_7BIT;
            int i;
            i = skip_bytes;
            if (skip_bytes > 0)
                i = (skip_bytes * 8 + 6) / 7;
            for (; i < strlen(sms_text); i++)
            {
                sprintf(sms->sms_text + i, "%c", sms_text[i]);
            }
            i++;
            sprintf(sms->sms_text + i, "%c", '\0');
            break;
        }
    case 2:
        { 
            // UCS2
            sms->type = SMS_CHARSET_UCS2;
            int offset = 0;
            for (int i = skip_bytes; i < SMS_TEXT_SIZE; i += 2)
            {
                int ucs2_char = 0x000000FF & sms_text[i + 1];
                ucs2_char |= (0x0000FF00 & (sms_text[i] << 8));
                unsigned char utf8_char[5];
                int len = ucs2_to_utf8(ucs2_char, utf8_char);
                int j;
                for (j = 0; j < len; j++)
                {
                    sprintf(sms->sms_text + offset, "%c", utf8_char[j]);
                    if (utf8_char[j] != '\0')
                    {
                        offset++;
                    }
                    
                }
            }
            offset++;
            sprintf(sms->sms_text + offset, "%c", '\0');
            break;
        }
    default:
        break;
    }
    return sms_len;
}
int destroy_sms(SMS_T *sms)
{
    if (sms->sms_pdu != NULL)
    {
        free(sms->sms_pdu);
    }
    if (sms->sender != NULL)
    {
        free(sms->sender);
    }
    if (sms->sms_text != NULL)
    {
        free(sms->sms_text);
    }
    free(sms);
    return SUCCESS;
}
int dump_sms(SMS_T *sms)
{
    dbg_msg("SMS Index: %d", sms->sms_index);
    dbg_msg("SMS Text: %s", sms->sms_text);
    dbg_msg("SMS Sender: %s", sms->sender);
    dbg_msg("SMS Timestamp: %ld", sms->timestamp);
    dbg_msg("SMS Segment: %d/%d", sms->segment_number, sms->total_segments);
    return SUCCESS;
}
int match_option(char *option_name)
{
    char short_option;
    char *long_option;
    // if start with '-' then it is an single character option
    if (option_name[0] == '-' && option_name[1] != '-')
    {

        short_option = option_name[1];
        switch (short_option)
        {
        case AT_CMD_S:
            return AT_CMD;
        case TTY_DEV_S:
            return TTY_DEV;
        case BAUD_RATE_S:
            return BAUD_RATE;
        case DATA_BITS_S:
            return DATA_BITS;
        case PARITY_S:
            return PARITY;
        case STOP_BITS_S:
            return STOP_BITS;
        case FLOW_CONTROL_S:
            return FLOW_CONTROL;
        case TIMEOUT_S:
            return TIMEOUT;
        case OPERATION_S:
            return OPERATION;
        case DEBUG_S:
            return DEBUG;
        case SMS_PDU_S:
            return SMS_PDU;
        case SMS_INDEX_S:
            return SMS_INDEX;
        case GREEDY_READ_S:
            return GREEDY_READ;
        default:
            return -1;
        }
    }
    if (option_name[0] == '-' && option_name[1] == '-')
    {
        long_option = option_name + 2;
        if (strcmp(long_option, AT_CMD_L) == 0)
        {
            return AT_CMD;
        }
        else if (strcmp(long_option, TTY_DEV_L) == 0)
        {
            return TTY_DEV;
        }
        else if (strcmp(long_option, BAUD_RATE_L) == 0)
        {
            return BAUD_RATE;
        }
        else if (strcmp(long_option, DATA_BITS_L) == 0)
        {
            return DATA_BITS;
        }
        else if (strcmp(long_option, PARITY_L) == 0)
        {
            return PARITY;
        }
        else if (strcmp(long_option, STOP_BITS_L) == 0)
        {
            return STOP_BITS;
        }
        else if (strcmp(long_option, FLOW_CONTROL_L) == 0)
        {
            return FLOW_CONTROL;
        }
        else if (strcmp(long_option, TIMEOUT_L) == 0)
        {
            return TIMEOUT;
        }
        else if (strcmp(long_option, OPERATION_L) == 0)
        {
            return OPERATION;
        }
        else if (strcmp(long_option, DEBUG_L) == 0)
        {
            return DEBUG;
        }
        else if (strcmp(long_option, SMS_PDU_L) == 0)
        {
            return SMS_PDU;
        }
        else if (strcmp(long_option, SMS_INDEX_L) == 0)
        {
            return SMS_INDEX;
        }
        else if (strcmp(long_option, GREEDY_READ_L) == 0)
        {
            return GREEDY_READ;
        }
        else
        {
            return -1;
        }
    }
    // if start with '--' then it is a long option
    return -1;
}
int match_operation(char *operation_name)
{

    char short_op;
    int opstr_len = strlen(operation_name);
    if (opstr_len == 1)
    {
        short_op = operation_name[0];
        switch (short_op)
        {
        case AT_OP_S:
            return AT_OP;
        case BINARY_AT_OP_S:
            return BINARY_AT_OP;
        case SMS_READ_OP_S:
            return SMS_READ_OP;
        case SMS_SEND_OP_S:
            return SMS_SEND_OP;
        case SMS_DELETE_OP_S:
            return SMS_DELETE_OP;
        case CLEANUP_SEMAPHORE_OP_S:
            return CLEANUP_SEMAPHORE_OP;
        default:
            return INVALID_PARAM;
            break;
        }
    }
    else if (opstr_len > 1)
    {
        if (strcmp(operation_name, AT_OP_L) == 0)
        {
            return AT_OP;
        }
        else if (strcmp(operation_name, BINARY_AT_OP_L) == 0)
        {
            return BINARY_AT_OP;
        }
        else if (strcmp(operation_name, SMS_READ_OP_L) == 0)
        {
            return SMS_READ_OP;
        }
        else if (strcmp(operation_name, SMS_SEND_OP_L) == 0)
        {
            return SMS_SEND_OP;
        }
        else if (strcmp(operation_name, SMS_DELETE_OP_L) == 0)
        {
            return SMS_DELETE_OP;
        }
        else if (strcmp(operation_name, CLEANUP_SEMAPHORE_OP_L) == 0)
        {
            return CLEANUP_SEMAPHORE_OP;
        }
        else
        {
            return INVALID_PARAM;
        }
    }
    return SUCCESS;
}
void escape_json(char *input, char *output)
{
    char *p = input;
    char *q = output;
    while (*p)
    {
        if (*p == '"')
        {
            *q++ = '\\';
            *q++ = '"';
        }
        else if (*p == '\\')
        {
            *q++ = '\\';
            *q++ = '\\';
        }
        else if (*p == '/')
        {
            *q++ = '\\';
            *q++ = '/';
        }
        else if (*p == '\b')
        {
            *q++ = '\\';
            *q++ = 'b';
        }
        else if (*p == '\f')
        {
            *q++ = '\\';
            *q++ = 'f';
        }
        else if (*p == '\n')
        {
            *q++ = '\\';
            *q++ = 'n';
        }
        else if (*p == '\r')
        {
            *q++ = '\\';
            *q++ = 'r';
        }
        else if (*p == '\t')
        {
            *q++ = '\\';
            *q++ = 't';
        }
        else
        {
            *q++ = *p;
        }
        p++;
    }
    *q = '\0';
}
int usage(char* name)
{
    err_msg("Usage: %s [options]", name);
    err_msg("Or %s [device_path] [AT command]", name);
    err_msg("Or %s [device_path] [operation]", name);
    err_msg("Options:");
    err_msg("  -c, --at_cmd <AT command>  AT command");
    err_msg("  -d, --tty_dev <TTY device>  TTY device **REQUIRED**");
    err_msg("  -b, --baud_rate <baud rate>  Baud rate Default: 115200 Supported: 4800,9600,19200,38400,57600,115200");
    err_msg("  -B, --data_bits <data bits>  Data bits Default: 8 Supported: 5,6,7,8");
    err_msg("  -t, --timeout <timeout>  Default: 3 Timeout in seconds, if output is more than timeout, it will be ignored unless -g option is set");
    err_msg("  -o, --operation <operation>  Operation(at[a:defualt],binary_at[b], sms_read[r], sms_send[s], sms_delete[d])");
    err_msg("  -D, --debug Debug mode Default: off");
    err_msg("  -p, --sms_pdu <sms pdu>  SMS PDU");
    err_msg("  -i, --sms_index <sms index>  SMS index");
    err_msg("  -g, --greedy_read Default: off, Greedy read mode, if set, each round it get new data from tty device, it will reset the timeout");
    #ifdef USE_SEMAPHORE
    err_msg("  -C, --cleanup Semaphore cleanup");
    #endif
    err_msg("Example:");
    err_msg("  %s -c ATI -d /dev/ttyUSB2 -b 115200 -B 8 -o at #advance at mode set bautrate and data bit", name);
    err_msg("  %s -c ATI -d /dev/ttyUSB2 # normal at mode", name);
    err_msg("  %s -c ATI -d /dev/ttyUSB2 -o binary_at -c 4154490D0A # means sending ATI to ttyUSB2", name);
    err_msg("  %s -d /dev/mhi_DUN -o r # read sms", name);
    #ifdef USE_SEMAPHORE
    err_msg("  %s -d /dev/mhi_DUN  -o C # force cleanup semaphore", name);
    #endif
    exit(-1);
}

int str_to_hex(char *str, char *hex)
{
    int len = strlen(str)/2;
    int high,low;
    for (int i = 0; i < len; i++)
    {
        high = char_to_hex(str[i*2]);
        low = char_to_hex(str[i*2+1]);
        if (high == -1 || low == -1)
        {
            return INVALID_HEX;
        }
        hex[i] = (high << 4) | low;
        dbg_msg("hex[%d]: %x", i, hex[i]);
    }
    return SUCCESS;
}

void dump_profile()
{
    dbg_msg("AT command: %s", s_profile.at_cmd);
    dbg_msg("TTY device: %s", s_profile.tty_dev);
    dbg_msg("Baud rate: %d", s_profile.baud_rate);
    dbg_msg("Data bits: %d", s_profile.data_bits);
    dbg_msg("Parity: %s", s_profile.parity);
    dbg_msg("Stop bits: %d", s_profile.stop_bits);
    dbg_msg("Flow control: %s", s_profile.flow_control);
    dbg_msg("Timeout: %d", s_profile.timeout);
    dbg_msg("Operation: %d", s_profile.op);
    dbg_msg("Debug: %d", s_profile.debug);
    dbg_msg("SMS PDU: %s", s_profile.sms_pdu);
    dbg_msg("SMS index: %d", s_profile.sms_index);
    dbg_msg("Greedy read: %d", s_profile.greedy_read);
}
int display_sms_in_json(SMS_T **sms,int num)
{

    char msg_json[SMS_BUF_SIZE];
    int offset;
    offset = sprintf(msg_json, "{\"msg\":[");
    for (int i = 0; i < num; i++)
    {
        char escaped_text[SMS_TEXT_SIZE];
        escape_json(sms[i]->sms_text, escaped_text);
        if (sms[i]->ref_number)
            offset += sprintf(msg_json + offset, "{\"index\":%d,\"sender\":\"%s\",\"timestamp\":%ld,\"content\":\"%s\",\"reference\":%d,\"total\":%d,\"part\":%d},",
                          sms[i]->sms_index, sms[i]->sender, sms[i]->timestamp, escaped_text, sms[i]->ref_number, sms[i]->total_segments, sms[i]->segment_number);
        else
            offset += sprintf(msg_json + offset, "{\"index\":%d,\"sender\":\"%s\",\"timestamp\":%ld,\"content\":\"%s\"},",
                          sms[i]->sms_index, sms[i]->sender, sms[i]->timestamp, escaped_text);
    }
    
    //if not empty msg_json,remove the last ','
    if (offset > 10)
    {
        offset--;
    }
    offset += sprintf(msg_json + offset, "]}");
    user_msg("%s\n", msg_json);
    return SUCCESS;

    
}
