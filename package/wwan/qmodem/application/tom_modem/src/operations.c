#include "operations.h"

int at(PROFILE_T *profile, void *transport_ptr)
{
    transport_t *transport = (transport_t *)transport_ptr;
    char *response_text = NULL;
    
    if (profile->at_cmd == NULL)
    {
        err_msg("AT command is empty");
        return INVALID_PARAM;
    }
    
    int result = transport_send_at_with_response(transport, profile, profile->at_cmd, NULL, 0, &response_text);
    
    if (response_text) {
        user_msg("%s", response_text);
        free(response_text);
    }
    
    return result;
}

int binary_at(PROFILE_T *profile, void *transport_ptr)
{
    transport_t *transport = (transport_t *)transport_ptr;
    char *response_text = NULL;
    
    if (profile->at_cmd == NULL)
    {
        err_msg("AT command is empty");
        return INVALID_PARAM;
    }

    if (strlen(profile->at_cmd) % 2 != 0)
    {
        err_msg("Invalid AT command length");
        return INVALID_PARAM;
    }
    
    // Send as raw hex command
    int result = transport_send_at_with_response(transport, profile, profile->at_cmd, "OK", 1, &response_text);
    
    if (response_text) {
        user_msg("%s", response_text);
        free(response_text);
    }
    
    return result;
}

int sms_delete(PROFILE_T *profile, void *transport_ptr)
{
    transport_t *transport = (transport_t *)transport_ptr;
    
    if (profile->sms_index < 0)
    {
        err_msg("SMS index is empty");
        return INVALID_PARAM;
    }
    
    char delete_sms_cmd[32];
    snprintf(delete_sms_cmd, 32, DELETE_SMS, profile->sms_index);
    
    int result = transport_send_at_with_response(transport, profile, delete_sms_cmd, "OK", 0, NULL);
    
    if (result != SUCCESS) {
        dbg_msg("Error deleting SMS, error code: %d", result);
    }
    
    return result;
}

int sms_read(PROFILE_T *profile, void *transport_ptr)
{
    transport_t *transport = (transport_t *)transport_ptr;
    SMS_T *sms_list[SMS_LIST_SIZE];
    SMS_T *sms;
    char *response_text = NULL;
    int result;

    // Set PDU format
    result = transport_send_at_with_response(transport, profile, SET_PDU_FORMAT, "OK", 0, NULL);
    if (result != SUCCESS)
    {
        dbg_msg("Error setting PDU format, error code: %d", result);
        return result;
    }
    dbg_msg("Set PDU format success");

    // Read all SMS
    result = transport_send_at_with_response(transport, profile, READ_ALL_SMS, "OK", 0, &response_text);
    if (result != SUCCESS)
    {
        dbg_msg("Error reading SMS, error code: %d", result);
        return result;
    }

    if (response_text)
    {
        char *line = strtok(response_text, "\n");
        int sms_count = 0;
        char *pdu;

        while (line != NULL)
        {
            if (strncmp(line, "+CMGL:", 6) == 0)
            {
                sms = (SMS_T *)malloc(sizeof(SMS_T));
                memset(sms, 0, sizeof(SMS_T));
                
                pdu = strtok(NULL, "\n");
                if (pdu == NULL || strlen(pdu) < 3) {
                    dbg_msg("No PDU found for line: %s", line);
                    pdu = strtok(NULL, "\n");
                }
                sms->sms_pdu = (char *)malloc(strlen(pdu));
                sms->sender = (char *)malloc(PHONE_NUMBER_SIZE);
                sms->sms_text = (char *)malloc(SMS_TEXT_SIZE);
                memset(sms->sms_text, 0, SMS_TEXT_SIZE);
                sms->sms_index = get_sms_index(line);
                memcpy(sms->sms_pdu, pdu, strlen(pdu));
                int sms_len = decode_pdu(sms);
                if (sms_len > 0)
                {
                    sms_list[sms_count] = sms;
                    sms_count++;
                }
                else
                {
                    dbg_msg("Error decoding SMS in line: %s", line);
                    destroy_sms(sms);
                }
            }
            line = strtok(NULL, "\n");

        }

        display_sms_in_json(sms_list, sms_count);
        free(response_text);
    }

    dbg_msg("Read SMS success");
    return SUCCESS;
}

