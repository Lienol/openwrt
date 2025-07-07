/*
    Copyright 2023 Quectel Wireless Solutions Co.,Ltd

    Quectel hereby grants customers of Quectel a license to use, modify,
    distribute and publish the Software in binary form provided that
    customers shall have no right to reverse engineer, reverse assemble,
    decompile or reduce to source code form any portion of the Software.
    Under no circumstances may customers modify, demonstrate, use, deliver
    or disclose any portion of the Software in source code form.
*/

#include <getopt.h>
#include <grp.h>
#include <sys/types.h>
#include <pwd.h>
#ifdef USE_IPC_MSG
#include <sys/msg.h>
#include <sys/ipc.h>
#endif

#include "usb_linux.h"
#include "md5.h"

/*
[PATCH 3.10 27/54] usb: xhci: Add support for URB_ZERO_PACKET to bulk/sg transfers
https://www.spinics.net/lists/kernel/msg2100618.html

commit 4758dcd19a7d9ba9610b38fecb93f65f56f86346
Author: Reyad Attiyat <reyad.attiyat@gmail.com>
Date:   Thu Aug 6 19:23:58 2015 +0300

    usb: xhci: Add support for URB_ZERO_PACKET to bulk/sg transfers

    This commit checks for the URB_ZERO_PACKET flag and creates an extra
    zero-length td if the urb transfer length is a multiple of the endpoint's
    max packet length.
*/
unsigned qusb_zlp_mode = 1; // MT7621 donot support USB ZERO PACKET
unsigned q_erase_all_before_download = 0;
unsigned q_module_packet_sign = 0;
unsigned int g_from_ecm_to_rndis = 0;
const char *q_device_type = "nand"; // nand/emmc/ufs
int sahara_main(const char *firehose_dir, const char *firehose_mbn, void *usb_handle, int edl_mode_05c69008);
int firehose_main(const char *firehose_dir, void *usb_handle, unsigned qusb_zlp_mode);
int stream_download(const char *firehose_dir, void *usb_handle, unsigned qusb_zlp_mode);
int retrieve_soft_revision(void *usb_handle, uint8_t *mobile_software_revision, unsigned length);
int usb2tcp_main(const void *usb_handle, int tcp_port, unsigned qusb_zlp_mode);
int ql_capture_usbmon_log(const char *usbmon_logfile);
void ql_stop_usbmon_log();

// process vals
static long long all_bytes_to_transfer = 0; // need transfered
static long long transfer_bytes = 0;        // transfered bytes;

char zip_cmd_buf[512] = {0}; // zip cmd buf
char firehose_zip_name[80] = {0};
char firehose_unzip_full_dir[256] = {0};
file_name_backup file_name_b;
int is_upgrade_fimeware_zip_7z = 0;
int is_firehose_zip_7z_name_exit = 0;
int is_upgrade_fimeware_only_zip = 0;
int g_is_module_adb_entry_edl = 0;

int g_is2mdn_path = 0;

int switch_to_edl_mode(void *usb_handle)
{
    // DIAG commands used to switch the Qualcomm devices to EDL (Emergency download mode)
    unsigned char edl_cmd[] = {0x4b, 0x65, 0x01, 0x00, 0x54, 0x0f, 0x7e};
    // unsigned char edl_cmd[] = {0x3a, 0xa1, 0x6e, 0x7e}; //DL (download mode)
    unsigned char *pbuf = malloc(512);
    if (pbuf == NULL)
    {
        return 0;
    }

    int rx_len;
    int rx_count = 0;

    do
    {
        rx_len = qusb_noblock_read(usb_handle, pbuf, 512, 0, 1000);
        if (rx_count++ > 100) break;
    } while (rx_len > 0);

    dbg_time("switch to 'Emergency download mode'\n");
    rx_len = qusb_noblock_write(usb_handle, edl_cmd, sizeof(edl_cmd), sizeof(edl_cmd), 3000, 0);
    if (rx_len < 0) return 0;

    rx_count = 0;

    do
    {
        rx_len = qusb_noblock_read(usb_handle, pbuf, 512, 0, 3000);
        if (rx_len == sizeof(edl_cmd) && memcmp(pbuf, edl_cmd, sizeof(edl_cmd)) == 0)
        {
            dbg_time("successful, wait module reboot\n");
            safe_free(pbuf);
            return 1;
        }

        if (rx_count++ > 50) break;

    } while (rx_len > 0);

    safe_free(pbuf);
    return 0;
}

