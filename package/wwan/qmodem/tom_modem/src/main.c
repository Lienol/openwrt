#include "main.h"

FDS_T s_fds;
PROFILE_T s_profile;   // global profile     

int parse_user_input(int argc, char *argv[], PROFILE_T *profile)
{
    int opt = 1;
    int anonymous_arg = 0;
    int option;
    profile->sms_index = -1;
#define has_more_argv() (opt < argc ? 1 : 0)
    while (opt < argc)
    {
        if (argv[opt][0] != '-') {
            if (anonymous_arg == 0) {
                profile->tty_dev = argv[opt];
            }
            if (anonymous_arg == 1){
                profile->at_cmd = argv[opt];
            }
            if (anonymous_arg >= 2) {
                err_msg("Too many anonymous arguments");
                return INVALID_PARAM;
            }
            anonymous_arg++;
            opt++;
            continue;
        }

        option = match_option(argv[opt]);
        if (option == -1)
        {
            usage(argv[0]);
            return INVALID_PARAM;
        }
        opt++;
        switch (option)
        {
        case AT_CMD:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->at_cmd = argv[opt++];
            break;
        case TTY_DEV:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->tty_dev = argv[opt++];
            break;
        case BAUD_RATE:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->baud_rate = atoi(argv[opt++]);
            break;
        case DATA_BITS:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->data_bits = atoi(argv[opt++]);
            break;
        case PARITY:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->parity = argv[opt++];
            break;
        case STOP_BITS:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->stop_bits = atoi(argv[opt++]);
            break;
        case FLOW_CONTROL:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->flow_control = argv[opt++];
            break;
        case TIMEOUT:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->timeout = atoi(argv[opt++]);
            break;
        case OPERATION:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->op = match_operation(argv[opt++]);
            break;
        case DEBUG:
            profile->debug = 1;
            break;
        case SMS_PDU:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->sms_pdu = argv[opt++];
            break;
        case SMS_INDEX:
            if (!has_more_argv())
            {
                usage(argv[0]);
                return INVALID_PARAM;
            }
            profile->sms_index = atoi(argv[opt++]);
            break;
        case GREEDY_READ:
            profile->greedy_read = 1;
            break;
        default:
            err_msg("Invalid option: %s", argv[opt]);
            break;
        }
    }

    // default settings:
    if (profile->tty_dev == NULL)
    {
        usage(argv[0]);
        return INVALID_PARAM;
    }
    if (profile->baud_rate == 0 )
    {
        profile->baud_rate = 115200;
    }
    if (profile->data_bits == 0)
    {
        profile->data_bits = 8;
    }
    if (profile->timeout == 0)
    {
        profile->timeout = 3;
    }
    if (profile->op == 0 || profile->op == -1)
    {
        profile->op = AT_OP;
    }
    return SUCCESS;
}
int run_op(PROFILE_T *profile,FDS_T *fds)
{
    switch (profile->op)
    {
    case AT_OP:
        return at(profile,fds);
    case BINARY_AT_OP:
        return binary_at(profile,fds);
    case SMS_READ_OP:
        return sms_read(profile,fds);
    case SMS_SEND_OP:
        return sms_send(profile,fds);
    case SMS_DELETE_OP:
        return sms_delete(profile,fds);
    default:
        err_msg("Invalid operation");
    }
    return UNKNOWN_ERROR;
}
static void clean_up()
{
#ifdef USE_SEMAPHORE
    if (unlock_at_port(s_profile.tty_dev))
    {
        err_msg("Failed to unlock tty device");
    }
#endif
    dbg_msg("Clean up success");
    if (s_fds.tty_fd >= 0)
    {
        if (tcsetattr(s_fds.tty_fd, TCSANOW, &s_fds.old_termios) != 0)
        {
            err_msg("Error restoring old tty attributes");
            return;
        }
        tcflush(s_fds.tty_fd, TCIOFLUSH);

        close(s_fds.tty_fd);
    }
}

int main(int argc, char *argv[])
{
    PROFILE_T *profile = &s_profile;
    FDS_T *fds = &s_fds;
    parse_user_input(argc, argv, profile);
    dump_profile();
    #ifdef USE_SEMAPHORE
    if (profile->op == CLEANUP_SEMAPHORE_OP)
    {
        if (unlock_at_port(profile->tty_dev))
        {
            err_msg("Failed to unlock tty device");
        }
        return SUCCESS;
    }
    if (profile->tty_dev != NULL)
    {
        if (lock_at_port(profile->tty_dev))
        {
            err_msg("Failed to lock tty device");
            return COMM_ERROR;
        }
    }
    #endif
    // try open tty devices
    atexit(clean_up);
    signal(SIGINT, clean_up);
    signal(SIGTERM, clean_up);
    if (tty_open_device(profile,fds))
    {
        err_msg("Failed to open tty device");
        return COMM_ERROR;
    }
    if (run_op(profile,fds))
    {
        err_msg("Failed to run operation %d", profile->op);
#ifdef USE_SEMAPHORE
        if (unlock_at_port(profile->tty_dev))
        {
            err_msg("Failed to unlock tty device");
        }
#endif
        kill(getpid(), SIGINT); 
    }
    
    dbg_msg("Exit");
    return SUCCESS;
}
