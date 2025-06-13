#include "QMIThread.h"
#include <sys/wait.h>
#include <sys/utsname.h>
#include <sys/time.h>
#include <dirent.h>

#include "util.h"
//#define CONFIG_EXIT_WHEN_DIAL_FAILED
//#define CONFIG_BACKGROUND_WHEN_GET_IP
//#define CONFIG_PID_FILE_FORMAT "/var/run/meig-cm-%s.pid" //for example /var/run/meig-cm-wwan0.pid
#define MAJOR 1
#define MINOR 3
#define REVISION 8
/*
* Generally, we do not modify version info, so several modifications will share the same version code.
* SUBVERSION is used for customized modification to distinguise this version from previous one. 
* SUBVERSION adds up before you send the code to customers and it should be set to 0 if VERSION_STRING info is changed.
*/
#define SUBVERSION 0
#define STRINGIFY_HELPER(v) #v
#define STRINGIFY(v) STRINGIFY_HELPER(v)
#define VERSION_STRING() STRINGIFY(MAJOR) "." \
                        STRINGIFY(MINOR) "." \
                        STRINGIFY(REVISION)
int debug_qmi = 0;
int main_loop = 0;
int qmidevice_control_fd[2];
static int signal_control_fd[2];

extern const struct qmi_device_ops gobi_qmidev_ops;
extern const struct qmi_device_ops qmiwwan_qmidev_ops;
extern int meig_ifconfig(int argc, char *argv[]);

#ifdef CONFIG_BACKGROUND_WHEN_GET_IP
static int daemon_pipe_fd[2];

static void meig_prepare_daemon(void) {
    pid_t daemon_child_pid;

    if (pipe(daemon_pipe_fd) < 0) {
        dbg_time("%s Faild to create daemon_pipe_fd: %d (%s)", __func__, errno, strerror(errno));
        return;
    }

    daemon_child_pid = fork();
    if (daemon_child_pid > 0) {
        struct pollfd pollfds[] = {{daemon_pipe_fd[0], POLLIN, 0}, {0, POLLIN, 0}};
        int ne, ret, nevents = sizeof(pollfds)/sizeof(pollfds[0]);
        int signo;

        //dbg_time("father");

        close(daemon_pipe_fd[1]);

        if (socketpair( AF_LOCAL, SOCK_STREAM, 0, signal_control_fd) < 0 ) {
            dbg_time("%s Faild to create main_control_fd: %d (%s)", __func__, errno, strerror(errno));
            return;
        }

        pollfds[1].fd = signal_control_fd[1];

        while (1) {
            do {
                ret = poll(pollfds, nevents, -1);
            } while ((ret < 0) && (errno == EINTR));

            if (ret < 0) {
                dbg_time("%s poll=%d, errno: %d (%s)", __func__, ret, errno, strerror(errno));
                goto __daemon_quit;
            }

            for (ne = 0; ne < nevents; ne++) {
                int fd = pollfds[ne].fd;
                short revents = pollfds[ne].revents;

                if (revents & (POLLERR | POLLHUP | POLLNVAL)) {
                    //dbg_time("%s poll err/hup", __func__);
                    //dbg_time("poll fd = %d, events = 0x%04x", fd, revents);
                    if (revents & POLLHUP)
                        goto __daemon_quit;
                }

                if ((revents & POLLIN) &&  read(fd, &signo, sizeof(signo)) == sizeof(signo)) {
                    if (signal_control_fd[1] == fd) {
                        if (signo == SIGCHLD) {
                            int status;
                            int pid = waitpid(daemon_child_pid, &status, 0);
                            dbg_time("waitpid pid=%d, status=%x", pid, status);
                            goto __daemon_quit;
                        } else {
                            kill(daemon_child_pid, signo);
                        }
                    } else if (daemon_pipe_fd[0] == fd) {
                        //dbg_time("daemon_pipe_signo = %d", signo);
                        goto __daemon_quit;
                    }
                }
            }
        }
__daemon_quit:
        //dbg_time("father exit");
        _exit(0);
    } else if (daemon_child_pid == 0) {
        close(daemon_pipe_fd[0]);
        //dbg_time("child", getpid());
    } else {
        close(daemon_pipe_fd[0]);
        close(daemon_pipe_fd[1]);
        dbg_time("%s Faild to create daemon_child_pid: %d (%s)", __func__, errno, strerror(errno));
    }
}