int switch_to_edl_mode_in_adb_way()
{
    printf("entry switch_to_edl_mode_in_adb_way \r\n");
    int res = -1;
    res = system("adb shell lxc-power1 adb host");
    // if (res == 127)
    // {
    //     printf("call /bin/sh return error \r\n");
    //     return res;
    // }
    // else if (res == -1)
    // {
    //     printf("just return: error \r\n");
    //     return res;
    // }
    // else if (res == 0)
    // {
    //     printf("no child pid create: error \r\n");
    //     return res;
    // }

    printf("send lxc power1 success res=[%d] \r\n", res);
    sleep(20);
    res = system("adb reboot edl");
    // if (res == 127)
    // {
    //     printf("call /bin/sh return error \r\n");
    //     return res;
    // }
    // else if (res == -1)
    // {
    //     printf("just return: error \r\n");
    //     return res;
    // }
    // else if (res == 0)
    // {
    //     printf("no child pid create: error \r\n");
    //     return res;
    // }

    printf("send reboot edl success res=[%d] \r\n", res);
    return 0;
}

static void usage(int status, const char *program_name)
{
    if (status != EXIT_SUCCESS)
    {
        printf("Try '%s --help' for more information.\n", program_name);
    }
    else
    {
        dbg_time("Upgrade Quectel's modules with Qualcomm's firehose protocol.\n");
        dbg_time("Usage: %s [options...]\n", program_name);
        dbg_time("    -f [package_dir]               Upgrade package directory path\n");
        dbg_time("    -p [/dev/ttyUSBx]              Diagnose port, will auto-detect if not "
                 "specified\n");
        dbg_time("    -s [/sys/bus/usb/devices/xx]   When multiple modules exist on the board, use "
                 "-s specify which module you want to upgrade\n");
        dbg_time("    -l [dir_name]                  Sync log into a file(will create "
                 "qfirehose_timestamp.log)\n");
        dbg_time("    -u [usbmon_log]                Catch usbmon log and save to file (need "
                 "debugfs and usbmon driver)\n");
        dbg_time("    -n                             Skip MD5 check\n");
        dbg_time("    -d                             Device Type, default nand, support emmc/ufs\n");
        dbg_time("    -v                             For AG215S-GLR signed firmware packages\n");
    }
    exit(status);
}

/*
1. enum dir, fix up dirhose_dir
2. md5 examine
3. furture
*/
static char *find_firehose_mbn(char **firehose_dir, size_t size)
{
    char *firehose_mbn = NULL;

    if (is_upgrade_fimeware_zip_7z)
    {
        int i;
        char file_name_prog[128] = {0};
        char file_name_prog_dir[256] = {0};

        firehose_mbn = (char *)malloc(256);
        if (firehose_mbn == NULL)
        {
            return NULL;
        }

        for (i = 0; i < file_name_b.file_name_count; i++)
        {
            if ((strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "prog_nand_firehose_") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".mbn")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "prog_emmc_firehose_") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".mbn")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "prog_firehose_") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".mbn")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "prog_firehose_") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".elf")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "firehose-prog") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".mbn")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "prog_") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".mbn")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "xbl_s_devprg_Qcm8550_ns") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".melf")) ||
                (strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "xbl_s_devprg_ns_SA52X") && strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".melf")))
            {
                printf("file_name_b.file_backup_c[i].zip_file_name_backup:%s\n", file_name_b.file_backup_c[i].zip_file_name_backup);
                printf("file_name_b.file_backup_c[i].zip_file_dir_backup:%s\n", file_name_b.file_backup_c[i].zip_file_dir_backup);

                if (strstr(file_name_b.file_backup_c[i].zip_file_dir_backup, "update/firehose"))
                {
                    memmove(file_name_prog, file_name_b.file_backup_c[i].zip_file_name_backup, strlen(file_name_b.file_backup_c[i].zip_file_name_backup));
                    memmove(file_name_prog_dir, file_name_b.file_backup_c[i].zip_file_dir_backup, strlen(file_name_b.file_backup_c[i].zip_file_dir_backup));
                    break;
                }
            }
        }

        if (file_name_prog[0] != '\0')
        {
            memset(zip_cmd_buf, 0, sizeof(zip_cmd_buf));
            if (is_upgrade_fimeware_only_zip)
            {
                snprintf(zip_cmd_buf, sizeof(zip_cmd_buf), "unzip -o -q %.240s '*%.200s' -d /tmp/ > %s", *firehose_dir, file_name_prog_dir, ZIP_PROCESS_INFO);
            }
            else
            {
                snprintf(zip_cmd_buf, sizeof(zip_cmd_buf), "7z x %.240s -o/tmp/ %.200s > %s", *firehose_dir, file_name_prog_dir, ZIP_PROCESS_INFO);
            }
            printf("%s zip_cmd_buf:%s\n", __func__, zip_cmd_buf);
            if (-1 == system(zip_cmd_buf))
            {
                printf("%s system return error\n", __func__);
                return NULL;
            }
            usleep(1000);

            memmove(firehose_mbn, file_name_prog_dir, 240);
        }
    }
    else
    {
        if (strstr(*firehose_dir, "/update/firehose") == NULL)
        {
            size_t len = strlen(*firehose_dir);

            strncat(*firehose_dir, "/update/firehose", size);
            if (access(*firehose_dir, R_OK))
            {
                (*firehose_dir)[len] = '\0'; // for smart module
            }
        }

        if (access(*firehose_dir, R_OK))
        {
            dbg_time("%s access(%s fail), errno: %d (%s)\n", __func__, *firehose_dir, errno, strerror(errno));
            return NULL;
        }

        if (!qfile_find_file(*firehose_dir, "prog_nand_firehose_", ".mbn", &firehose_mbn) && !qfile_find_file(*firehose_dir, "prog_emmc_firehose_", ".mbn", &firehose_mbn) &&
            !qfile_find_file(*firehose_dir, "prog_firehose_", ".mbn", &firehose_mbn) && !qfile_find_file(*firehose_dir, "prog_firehose_", ".elf", &firehose_mbn) &&
            !qfile_find_file(*firehose_dir, "firehose-prog", ".mbn", &firehose_mbn) && !qfile_find_file(*firehose_dir, "prog_", ".mbn", &firehose_mbn) &&
            !qfile_find_file(*firehose_dir, "xbl_s_devprg_Qcm8550_ns", ".melf",
                             &firehose_mbn) // smart  SA885GAPNA
            && !qfile_find_file(*firehose_dir, "xbl_s_devprg_ns_SA52X", ".melf",
                                &firehose_mbn) // AG590ECNABR01A01M8G_OCPU_01.001.01
        )
        {
            dbg_time("%s fail to find firehose mbn file in %s\n", __func__, *firehose_dir);
            safe_free(firehose_mbn);
            return NULL;
        }
    }

    dbg_time("%s %s\n", __func__, firehose_mbn);
    return firehose_mbn;
}