int sms_send(PROFILE_T *profile, void *transport_ptr) 
{
    transport_t *transport = (transport_t *)transport_ptr;
    
    if (profile->sms_pdu == NULL) {
        err_msg("SMS PDU is empty");
        return INVALID_PARAM;
    }

    int pdu_len = strlen(profile->sms_pdu);
    int pdu_expected_len = (pdu_len) / 2 - 1;
    char send_sms_cmd[32];
    char pdu_hex[512];
    char send_sms_cmd2[514];
    char *send_sms_response = NULL;
    int result;
    int ascii_code;
    
    // Set PDU format
    result = transport_send_at_with_response(transport, profile, SET_PDU_FORMAT, "OK", 0, NULL);
    if (result != SUCCESS) {
        dbg_msg("Error setting PDU format, error code: %d", result);
        return result;
    }
    dbg_msg("Set PDU format success");

    snprintf(send_sms_cmd, 32, SEND_SMS, pdu_expected_len);
    for (int i = 0; i < pdu_len; i++) {
        //将字符串转换成字符串对应的十六进制的字符串
        ascii_code = profile->sms_pdu[i];
        snprintf(pdu_hex + (i * 2), 3, "%02X", ascii_code);
    }
    pdu_hex[pdu_len * 2] = '\0'; // Add the end of transmission character
    snprintf(send_sms_cmd2, 514, "%s%s", pdu_hex, "1A"); // Append Ctrl+Z to indicate end of SMS

    // Send first AT command and wait for > prompt
    transport_send_at_only(transport, profile, send_sms_cmd, 0);
    dbg_msg("Send SMS command: %s", send_sms_cmd);
    dbg_msg("Write PDU command: %s", send_sms_cmd2);
    usleep(10000); // 10ms delay

    // Send PDU data and wait for +CMGS response
    result = transport_send_at_with_response(transport, profile, send_sms_cmd2, "+CMGS:", 1, &send_sms_response);
    if (result != SUCCESS) {
        dbg_msg("Error sending SMS PDU, error code: %d", result);
        return result;
    }
    // Check send SMS response (contain +CME ERROR or +CMS ERROR indicates failure and contain OK indicates success)
    dbg_msg("Send SMS response: %s", send_sms_response);
    if (strstr(send_sms_response, "ERROR") != NULL) {
        dbg_msg("Error sending SMS, response: %s", send_sms_response);
        free(send_sms_response);
        return SEND_SMS_FAILED;
    }
    free(send_sms_response);
    return SUCCESS;
}

int sms_read_unread(PROFILE_T *profile, void *transport_ptr)
{
    transport_t *transport = (transport_t *)transport_ptr;
    SMS_T *sms_list[SMS_LIST_SIZE];
    SMS_T *sms;
    char *response_text = NULL;
    int result;

    // Set PDU format
    result = transport_send_at_with_response(transport, profile, SET_PDU_FORMAT, "OK", 0, NULL);
    if (result != SUCCESS)
    {
        dbg_msg("Error setting PDU format, error code: %d", result);
        return result;
    }
    dbg_msg("Set PDU format success");

    // Read unread SMS only
    result = transport_send_at_with_response(transport, profile, READ_UNREAD_SMS, "OK", 0, &response_text);
    if (result != SUCCESS)
    {
        dbg_msg("Error reading unread SMS, error code: %d", result);
        return result;
    }

    if (response_text)
    {
        char *line = strtok(response_text, "\n");
        int sms_count = 0;
        char *pdu;
        while (line != NULL)
        {
            if (strncmp(line, "+CMGL:", 6) == 0)
            {
                sms = (SMS_T *)malloc(sizeof(SMS_T));
                memset(sms, 0, sizeof(SMS_T));
                pdu = strtok(NULL, "\n");
                if (pdu == NULL || strlen(pdu) < 3) {
                    dbg_msg("No PDU found for line: %s", line);
                    pdu = strtok(NULL, "\n");
                }
                sms->sms_pdu = (char *)malloc(strlen(pdu));
                sms->sender = (char *)malloc(PHONE_NUMBER_SIZE);
                sms->sms_text = (char *)malloc(SMS_TEXT_SIZE);
                memset(sms->sms_text, 0, SMS_TEXT_SIZE);
                sms->sms_index = get_sms_index(line);
                memcpy(sms->sms_pdu, pdu, strlen(pdu));
                int sms_len = decode_pdu(sms);
                if (sms_len > 0)
                {
                    sms_list[sms_count] = sms;
                    sms_count++;
                }
                else
                {
                    dbg_msg("Error decoding SMS in line: %s", line);
                    destroy_sms(sms);
                }
            }
            line = strtok(NULL, "\n");
        }

        display_sms_in_json(sms_list, sms_count);
        free(response_text);
    }

    dbg_msg("Read unread SMS success");
    return SUCCESS;
}

int sms_mark_read(PROFILE_T *profile, void *transport_ptr)
{
    transport_t *transport = (transport_t *)transport_ptr;
    char mark_read_cmd[64];
    int result;

    if (profile->sms_index < 0)
    {
        err_msg("SMS index not specified");
        return INVALID_PARAM;
    }

    // Set PDU format
    result = transport_send_at_with_response(transport, profile, SET_PDU_FORMAT, "OK", 0, NULL);
    if (result != SUCCESS)
    {
        dbg_msg("Error setting PDU format, error code: %d", result);
        return result;
    }

    // Mark SMS as read by reading it
    snprintf(mark_read_cmd, 64, MARK_SMS_READ, profile->sms_index);
    result = transport_send_at_with_response(transport, profile, mark_read_cmd, "OK", 0, NULL);
    if (result != SUCCESS)
    {
        dbg_msg("Error marking SMS as read, error code: %d", result);
        return result;
    }

    dbg_msg("SMS %d marked as read", profile->sms_index);
    return SUCCESS;
}
