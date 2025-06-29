#include "main.h"

PROFILE_T s_profile;   // global profile
transport_t s_transport; // global transport

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
        case USE_UBUS:
#ifdef ENABLE_UBUS_DAEMON
            profile->transport = TRANSPORT_UBUS;
#else
            err_msg("UBUS daemon support not compiled in");
            return INVALID_PARAM;
#endif
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
    
    // Default transport is TTY
    if (profile->transport != TRANSPORT_UBUS)
    {
        profile->transport = TRANSPORT_TTY;
    }
    
    return SUCCESS;
}

int run_op(PROFILE_T *profile, void *transport)
{
    int ret;
    switch (profile->op)
    {
    case AT_OP:
        return at(profile, transport);
    case BINARY_AT_OP:
        return binary_at(profile, transport);
    case SMS_READ_OP:
        return sms_read(profile, transport);
    case SMS_SEND_OP:
        ret = sms_send(profile, transport);
        switch (ret)
        {
        case SUCCESS:
            printf("{\"status\":\"success\"}");
            break;
        case SEND_SMS_FAILED:
            printf("{\"status\":\"failed\",\"reason\":\"send_sms_failed\"}");
            break;
        case INVALID_PARAM:
            printf("{\"status\":\"failed\",\"reason\":\"invalid_param\"}");
            break;
        case COMM_ERROR:
            printf("{\"status\":\"failed\",\"reason\":\"comm_error\"}");
            break;
        default:
            printf("{\"status\":\"failed\",\"reason\":\"unknown_error\"}");
            break;
        }
        return ret;
    case SMS_DELETE_OP:
        return sms_delete(profile, transport);
    case SMS_UNREAD_OP:
        return sms_read_unread(profile, transport);
    case SMS_MARK_READ_OP:
        return sms_mark_read(profile, transport);
    default:
        err_msg("Invalid operation");
    }
    return UNKNOWN_ERROR;
}

static void clean_up(int sig __attribute__((unused)))
{
    dbg_msg("Clean up success");
    
    // Cleanup transport
    transport_cleanup(&s_transport);
    
#ifdef USE_SEMAPHORE
    if (s_profile.transport == TRANSPORT_TTY && unlock_at_port(s_profile.tty_dev))
    {
        err_msg("Failed to unlock tty device");
    }
#endif
}

static void atexit_cleanup(void)
{
    clean_up(0);
}

static void signal_cleanup(int sig __attribute__((unused)))
{
    clean_up(sig);
}

int main(int argc, char *argv[])
{
    PROFILE_T *profile = &s_profile;
    parse_user_input(argc, argv, profile);
    dump_profile();
    
    // Initialize transport layer
    if (transport_init(&s_transport, profile->transport) != SUCCESS) {
        err_msg("Failed to initialize transport layer");
        return COMM_ERROR;
    }
    
    // Setup cleanup and signal handlers
    atexit(atexit_cleanup);
    signal(SIGINT, signal_cleanup);
    signal(SIGTERM, signal_cleanup);
    
#ifdef USE_SEMAPHORE
    if (profile->op == CLEANUP_SEMAPHORE_OP)
    {
        if (unlock_at_port(profile->tty_dev))
        {
            err_msg("Failed to unlock tty device");
        }
        return SUCCESS;
    }
    
    // Only use semaphore locking for TTY transport
    if (profile->transport == TRANSPORT_TTY && profile->tty_dev != NULL)
    {
        if (lock_at_port(profile->tty_dev))
        {
            err_msg("Failed to lock tty device");
            return COMM_ERROR;
        }
    }
#endif
    
    // Open device
    if (transport_open_device(&s_transport, profile) != SUCCESS)
    {
        err_msg("Failed to open device");
        return COMM_ERROR;
    }
    
    // Run operation
    if (run_op(profile, &s_transport))
    {
        err_msg("Failed to run operation %d", profile->op);
#ifdef USE_SEMAPHORE
        if (profile->transport == TRANSPORT_TTY && unlock_at_port(profile->tty_dev))
        {
            err_msg("Failed to unlock tty device");
        }
#endif
        kill(getpid(), SIGINT); 
    }
    
    dbg_msg("Exit");
    return SUCCESS;
}