static void meig_enter_daemon(int signo) {
    if (daemon_pipe_fd[1] > 0)
        if (signo) {
            write(daemon_pipe_fd[1], &signo, sizeof(signo));
            sleep(1);
        }
        close(daemon_pipe_fd[1]);
        daemon_pipe_fd[1] = -1;
        setsid();
    }
#endif

//UINT ifc_get_addr(const char *ifname);
static void usbnet_link_change(int link, PROFILE_T *profile) {
    static int s_link = -1;
    int curIpFamily = profile->enable_ipv6 ? IpFamilyV6 : IpFamilyV4;

    if (s_link == link)
        return;

    s_link = link;

    if (link) {
        requestGetIPAddress(profile, curIpFamily);
        if (profile->IsDualIPSupported)
            requestGetIPAddress(profile, IpFamilyV6);
        udhcpc_start(profile);
    } else {
        udhcpc_stop(profile);
    }

#ifdef CONFIG_BACKGROUND_WHEN_GET_IP
    if (link && daemon_pipe_fd[1] > 0) {
        int timeout = 6;
        while (timeout-- /*&& ifc_get_addr(profile->usbnet_adapter) == 0*/) {
            sleep(1);
        }
        meig_enter_daemon(SIGUSR1);
    }
#endif
}

static int check_ipv4_address(PROFILE_T *now_profile) {
    PROFILE_T new_profile_v;
    PROFILE_T *new_profile = &new_profile_v;

    memcpy(new_profile, now_profile, sizeof(PROFILE_T));
    if (requestGetIPAddress(new_profile, 0x04) == 0) {
         if (new_profile->ipv4.Address != now_profile->ipv4.Address || debug_qmi) {
             unsigned char *l = (unsigned char *)&now_profile->ipv4.Address;
             unsigned char *r = (unsigned char *)&new_profile->ipv4.Address;
             dbg_time("localIP: %d.%d.%d.%d VS remoteIP: %d.%d.%d.%d",
                     l[3], l[2], l[1], l[0], r[3], r[2], r[1], r[0]);
        }
        return (new_profile->ipv4.Address == now_profile->ipv4.Address);
    }
    return 0;
}

static void main_send_event_to_qmidevice(int triger_event) {
     write(qmidevice_control_fd[0], &triger_event, sizeof(triger_event));
}

static void send_signo_to_main(int signo) {
     write(signal_control_fd[0], &signo, sizeof(signo));
}

void qmidevice_send_event_to_main(int triger_event) {
     write(qmidevice_control_fd[1], &triger_event, sizeof(triger_event));
}

#define MAX_PATH 256

static int ls_dir(const char *dir, int (*match)(const char *dir, const char *file, void *argv[]), void *argv[])
{
    DIR *pDir;
    struct dirent* ent = NULL;
    int match_times = 0;

    pDir = opendir(dir);
    if (pDir == NULL)  {
        dbg_time("Cannot open directory: %s, errno: %d (%s)", dir, errno, strerror(errno));
        return 0;
    }

    while ((ent = readdir(pDir)) != NULL)  {
        match_times += match(dir, ent->d_name, argv);
    }
    closedir(pDir);

    return match_times;
}

static int is_same_linkfile(const char *dir, const char *file,  void *argv[])
{
    const char *qmichannel = (const char *)argv[1];
    char linkname[MAX_PATH];
    char filename[MAX_PATH];
    int linksize;

    snprintf(linkname, MAX_PATH, "%s/%s", dir, file);
    linksize = readlink(linkname, filename, MAX_PATH);
    if (linksize <= 0)
        return 0;

    filename[linksize] = 0;
    if (strcmp(filename, qmichannel))
        return 0;

    dbg_time("%s -> %s", linkname, filename);
    return 1;
}

