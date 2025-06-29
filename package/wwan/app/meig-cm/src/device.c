#include <unistd.h>
#include <sys/types.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <strings.h>
#include <stdlib.h>
#include <limits.h>

#include "QMIThread.h"

#define CM_MAX_PATHLEN 256

#define CM_INVALID_VAL (~((int)0))
/* get first line from file 'fname'
 * And convert the content into a hex number, then return this number */
static int file_get_value(const char *fname)
{
    FILE *fp = NULL;
    int hexnum;
    char buff[32 + 1] = {'\0'};
    char *endptr = NULL;

    fp = fopen(fname, "r");
    if (!fp) goto error;
    if (fgets(buff, sizeof(buff), fp) == NULL)
        goto error;
    fclose(fp);

    hexnum = strtol(buff, &endptr, 16);
    if (errno == ERANGE && (hexnum == LONG_MAX || hexnum == LONG_MIN))
        goto error;
    /* if there is no digit in buff */
    if (endptr == buff)
        goto error;
    return (int)hexnum;

error:
    if (fp) fclose(fp);
    return CM_INVALID_VAL;
}

/*
 * This function will search the directory 'dirname' and return the first child.
 * '.' and '..' is ignored by default
 */
int dir_get_child(const char *dirname, char *buff, unsigned bufsize)
{
    struct dirent *entptr = NULL;
    DIR *dirptr = opendir(dirname);
    if (!dirptr)
        goto error;
    while ((entptr = readdir(dirptr))) {
        if (entptr->d_name[0] == '.')
            continue;
        snprintf(buff, bufsize, "%s", entptr->d_name);
        break;
    }

    closedir(dirptr);
    return 0;
error:
    buff[0] = '\0';
    if (dirptr) closedir(dirptr);
    return -1;
}

int conf_get_val(const char *fname, const char *key)
{
    char buff[CM_MAX_BUFF] = {'\0'};
    FILE *fp = fopen(fname, "r");
    if (!fp)
        goto error;
    
    while (fgets(buff, CM_MAX_BUFF, fp)) {
        char prefix[CM_MAX_BUFF] = {'\0'};
        char tail[CM_MAX_BUFF] = {'\0'};
        /* To eliminate cppcheck warnning: Assume string length is no more than 15 */
        sscanf(buff, "%15[^=]=%15s", prefix, tail);
        if (!strncasecmp(prefix, key, strlen(key))) {
            fclose(fp);
            return atoi(tail);
        }
    }

error:
    fclose(fp);
    return CM_INVALID_VAL;
}

/* To detect the device info of the modem.
 * return:
 *  FALSE -> fail
 *  TRUE -> ok
 */