#if 0
static int detect_and_judge_module_version(void *usb_handle) {
    static uint8_t version[64] = {'\0'};

    if (usb_handle && version[0] == '\0') {
        retrieve_soft_revision(usb_handle, version, sizeof(version));
        if (version[0]) {
            size_t i = 0;
            size_t length = strlen((const char *)version) - strlen("R00A00");
            dbg_time("old software version: %s\n", version);
            for (i = 0; i < length; i++) {
                if (version[i] == 'R' && isdigit(version[i+1]) &&  isdigit(version[i+2])
                    && version[i+3] == 'A'  && isdigit(version[i+4]) &&  isdigit(version[i+5]))
                {
                    version[i] = '\0';
                    //dbg_time("old hardware version: %s\n", mobile_software_revision);
                    break;
                }
            }
        }
    }

    if (version[0])
        return 0;

    error_return();
}
#endif

FILE *loghandler = NULL;
#ifdef FIREHOSE_ENABLE
int firehose_main_entry(int argc, char *argv[])
#else
int main(int argc, char *argv[])
#endif
{
    int opt;
    int check_hash = 1;
    int retval;
    void *usb_handle = NULL;
    int idVendor = 0, idProduct = 0, interfaceNum = 0;
    int edl_retry = 30; // SDX55 require long time by now 20190412
    double start;

    // char *firehose_mbn = NULL;
    int usb3_speed;
    struct timespec usb3_atime;
    int usb2tcp_port = 0;
    char filename[128] = {'\0'};
    char *usbmon_logfile = NULL;

    char *file_message = malloc(MAX_PATH);
    if (file_message == NULL)
    {
        return -1;
    }

    char *firehose_mbn = malloc(MAX_PATH);
    if (firehose_mbn == NULL)
    {
        safe_free(file_message);
        return -1;
    }

    char *firehose_dir = malloc(MAX_PATH);
    if (firehose_dir == NULL)
    {
        safe_free(file_message);
        safe_free(firehose_mbn);
        return -1;
    }

    char *module_port_name = malloc(MAX_PATH);
    if (module_port_name == NULL)
    {
        safe_free(file_message);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        return -1;
    }

    char *module_sys_path = malloc(MAX_PATH);
    if (module_sys_path == NULL)
    {
        safe_free(file_message);
        safe_free(module_port_name);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        return -1;
    }

    memset(firehose_dir, 0, MAX_PATH);
    memset(module_port_name, 0, MAX_PATH);
    memset(module_sys_path, 0, MAX_PATH);

    // firehose_dir[0] = module_port_name[0] = module_sys_path[0] = '\0';

    /* set file priviledge mask 0 */
    umask(0);
    /*build V1.0.8*/
    dbg_time("Version: QFirehose_Linux_Android_V1.4.21\n"); // when release,
                                                            // rename to V1.X
#ifndef __clang__
    dbg_time("Builded: %s %s\n", __DATE__, __TIME__);
#endif

#ifdef ANDROID
    struct passwd *pd;
    pd = getpwuid(getuid());
    dbg_time("------------------\n");
    dbg_time("User:\t %s\n", pd->pw_name);
    struct group *group;
    group = getgrgid(pd->pw_gid);
    dbg_time("Group:\t %s\n", group->gr_name);
    dbg_time("------------------\n");
#if 0 // not all customers need this function
    loghandler = fopen("/data/upgrade.log", "w+");
#endif
    if (loghandler) dbg_time("upgrade log will be sync to /data/upgrade.log\n");
#endif

    optind = 1;
    while (-1 != (opt = getopt(argc, argv, "f:p:z:s:l:u:d:nevhr")))
    {
        switch (opt)
        {
            case 'n': check_hash = 0; break;
            case 'l':
                if (loghandler) fclose(loghandler);
                snprintf(filename, sizeof(filename), "%.80s/qfirehose_%lu.log", optarg, time(NULL));
                loghandler = fopen(filename, "w+");
                if (loghandler) dbg_time("upgrade log will be sync to %s\n", filename);
                break;
            case 'f': {
                strncpy(file_message, optarg, MAX_PATH - 1);
                if (strstr(file_message, ".mbn") != NULL || strstr(file_message, ".elf") != NULL)
                {
                    g_is2mdn_path = 1;
                    char *tmp = strrchr(file_message, '/');
                    strncpy(firehose_mbn, tmp + 1, strlen(tmp) - 1);
                    strncpy(firehose_dir, file_message, strlen(file_message) - strlen(tmp));
                    dbg_time("f pargram: "
                             "g_is2mdn_path=[%d],file_message=[%s],firehose_mbn=[%s],"
                             "firehose_dir=[%s]\n",
                             g_is2mdn_path, file_message, firehose_mbn, firehose_dir);
                    break;
                }
                strncpy(firehose_dir, file_message, strlen(file_message));
                break;
            }
            case 'p':
                strncpy(module_port_name, optarg, MAX_PATH - 1);
                if (!strcmp(module_port_name, "9008"))
                {
                    usb2tcp_port = atoi(module_port_name);
                    module_port_name[0] = '\0';
                }
                break;
            case 's':
                strncpy(module_sys_path, optarg, MAX_PATH - 1);
                int len = strlen(optarg);
                if (len > 256)
                {
                    safe_free(module_port_name);
                    safe_free(module_sys_path);
                    safe_free(usbmon_logfile);
                    safe_free(firehose_dir);
                    safe_free(file_message);
                    safe_free(firehose_mbn);
                    printf("optarg length is longer than 256\n");
                    return -1;
                }

                if (module_sys_path[strlen(optarg) - 1] == '/') module_sys_path[strlen(optarg) - 1] = '\0';
                break;
            case 'z': qusb_zlp_mode = !!atoi(optarg); break;
            case 'e': q_erase_all_before_download = 1; break;
            case 'u':
                usbmon_logfile = strdup(optarg);
                if (usbmon_logfile == NULL)
                {
                    printf("usbmon_logfile is NULL\n");
                    return -1;
                }
                break;
            case 'd':
                q_device_type = strdup(optarg);
                if (q_device_type == NULL)
                {
                    printf("q_device_type is NULL\n");
                    return -1;
                }
                break;
            case 'v': q_module_packet_sign = 1; break;
            case 'r':
                g_from_ecm_to_rndis = 1;
                printf("will use rndis mode [%d]\r\n", g_from_ecm_to_rndis);
                break;
            case 'h': usage(EXIT_SUCCESS, argv[0]); break;
            default: break;
        }
    }

    if (usbmon_logfile) ql_capture_usbmon_log(usbmon_logfile);

    update_transfer_bytes(0);
    if (usb2tcp_port) goto _usb2tcp_start;

    if (firehose_dir[0] == '\0')
    {
        usage(EXIT_SUCCESS, argv[0]);
        update_transfer_bytes(-1);
        error_return();
    }

    if (access(firehose_dir, R_OK))
    {
        dbg_time("fail to access %s, errno: %d (%s)\n", firehose_dir, errno, strerror(errno));
        update_transfer_bytes(-1);
        safe_free(firehose_dir);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(file_message);
        safe_free(firehose_mbn);
        error_return();
    }

    opt = strlen(firehose_dir);
    if (firehose_dir[opt - 1] == '/')
    {
        firehose_dir[opt - 1] = '\0';
    }

    char buff[256] = {0};
    int file_name_count = 0;

    if (strstr(firehose_dir, ".zip") || strstr(firehose_dir, ".7z"))
    {
        if (strstr(firehose_dir, ".zip"))
        {
            is_upgrade_fimeware_only_zip = 1;
        }

        unlink(ZIP_INFO);
        memset(zip_cmd_buf, 0, sizeof(zip_cmd_buf));
        if (is_upgrade_fimeware_only_zip)
        {
            snprintf(zip_cmd_buf, sizeof(zip_cmd_buf), "unzip -l -q %.240s > %s", firehose_dir, ZIP_INFO);
        }
        else
        {
            snprintf(zip_cmd_buf, sizeof(zip_cmd_buf), "7z l %.240s > %s", firehose_dir, ZIP_INFO);
        }
        if (-1 == system(zip_cmd_buf))
        {
            dbg_time("%s system return error\n", __func__);
            return -1;
        }
        usleep(1000);

        char *p = strrchr(firehose_dir, '/'); // firehose_dir is the absolute path of the zip/7z
                                              // file
        if (p)
        {
            if (strstr(firehose_dir, ".zip"))
            {
                strncpy(firehose_zip_name, p + 1, strlen(p) - 4 - 1); // 4(.zip); 1(/)
            }
            else
            {
                strncpy(firehose_zip_name, p + 1, strlen(p) - 3 - 1); // 3(.7z); 1(/)
            }
        }
        else
        {
            if (strstr(firehose_dir, ".zip"))
            {
                strncpy(firehose_zip_name, firehose_dir,
                        strlen(firehose_dir) - 4); // QFirehose -f RG520NEUDCR01A01M4G_01.001.01.001.zip
            }
            else
            {
                strncpy(firehose_zip_name, firehose_dir,
                        strlen(firehose_dir) - 3); // QFirehose -f RG520NEUDCR01A01M4G_01.001.01.001.7z
            }
        }

        dbg_time("firehose_zip_name:%s\n", firehose_zip_name); // RG520NEUDCR01A01M4G_01.001.01.001
        is_upgrade_fimeware_zip_7z = 1;                        // Judging as a zip/7z package upgrade

        if (!access(ZIP_INFO, F_OK))
        {
            char *p0 = NULL;
            char *p01 = NULL;
            char *p1 = NULL;
            char *p2 = NULL;
            char *p3 = NULL;
            char *p4 = NULL;
            FILE *fp = fopen(ZIP_INFO, "rb");
            if (fp == NULL)
            {
                dbg_time("fail to fopen(%s), error: %d (%s)\n", ZIP_INFO, errno, strerror(errno));
                return -1;
            }

            while (fgets(buff, sizeof(buff), fp))
            {
                p0 = strstr(buff, firehose_zip_name);
                if (p0)
                {
                    int length_debug1 = strlen(p0);
                    if (p0[length_debug1 - 1] == 0x0a) length_debug1 -= 1;

                    memmove(file_name_b.file_backup_c[file_name_count].zip_file_dir_backup, p0, length_debug1);

                    p01 = strrchr(p0, '/');
                    if (p01 == NULL) continue;

                    if (p01[0] == '/' && p01[1] == '\0')
                    {
                        continue;
                    }

                    is_firehose_zip_7z_name_exit = 1; // Determine which type of package it is and whether it should be placed
                                                      // in one folder or several files or folders after decompression

                    int length_debug = strlen(p01);
                    if (p01[length_debug - 1] == 0x0a) length_debug -= 1;

                    memmove(file_name_b.file_backup_c[file_name_count].zip_file_name_backup, p01 + 1, length_debug - 1);

                    file_name_count++;
                    file_name_b.file_name_count = file_name_count;
                }
                else
                {
                    p1 = strstr(buff, "contents.xml");
                    p2 = strstr(buff, "md5.txt");
                    p3 = strstr(buff, "update");

                    if (p1)
                    {
                        int length_debug1 = strlen(p1);
                        if (p1[length_debug1 - 1] == 0x0a) length_debug1 -= 1;

                        memmove(file_name_b.file_backup_c[file_name_count].zip_file_dir_backup, p1, length_debug1);

                        int length_debug = strlen(p1);
                        if (p1[length_debug - 1] == 0x0a) length_debug -= 1;

                        memmove(file_name_b.file_backup_c[file_name_count].zip_file_name_backup, p1 + 1, length_debug - 1);

                        file_name_count++;
                        file_name_b.file_name_count = file_name_count;
                    }
                    else if (p2)
                    {
                        int length_debug1 = strlen(p2);
                        if (p2[length_debug1 - 1] == 0x0a) length_debug1 -= 1;

                        memmove(file_name_b.file_backup_c[file_name_count].zip_file_dir_backup, p2, length_debug1);

                        int length_debug = strlen(p2);
                        if (p2[length_debug - 1] == 0x0a) length_debug -= 1;

                        memmove(file_name_b.file_backup_c[file_name_count].zip_file_name_backup, p2 + 1, length_debug - 1);

                        file_name_count++;
                        file_name_b.file_name_count = file_name_count;
                    }
                    else if (p3)
                    {
                        int length_debug1 = strlen(p3);
                        if (p3[length_debug1 - 1] == 0x0a) length_debug1 -= 1;

                        memmove(file_name_b.file_backup_c[file_name_count].zip_file_dir_backup, p3, length_debug1);

                        p4 = strrchr(p3, '/');
                        if (p4 == NULL) continue;

                        if (p4[0] == '/' && p4[1] == '\0')
                        {
                            dbg_time("continue..\n");
                            continue;
                        }

                        int length_debug = strlen(p4);
                        if (p4[length_debug - 1] == 0x0a) length_debug -= 1;

                        memmove(file_name_b.file_backup_c[file_name_count].zip_file_name_backup, p4 + 1, length_debug - 1);

                        file_name_count++;
                        file_name_b.file_name_count = file_name_count;
                    }
                }
            }

            fclose(fp);
            unlink(ZIP_INFO);

            if (!is_firehose_zip_7z_name_exit)
            {
                memset(firehose_zip_name, 0, sizeof(firehose_zip_name));
            }

            if (firehose_zip_name[0] == '\0')
            {
                strcpy(firehose_unzip_full_dir, "/tmp");
            }
            else
            {
                snprintf(firehose_unzip_full_dir, sizeof(firehose_unzip_full_dir), "/tmp/%.76s", firehose_zip_name);
            }

            dbg_time("%s firehose_unzip_full_dir:%s\n", __func__, firehose_unzip_full_dir);
        }
    }

    if (check_hash && md5_check(firehose_dir))
    {
        update_transfer_bytes(-1);
        safe_free(firehose_dir);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(file_message);
        safe_free(firehose_mbn);
        error_return();
    }

    if (!g_is2mdn_path) firehose_mbn = find_firehose_mbn(&firehose_dir, MAX_PATH);
    dbg_time("%s %s\n", __func__, firehose_mbn);
    if (!firehose_mbn)
    {
        update_transfer_bytes(-1);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        error_return();
    }

    if (module_port_name[0] && !strncmp(module_port_name, "/dev/mhi", strlen("/dev/mhi")))
    {
        if (qpcie_open(firehose_dir, firehose_mbn, module_port_name))
        {
            update_transfer_bytes(-1);
            safe_free(module_port_name);
            safe_free(module_sys_path);
            safe_free(usbmon_logfile);
            safe_free(firehose_dir);
            safe_free(file_message);
            safe_free(firehose_mbn);
            error_return();
        }

        usb_handle = &edl_pcie_mhifd;
        start = get_now();
        goto __firehose_main;
    }
    else if (module_port_name[0] && strstr(module_port_name, ":9008"))
    {
        strcpy(module_sys_path, module_port_name);
        goto __edl_retry;
    }

_usb2tcp_start:
    if (module_sys_path[0] && access(module_sys_path, R_OK))
    {
        dbg_time("fail to access %s, errno: %d (%s)\n", module_sys_path, errno, strerror(errno));
        update_transfer_bytes(-1);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        error_return();
    }

    if (module_port_name[0] && access(module_port_name, R_OK | W_OK))
    {
        dbg_time("fail to access %s, errno: %d (%s)\n", module_port_name, errno, strerror(errno));
        update_transfer_bytes(-1);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        error_return();
    }

    if (module_sys_path[0] == '\0' && module_port_name[0] != '\0')
    {
        // get sys path by port name
        quectel_get_syspath_name_by_ttyport(module_port_name, module_sys_path, MAX_PATH);
    }

    g_is_module_adb_entry_edl = 0;

    if (module_sys_path[0] == '\0')
    {
        int module_count = auto_find_quectel_modules(module_sys_path, MAX_PATH, NULL, NULL);
        if (module_count <= 0)
        {
            dbg_time("Quectel module not found\n");
            update_transfer_bytes(-1);
            safe_free(module_port_name);
            safe_free(module_sys_path);
            safe_free(usbmon_logfile);
            safe_free(firehose_dir);
            safe_free(file_message);
            safe_free(firehose_mbn);
            error_return();
        }
        else if (module_count == 1)
        {
            if (g_is_module_adb_entry_edl > 0)
            {
                switch_to_edl_mode_in_adb_way();
            }
        }
        else
        {
            dbg_time("There are multiple quectel modules in system, Please use <-s "
                     "/sys/bus/usb/devices/xx> specify which module you want to "
                     "upgrade!\n");
            dbg_time("The module's </sys/bus/usb/devices/xx> path was printed in the "
                     "previous log!\n");
            update_transfer_bytes(-1);
            safe_free(module_port_name);
            safe_free(module_sys_path);
            safe_free(usbmon_logfile);
            safe_free(firehose_dir);
            safe_free(file_message);
            safe_free(firehose_mbn);
            error_return();
        }
    }

__edl_retry:
    qusb_read_speed_atime(module_sys_path, &usb3_atime, &usb3_speed);
    while (edl_retry-- > 0)
    {
        usb_handle = qusb_noblock_open(module_sys_path, &idVendor, &idProduct, &interfaceNum);

        if (usb_handle)
        {
            clock_gettime(CLOCK_REALTIME, &usb3_atime);
        }
        else
        {
            sleep(1); // in reset sate, wait connect
            if (usb3_speed >= 5000 && access(module_sys_path, R_OK) && errno_nodev())
            {
                if (auto_find_quectel_modules(module_sys_path, MAX_PATH, "5c6/9008/", &usb3_atime) > 1)
                {
                    dbg_time("There are multiple quectel EDL modules in system!\n");
                    update_transfer_bytes(-1);
                    safe_free(module_port_name);
                    safe_free(module_sys_path);
                    safe_free(usbmon_logfile);
                    safe_free(firehose_dir);
                    safe_free(file_message);
                    safe_free(firehose_mbn);
                    error_return();
                }
            }
            continue;
        }

#if 0
        if (idVendor == 0x2c7c && interfaceNum > 1) {
            if (detect_and_judge_module_version(usb_handle)) {
                // update_transfer_bytes(-1);
                /* do not return here, this command will fail when modem is not ready */
                // error_return();
            }
        }
#endif

        if (interfaceNum == 1)
        {
            if ((idVendor == 0x2C7C) && (idProduct == 0x0800))
            {
                // although 5G module stay in dump mode, after send edl command, it also
                // can enter edl mode
                dbg_time("5G module stay in dump mode!\n");
            }
            else
            {
                break;
            }
            dbg_time("something went wrong???, why only one interface left\n");
        }

        switch_to_edl_mode(usb_handle);
        qusb_noblock_close(usb_handle);
        usb_handle = NULL;
        sleep(1); // wait usb disconnect and re-connect
    }

    if (usb_handle == NULL)
    {
        update_transfer_bytes(-1);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        error_return();
    }

    if (usb2tcp_port)
    {
        retval = usb2tcp_main(usb_handle, usb2tcp_port, qusb_zlp_mode);
        qusb_noblock_close(usb_handle);
        safe_free(module_port_name);
        safe_free(module_sys_path);
        safe_free(usbmon_logfile);
        safe_free(firehose_dir);
        safe_free(file_message);
        safe_free(firehose_mbn);
        return retval;
    }

    start = get_now();
    retval = sahara_main(firehose_dir, firehose_mbn, usb_handle, idVendor == 0x05c6);

    if (!retval)
    {
        if (idVendor != 0x05C6)
        {
            sleep(1);
            stream_download(firehose_dir, usb_handle, qusb_zlp_mode);
            qusb_noblock_close(usb_handle);
            sleep(10); // EM05-G switching to download mode is slow and increases the waiting time
                       // to 10 seconds
            goto __edl_retry;
        }

    __firehose_main:
        retval = firehose_main(firehose_dir, usb_handle, qusb_zlp_mode);
        if (retval == 0)
        {
            get_duration(start);
        }
    }

    qusb_noblock_close(usb_handle);

    safe_free(firehose_dir);
    safe_free(module_port_name);
    safe_free(module_sys_path);
    safe_free(file_message);
    safe_free(firehose_mbn);

    dbg_time("Upgrade module %s.\n", retval == 0 ? "successfully" : "failed");
    if (loghandler) fclose(loghandler);
    if (retval) update_transfer_bytes(-1);
    if (usbmon_logfile) ql_stop_usbmon_log();
    unlink(ZIP_PROCESS_INFO);

    return retval;
}

