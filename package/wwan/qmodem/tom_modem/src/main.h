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
#include "transport.h"
#include "modem_types.h"
#include "utils.h"

#define DEFAULT_TIMEOUT 3

extern PROFILE_T s_profile;   // global profile     

// Operation dispatcher
extern int run_op(PROFILE_T *profile, void *transport);

extern void dump_profile();

extern int match_option(char *option_name);

extern int match_operation(char *operation_name);

extern int usage(char* name);

#endif