static int is_brother_process(const char *dir, const char *file, void *argv[])
{
    //const char *myself = (const char *)argv[0];
    char linkname[MAX_PATH];
    char filename[MAX_PATH];
    int linksize;
    int i = 0, kill_timeout = 15;
    pid_t pid;

    //dbg_time("%s", file);
    while (file[i]) {
        if (!isdigit(file[i]))
            break;
        i++;
    }

    if (file[i]) {
        //dbg_time("%s not digit", file);
        return 0;
    }

    snprintf(linkname, MAX_PATH, "%s/%s/exe", dir, file);
    linksize = readlink(linkname, filename, MAX_PATH);
    if (linksize <= 0)
        return 0;

    filename[linksize] = 0;

    pid = atoi(file);
    if (pid >= getpid())
        return 0;

    snprintf(linkname, MAX_PATH, "%s/%s/fd", dir, file);
    if (!ls_dir(linkname, is_same_linkfile, argv))
        return 0;

    dbg_time("%s/%s/exe -> %s", dir, file, filename);
    while (kill_timeout-- && !kill(pid, 0))
    {
        kill(pid, SIGTERM);
        sleep(1);
    }
    if (!kill(pid, 0))
    {
        dbg_time("force kill %s/%s/exe -> %s", dir, file, filename);
        kill(pid, SIGKILL);
        sleep(1);
    }

    return 1;
}

static int kill_brothers(const char *qmichannel)
{
    char myself[MAX_PATH];
    int filenamesize;
    void *argv[2] = {myself, (void *)qmichannel};

    filenamesize = readlink("/proc/self/exe", myself, MAX_PATH);
    if (filenamesize <= 0)
        return 0;
    myself[filenamesize] = 0;

    if (ls_dir("/proc", is_brother_process, argv))
        sleep(1);

    return 0;
}

static void meig_sigaction(int signo) {
     if (SIGCHLD == signo)
         waitpid(-1, NULL, WNOHANG);
     else if (SIGALRM == signo)
         send_signo_to_main(SIGUSR1);
     else
     {
        if (SIGTERM == signo || SIGHUP == signo || SIGINT == signo)
            main_loop = 0;
         send_signo_to_main(signo);
        main_send_event_to_qmidevice(signo); //main may be wating qmi response
    }
}

pthread_t gQmiThreadID;


static int usage(const char *progname) {
     dbg_time("Usage: %s [options]", progname);
     dbg_time("-s [apn [user password auth]]          Set apn/user/password/auth get from your network provider");
     dbg_time("-p pincode                             Verify sim card pin if sim card is locked");
     dbg_time("-f logfilename                         Save log message of this program to file");
     dbg_time("-i interface                           Specify network interface(default auto-detect)");
     dbg_time("-4                                     IPv4 protocol");
     dbg_time("-6                                     IPv6 protocol");
     dbg_time("-m muxID                               Specify muxid when set multi-pdn data connection.");
     dbg_time("-n channelID                           Specify channelID when set multi-pdn data connection(default 1).");
	 dbg_time("[Examples]");
     dbg_time("Example 1: %s ", progname);
     dbg_time("Example 2: %s -s 3gnet ", progname);
     dbg_time("Example 3: %s -s 3gnet carl 1234 0 -p 1234 -f gobinet_log.txt", progname);
     return 0;
}