double get_now()
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1000000;
}

void get_duration(double start) { dbg_time("THE TOTAL DOWNLOAD TIME IS %.3f s\n", (get_now() - start)); }

void set_transfer_allbytes(long long bytes)
{
    transfer_bytes = 0;
    all_bytes_to_transfer = bytes;
}

int update_progress_msg(int percent);
int update_progress_file(int percent);
/*
return percent
*/
int update_transfer_bytes(long long bytes_cur)
{
    static int last_percent = -1;
    int percent = 0;

    if (bytes_cur == -1 || bytes_cur == 0)
    {
        percent = bytes_cur;
    }
    else
    {
        transfer_bytes += bytes_cur;
        percent = (transfer_bytes * 100) / all_bytes_to_transfer;
    }

    if (percent != last_percent)
    {
        last_percent = percent;
#ifdef USE_IPC_FILE
        update_progress_file(percent);
#endif
#ifdef USE_IPC_MSG
        update_progress_msg(percent);
#endif
    }

    return percent;
}

void show_progress()
{
    static int percent = 0;

    if (all_bytes_to_transfer) percent = (transfer_bytes * 100) / all_bytes_to_transfer;
    dbg_time("upgrade progress %d%% %lld/%lld\n", percent, transfer_bytes, all_bytes_to_transfer);
}