BOOL qmidevice_detect(char *qmichannel, char *usbnet_adapter, unsigned bufsize) {
    struct dirent* ent = NULL;
    DIR *pDir;
    const char *rootdir = "/sys/bus/usb/devices";
    struct {
        char path[255*2];
        char uevent[255*3];
    } *pl;
    pl = (typeof(pl)) malloc(sizeof(*pl));
    memset(pl, 0x00, sizeof(*pl));

    pDir = opendir(rootdir);
    if (!pDir) {
        dbg_time("opendir %s failed: %s", rootdir, strerror(errno));
        goto error;
    }

    while ((ent = readdir(pDir)) != NULL)  {
        int idVendor;
        int idProduct;
        char netcard[32+1] = {'\0'};
        char device[32+1] = {'\0'};
        char devname[32+1+6] = {'\0'};

        snprintf(pl->path, sizeof(pl->path), "%s/%s/idVendor", rootdir, ent->d_name);
        idVendor = file_get_value(pl->path);

        snprintf(pl->path, sizeof(pl->path), "%s/%s/idProduct", rootdir, ent->d_name);
        idProduct = file_get_value(pl->path);

        if (idVendor != 0x05c6 && idVendor != 0x2c7c && idVendor != 0x2dee)
            continue;
        
        dbg_time("Find %s/%s idVendor=0x%x idProduct=0x%x", rootdir, ent->d_name, idVendor, idProduct);

        /* get network interface */
        snprintf(pl->path, sizeof(pl->path), "%s/%s:1.4/net", rootdir, ent->d_name);
        dir_get_child(pl->path, netcard, sizeof(netcard));
        if (netcard[0] == '\0')
            continue;

        if (usbnet_adapter[0] && strcmp(usbnet_adapter, netcard))
            continue;

        snprintf(pl->path, sizeof(pl->path), "%s/%s:1.4/GobiQMI", rootdir, ent->d_name);
        if (access(pl->path, R_OK)) {
            snprintf(pl->path, sizeof(pl->path), "%s/%s:1.4/usbmisc", rootdir, ent->d_name);
            if (access(pl->path, R_OK)) {
                snprintf(pl->path, sizeof(pl->path), "%s/%s:1.4/usb", rootdir, ent->d_name);
                if (access(pl->path, R_OK)) {
                    dbg_time("no GobiQMI/usbmic/usb found in %s/%s:1.4", rootdir, ent->d_name);
                    continue;
                }
            }
        }

        /* get device */
        dir_get_child(pl->path, device, sizeof(device));
        if (device[0] == '\0')
            continue;

        /* There is a chance that, no device(qcqmiX|cdc-wdmX) is generated. We should warn user about that! */
        snprintf(devname, sizeof(devname), "/dev/%s", device);
        if (access(devname, R_OK | F_OK) && errno == ENOENT) {
            int major;
            int minor;
            int ret;

            dbg_time("%s access failed, errno: %d (%s)", devname, errno, strerror(errno));
            snprintf(pl->uevent, sizeof(pl->uevent), "%s/%s/uevent", pl->path, device);
            major = conf_get_val(pl->uevent, "MAJOR");
            minor = conf_get_val(pl->uevent, "MINOR");
            if(major == CM_INVALID_VAL || minor == CM_INVALID_VAL)
                dbg_time("get major and minor failed");

            ret = mknod(devname, S_IFCHR|0666, (((major & 0xfff) << 8) | (minor & 0xff) | ((minor & 0xfff00) << 12)));
            if (ret)
                dbg_time("please mknod %s c %d %d", devname, major, minor);
        }

        if (netcard[0] && device[0]) {
            snprintf(qmichannel, bufsize, "/dev/%s", device);
            snprintf(usbnet_adapter, bufsize, "%s", netcard);
            dbg_time("Auto find qmichannel = %s", qmichannel);
            dbg_time("Auto find usbnet_adapter = %s", usbnet_adapter);
            break;
        }
    }
    closedir(pDir);
    
    if (qmichannel[0] == '\0' || usbnet_adapter[0] == '\0') {
        dbg_time("network interface '%s' or qmidev '%s' is not exist", usbnet_adapter, qmichannel);
        goto error;
    }

    free(pl);
    return TRUE;
error:
    free(pl);
    return FALSE;
}

#define USB_CLASS_COMM			2
#define USB_CLASS_VENDOR_SPEC		0xff
#define USB_CDC_SUBCLASS_MBIM			0x0e

/*
 * To check whether the system load the wrong driver:
 *      error1: usbnet 2(MBIM) match the QMI driver(qmi_wwan|GobiNet)
 *      error2: usbnet 0(QMI) match the MBIM driver(cdc_mbim)
 * return:
 *  0 for ok, or ignorance
 *  others for failure or error
 */
int varify_driver(PROFILE_T *profile)
{
    char path[CM_MAX_PATHLEN+1] = {'\0'};
    int bInterfaceClass = -1;
            
    snprintf(path, sizeof(path), "/sys/class/net/%s/device/bInterfaceClass", profile->usbnet_adapter);
    bInterfaceClass = file_get_value(path);

    /* QMI_WWAN */
    if (driver_is_qmi(profile->driver_name) && bInterfaceClass != USB_CLASS_VENDOR_SPEC) {
        dbg_time("module register driver %s, but at+qcfg=\"usbnet\" is not QMI mode!", profile->driver_name);
        return 1;
    }

    /* CDC_MBIM */
    if (driver_is_mbim(profile->driver_name) && bInterfaceClass != USB_CLASS_COMM) {
        dbg_time("module register driver %s, but at+qcfg=\"usbnet\" is not MBIM mode!", profile->driver_name);
        return 1;
    }
            
    return 0;
}