int qmi_main(PROFILE_T *profile)
{
    int triger_event = 0;
    int signo;
#ifdef CONFIG_SIM
    SIM_Status SIMStatus;
#endif
    UCHAR PSAttachedState;
    UCHAR  IPv4ConnectionStatus = 0xff; //unknow state
    UCHAR  IPV6ConnectionStatus = 0xff; //unknow state
    int qmierr = 0;
    char * save_usbnet_adapter = NULL;

    signal(SIGUSR1, meig_sigaction);
    signal(SIGUSR2, meig_sigaction);
    signal(SIGINT, meig_sigaction);
    signal(SIGTERM, meig_sigaction);
    signal(SIGHUP, meig_sigaction);
    signal(SIGCHLD, meig_sigaction);
    signal(SIGALRM, meig_sigaction);

#ifdef CONFIG_BACKGROUND_WHEN_GET_IP
    meig_prepare_daemon();
#endif

    if (socketpair( AF_LOCAL, SOCK_STREAM, 0, signal_control_fd) < 0 ) {
        dbg_time("%s Faild to create main_control_fd: %d (%s)", __func__, errno, strerror(errno));
        return -1;
    }

    if ( socketpair( AF_LOCAL, SOCK_STREAM, 0, qmidevice_control_fd ) < 0 ) {
        dbg_time("%s Failed to create thread control socket pair: %d (%s)", __func__, errno, strerror(errno));
        return 0;
    }

//sudo apt-get install udhcpc
//sudo apt-get remove ModemManager
__main_loop:
    while (!profile->qmichannel) {
        char qmichannel[32+1] = {'\0'};
        char usbnet_adapter[32+1] = {'\0'};
        
        if (!qmidevice_detect(qmichannel, usbnet_adapter, sizeof(qmichannel))) {
            dbg_time("qmidevice_detect failed");
            continue;
        } else {
            if (!(profile->qmichannel))
                strset(profile->qmichannel, qmichannel);
            if (!(profile->usbnet_adapter))
                strset(profile->usbnet_adapter, usbnet_adapter);
                break;
        }
        if (main_loop) {
            int wait_for_device = 3000;
            dbg_time("Wait for Meig modules connect");
            while (wait_for_device && main_loop) {
                wait_for_device -= 100;
                usleep(100*1000);
            }
            continue;
        }
        dbg_time("Cannot find qmichannel(%s) usbnet_adapter(%s) for Meig modules", profile->qmichannel, profile->usbnet_adapter);
        return -ENODEV;
    }

    if (qmidev_is_gobinet(profile->qmichannel)) {
        profile->qmi_ops = &gobi_qmidev_ops;
    }
    else {
        profile->qmi_ops = &qmiwwan_qmidev_ops;
    }
    qmidev_send = profile->qmi_ops->send;
    meig_qmap_mode_detect(profile);
    dbg_time("[zpf]qmap_mode=%d", profile->qmap_mode);
    if (profile->qmap_mode == 0 || profile->qmap_mode == 1)
        kill_brothers(profile->qmichannel);

    if (pthread_create( &gQmiThreadID, 0, profile->qmi_ops->read, (void *)profile) != 0) {
        dbg_time("%s Failed to create QMIThread: %d (%s)", __func__, errno, strerror(errno));
            return 0;
    }

    if ((read(qmidevice_control_fd[0], &triger_event, sizeof(triger_event)) != sizeof(triger_event))
        || (triger_event != RIL_INDICATE_DEVICE_CONNECTED)) {
        dbg_time("%s Failed to init QMIThread: %d (%s)", __func__, errno, strerror(errno));
        return 0;
    }

    if (profile->qmi_ops->init && profile->qmi_ops->init(profile)) {
        dbg_time("%s Failed to qmi init: %d (%s)", __func__, errno, strerror(errno));
            return 0;
    }

#ifdef CONFIG_VERSION
    requestBaseBandVersion(NULL);
#endif
    requestSetEthMode(profile);
#ifdef CONFIG_SIM
    qmierr = requestGetSIMStatus(&SIMStatus);
    while (qmierr == QMI_ERR_OP_DEVICE_UNSUPPORTED) {
        sleep(1);
        qmierr = requestGetSIMStatus(&SIMStatus);
    }
    if ((SIMStatus == SIM_PIN) && profile->pincode) {
        requestEnterSimPin(profile->pincode);
    }
#ifdef CONFIG_IMSI_ICCID
    if (SIMStatus == SIM_READY) {
        requestGetICCID();
        requestGetIMSI();
   }
#endif
#endif
#ifdef CONFIG_APN
    if (profile->apn || profile->user || profile->password) {
        requestSetProfile(profile);
    }
    requestGetProfile(profile);
#endif
    requestRegistrationState(&PSAttachedState);

    if (!requestQueryDataCall(&IPv4ConnectionStatus, IpFamilyV4) && (QWDS_PKT_DATA_CONNECTED == IPv4ConnectionStatus)){
        usbnet_link_change(1, profile);
     } else
        usbnet_link_change(0, profile);

    send_signo_to_main(SIGUSR1);

#ifdef CONFIG_PID_FILE_FORMAT
    {
        char cmd[255];
        sprintf(cmd, "echo %d > " CONFIG_PID_FILE_FORMAT, getpid(), profile->usbnet_adapter);
        system(cmd);
    }
#endif

    while (1)
    {
        struct pollfd pollfds[] = {{signal_control_fd[1], POLLIN, 0}, {qmidevice_control_fd[0], POLLIN, 0}};
        int ne, ret, nevents = sizeof(pollfds)/sizeof(pollfds[0]);
		UCHAR *pConnectionStatus = (profile->enable_ipv6) ? &IPV6ConnectionStatus : &IPv4ConnectionStatus;
		int curIpFamily = (profile->enable_ipv6) ? IpFamilyV6 : IpFamilyV4;

        do {
            ret = poll(pollfds, nevents,  15*1000);
        } while ((ret < 0) && (errno == EINTR));

        if (ret == 0)
        {
            send_signo_to_main(SIGUSR2);
            continue;
        }

        if (ret <= 0) {
            dbg_time("%s poll=%d, errno: %d (%s)", __func__, ret, errno, strerror(errno));
            goto __main_quit;
        }

        for (ne = 0; ne < nevents; ne++) {
            int fd = pollfds[ne].fd;
            short revents = pollfds[ne].revents;

            if (revents & (POLLERR | POLLHUP | POLLNVAL)) {
                dbg_time("%s poll err/hup", __func__);
                dbg_time("epoll fd = %d, events = 0x%04x", fd, revents);
                main_send_event_to_qmidevice(RIL_REQUEST_QUIT);
                if (revents & POLLHUP)
                    goto __main_quit;
            }

            if ((revents & POLLIN) == 0)
                continue;

            if (fd == signal_control_fd[1])
            {
                if (read(fd, &signo, sizeof(signo)) == sizeof(signo))
                {
                    alarm(0);
                    switch (signo)
                    {
                        case SIGUSR1:
                            requestQueryDataCall(pConnectionStatus, curIpFamily);
                            if (QWDS_PKT_DATA_CONNECTED != *pConnectionStatus)
                            {
                                usbnet_link_change(0, profile);
                                requestRegistrationState(&PSAttachedState);

                                if (PSAttachedState == 1) {
                                    qmierr = requestSetupDataCall(profile, curIpFamily);

                                    if ((qmierr > 0) && profile->user && profile->user[0] && profile->password && profile->password[0]) {
                                        int old_auto =  profile->auth;

                                        //may be fail because wrong auth mode, try pap->chap, or chap->pap
                                        profile->auth = (profile->auth == 1) ? 2 : 1;
                                        qmierr = requestSetupDataCall(profile, curIpFamily);

                                        if (qmierr)
                                            profile->auth = old_auto; //still fail, restore old auth moe
                                    }

                                    //succssful setup data call
                                    if (!qmierr && profile->IsDualIPSupported) {
                                        requestSetupDataCall(profile, IpFamilyV6);
                                    }

                                    if (!qmierr)
                                        continue;
                                }
                                
#ifdef CONFIG_EXIT_WHEN_DIAL_FAILED
                                kill(getpid(), SIGTERM);
#endif
                                alarm(5); //try to setup data call 5 seconds later
                            }
                        break;

                        case SIGUSR2:
                            if (QWDS_PKT_DATA_CONNECTED == *pConnectionStatus)
                                 requestQueryDataCall(pConnectionStatus, curIpFamily);

                            //local ip is different with remote ip
                            if (QWDS_PKT_DATA_CONNECTED == IPv4ConnectionStatus && check_ipv4_address(profile) == 0) {
                                requestDeactivateDefaultPDP(profile, curIpFamily);
                                *pConnectionStatus = QWDS_PKT_DATA_DISCONNECTED;
                            }
                            
                            if (QWDS_PKT_DATA_CONNECTED != *pConnectionStatus)
                                send_signo_to_main(SIGUSR1);
                        break;

                        case SIGTERM:
                        case SIGHUP:
                        case SIGINT:
                            if (QWDS_PKT_DATA_CONNECTED == *pConnectionStatus) {
                                requestDeactivateDefaultPDP(profile, curIpFamily);
                                if (profile->IsDualIPSupported)
                                    requestDeactivateDefaultPDP(profile, IpFamilyV6);
                           }
                            usbnet_link_change(0, profile);
                            if (profile->qmi_ops->deinit)
                                profile->qmi_ops->deinit();
                            main_send_event_to_qmidevice(RIL_REQUEST_QUIT);
                            goto __main_quit;
                        break;

                        default:
                        break;
                    }
                }
            }

            if (fd == qmidevice_control_fd[0]) {
                if (read(fd, &triger_event, sizeof(triger_event)) == sizeof(triger_event)) {
                    switch (triger_event) {
                        case RIL_INDICATE_DEVICE_DISCONNECTED:
                            usbnet_link_change(0, profile);
                            if (main_loop)
                            {
                                if (pthread_join(gQmiThreadID, NULL)) {
                                    dbg_time("%s Error joining to listener thread (%s)", __func__, strerror(errno));
                                }
                                profile->qmichannel = NULL;
                                profile->usbnet_adapter = save_usbnet_adapter;
                                goto __main_loop;
                            }
                            goto __main_quit;
                        break;

                        case RIL_UNSOL_RESPONSE_VOICE_NETWORK_STATE_CHANGED:
                            requestRegistrationState(&PSAttachedState);
                            if (PSAttachedState == 1 && QWDS_PKT_DATA_DISCONNECTED == *pConnectionStatus)
                                send_signo_to_main(SIGUSR1);
                        break;

                        case RIL_UNSOL_DATA_CALL_LIST_CHANGED:
                        {
                            UCHAR oldConnectionStatus = *pConnectionStatus;
                            requestQueryDataCall(pConnectionStatus, curIpFamily);
                            if (profile->IsDualIPSupported)
                                requestQueryDataCall(&IPV6ConnectionStatus, IpFamilyV6);
                            if (QWDS_PKT_DATA_CONNECTED != *pConnectionStatus)
                            {
                                usbnet_link_change(0, profile);
                                //connected change to disconnect
                                if (oldConnectionStatus == QWDS_PKT_DATA_CONNECTED)
                                    send_signo_to_main(SIGUSR1);
                            } else if (QWDS_PKT_DATA_CONNECTED == *pConnectionStatus) {
                                usbnet_link_change(1, profile);
                                if (oldConnectionStatus == QWDS_PKT_DATA_CONNECTED) { //receive two CONNECT IND?
                                    send_signo_to_main(SIGUSR2);
                                }
                            }
                        }
                        break;

                        default:
                        break;
                    }
                }
            }
        }
    }

__main_quit:
    usbnet_link_change(0, profile);
    if (pthread_join(gQmiThreadID, NULL)) {
        dbg_time("%s Error joining to listener thread (%s)", __func__, strerror(errno));
    }
    close(signal_control_fd[0]);
    close(signal_control_fd[1]);
    close(qmidevice_control_fd[0]);
    close(qmidevice_control_fd[1]);
    dbg_time("%s exit", __func__);
    if (logfilefp)
        fclose(logfilefp);

#ifdef CONFIG_PID_FILE_FORMAT
    {
        char cmd[255];
        sprintf(cmd, "rm  " CONFIG_PID_FILE_FORMAT, profile.usbnet_adapter);
        system(cmd);
    }
#endif

    return 0;
}

