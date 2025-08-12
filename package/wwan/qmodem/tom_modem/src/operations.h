#ifndef OPERATION_H
#define OPERATION_H
#include "modem_types.h"
#include "transport.h"
#include "utils.h"

int str_to_hex(char *str, char *hex);

// Unified operations using transport layer
int at(PROFILE_T *profile, void *transport);
int binary_at(PROFILE_T *profile, void *transport);
int sms_read(PROFILE_T *profile, void *transport);
int sms_send(PROFILE_T *profile, void *transport);
int sms_delete(PROFILE_T *profile, void *transport);

#endif
