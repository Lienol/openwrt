#ifndef _MAIN_H_
#define _MAIN_H_
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <termios.h>
#include <signal.h>
#include <sys/select.h>
#include <errno.h>
#include "operations.h"
#include "ttydevice.h"
#include "modem_types.h"
#include "utils.h"

#define DEFAULT_TIMEOUT 3
// 

extern PROFILE_T s_profile;   // global profile     


extern  int at(PROFILE_T *profile,FDS_T *fds);

extern int binary_at(PROFILE_T *profile,FDS_T *fds);

extern  int sms_read(PROFILE_T *profile,FDS_T *fds);

extern  int sms_send(PROFILE_T *profile,FDS_T *fds);

extern  int sms_delete(PROFILE_T *profile,FDS_T *fds);

extern void dump_profile();

extern int match_option(char *option_name);

extern int match_operation(char *operation_name);

extern int open_tty_device(PROFILE_T *profile,FDS_T *fds);

extern int usage(char* name);

#endif