#define has_more_argv() ((opt < argc) && (argv[opt][0] != '-'))
int main(int argc, char *argv[])
{
    int opt = 1;
    char * save_usbnet_adapter = NULL;
    PROFILE_T profile;

    dbg_time("Meig_QConnectManager_Linux_V%s", VERSION_STRING());
    memset(&profile, 0x00, sizeof(profile));
    profile.pdp = CONFIG_DEFAULT_PDP;

    if (!strcmp(argv[argc-1], "&"))
        argc--;

    opt = 1;
    while  (opt < argc) {
        if (argv[opt][0] != '-')
            return usage(argv[0]);

        switch (argv[opt++][1])
        {
            case 's':
                profile.apn = profile.user = profile.password = "";
                if (has_more_argv())
                    profile.apn = argv[opt++];
                if (has_more_argv())
                    profile.user = argv[opt++];
                if (has_more_argv())
                {
                    profile.password = argv[opt++];
                    if (profile.password && profile.password[0])
                        profile.auth = 2; //default chap, customers may miss auth
                }
                if (has_more_argv())
                    profile.auth = argv[opt++][0] - '0';
            break;

            case 'm':
                if (has_more_argv())
                    profile.muxid = argv[opt++][0] - '0';
                break;

            case 'p':
                if (has_more_argv())
                    profile.pincode = argv[opt++];
            break;

            case 'n':
                if (has_more_argv())
                    profile.pdp = argv[opt++][0] - '0';
            break;

            case 'f':
                if (has_more_argv())
                {
                    const char * filename = argv[opt++];
                    logfilefp = fopen(filename, "a+");
                    if (!logfilefp) {
                        dbg_time("Fail to open %s, errno: %d(%s)", filename, errno, strerror(errno));
                     }
                }
            break;

            case 'i':
                if (has_more_argv())
                    profile.usbnet_adapter = save_usbnet_adapter = argv[opt++];
            break;

            case 'v':
                debug_qmi = 1;
            break;

            case 'l':
                main_loop = 1;
            break;

            case '4':
                profile.ipv4_flag = 1; 
            break;

            case '6':
                profile.ipv6_flag = 1;
            break;

            case 'd':
                if (has_more_argv()) {
                    profile.qmichannel = argv[opt++];
                    if (qmidev_is_pciemhi(profile.qmichannel))
                        profile.usbnet_adapter = "mhi0.1";
                }
            break;

            default:
                return usage(argv[0]);
            break;
        }
    }

    if (profile.ipv4_flag == 1 && profile.ipv6_flag == 1) {
        profile.IsDualIPSupported |= (1 << IpFamilyV6);	
    } else if (profile.ipv6_flag) {
        profile.enable_ipv6 = 1;
    }
    
    if (profile.ipv4_flag != 1 && profile.ipv6_flag != 1) { // default enable IPv4
        profile.ipv4_flag = 1;
    }

    if (!(profile.qmichannel) || !(profile.usbnet_adapter)) {
        char qmichannel[32+1] = {'\0'};
        char usbnet_adapter[32+1] = {'\0'};

        if (profile.usbnet_adapter)
            strcpy(usbnet_adapter, profile.usbnet_adapter);
        
        if (!qmidevice_detect(qmichannel, usbnet_adapter, sizeof(qmichannel))) {
            dbg_time("qmidevice_detect failed");
            goto error;
        }
        if (!(profile.qmichannel))
            strset(profile.qmichannel, qmichannel);
        if (!(profile.usbnet_adapter))
            strset(profile.usbnet_adapter, usbnet_adapter);
    }
    
    meig_qmap_mode_detect(&profile);
    if (varify_driver(&profile))
        return -1;

    if (driver_is_mbim(profile.driver_name) || !strncmp(profile.qmichannel, "/dev/mhi_MBIM", strlen("/dev/mhi_MBIM"))) {
        dbg_time("Modem works in MBIM mode");
        return mbim_main(&profile);
    } else {
        dbg_time("Modem works in QMI mode");
        return qmi_main(&profile);
    }

error:
    return -1;
}