#ifdef USE_IPC_FILE
#define IPC_FILE_ANDROID "/data/update.conf"
#define IPC_FILE_LINUX "/tmp/update.conf"
int update_progress_file(int percent)
{
    static int ipcfd = -1;
    char buff[16];

    if (ipcfd < 0)
    {
#ifdef ANDROID
        const char *ipc_file = IPC_FILE_ANDROID;
#else
        const char *ipc_file = IPC_FILE_LINUX;
#endif
        /* Have set umask previous, no need to call fchmod */
        ipcfd = open(ipc_file, O_TRUNC | O_CREAT | O_WRONLY | O_NONBLOCK, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
        if (ipcfd < 0)
        {
            dbg_time("Fail to open(O_WRONLY) %s: %s\n", ipc_file, strerror(errno));
            return -1;
        }
    }

    lseek(ipcfd, 0, SEEK_SET);
    snprintf(buff, sizeof(buff), "%d", percent);
    if (write(ipcfd, buff, strlen(buff)) < 0) dbg_time("fail to write upgrade progress into %s: %s\n", ipc_file, strerror(errno));

    if (percent == 100 || percent < 0) close(ipcfd);
    return 0;
}
#endif

#ifdef USE_IPC_MSG
#define MSGBUFFSZ 16
struct message
{
    long mtype;
    char mtext[MSGBUFFSZ];
};

#define MSG_FILE "/etc/passwd"
#define MSG_TYPE_IPC 1
static int msg_get()
{
    key_t key = ftok(MSG_FILE, 'a');
    int msgid = msgget(key, IPC_CREAT | 0644);

    if (msgid < 0)
    {
        dbg_time("msgget fail: key %d, %s\n", key, strerror(errno));
        return -1;
    }
    return msgid;
}

static int msg_rm(int msgid) { return msgctl(msgid, IPC_RMID, 0); }

static int msg_send(int msgid, long type, const char *msg)
{
    struct message info;
    info.mtype = type;
    snprintf(info.mtext, MSGBUFFSZ, "%s", msg);
    if (msgsnd(msgid, (void *)&info, MSGBUFFSZ, IPC_NOWAIT) < 0)
    {
        dbg_time("msgsnd faild: msg %s, %s\n", msg, strerror(errno));
        return -1;
    }
    return 0;
}

static int msg_recv(int msgid, struct message *info)
{
    if (msgrcv(msgid, (void *)info, MSGBUFFSZ, info->mtype, IPC_NOWAIT) < 0)
    {
        dbg_time("msgrcv faild: type %ld, %s\n", info->mtype, strerror(errno));
        return -1;
    }
    return 0;
}

/**
 * this function will not delete the msg queue
 */
int update_progress_msg(int percent)
{
    char buff[MSGBUFFSZ];
    int msgid = msg_get();
    if (msgid < 0) return -1;
    snprintf(buff, sizeof(buff), "%d", percent);

#ifndef IPC_TEST
    return msg_send(msgid, MSG_TYPE_IPC, buff);
#else
    msg_send(msgid, MSG_TYPE_IPC, buff);
    struct message info;
    info.mtype = MSG_TYPE_IPC;
    msg_recv(msgid, &info);
    printf("msg queue read: %s\n", info.mtext);
#endif
}
#endif
