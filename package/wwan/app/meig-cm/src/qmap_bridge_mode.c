#include "QMIThread.h"

static size_t meig_fread(const char *filename, void *buf, size_t size) {
    FILE *fp = fopen(filename , "r");
    size_t n = 0;

    memset(buf, 0x00, size);

    if (fp) {
        n = fread(buf, 1, size, fp);
        if (n <= 0 || n == size) {
            dbg_time("warnning: fail to fread(%s), fread=%zu, buf_size=%zu: (%s)", filename, n, size, strerror(errno));
        }
        fclose(fp);
    }

    return n > 0 ? n : 0;
}

static size_t meig_fwrite(const char *filename, const void *buf, size_t size) {
    FILE *fp = fopen(filename , "w");
    size_t n = 0;

    if (fp) {
        n = fwrite(buf, 1, size, fp);
        if (n != size) {
            dbg_time("warnning: fail to fwrite(%s), fwrite=%zu, buf_size=%zu: (%s)", filename, n, size, strerror(errno));
        }
        fclose(fp);
    }

    return n > 0 ? n : 0;
}

static int meig_iface_is_in_bridge(const char *iface) {
    char filename[256];

    snprintf(filename, sizeof(filename), "/sys/class/net/%s/brport", iface);
    return (access(filename, F_OK) == 0 || errno != ENOENT);    
}

int meig_bridge_mode_detect(PROFILE_T *profile) {
    const char *ifname = profile->qmapnet_adapter ? profile->qmapnet_adapter : profile->usbnet_adapter;
    const char *driver;
    char bridge_mode[128];
    char bridge_ipv4[128];
    char ipv4[128];
    char buf[64];
    size_t n;
    int in_bridge;

    driver = profile->driver_name;
    snprintf(bridge_mode, sizeof(bridge_mode), "/sys/class/net/%s/bridge_mode", ifname);
    snprintf(bridge_ipv4, sizeof(bridge_ipv4), "/sys/class/net/%s/bridge_ipv4", ifname);
    
    if (access(bridge_mode, F_OK) && errno == ENOENT) {
        snprintf(bridge_mode, sizeof(bridge_mode), "/sys/module/%s/parameters/bridge_mode", driver);
        snprintf(bridge_ipv4, sizeof(bridge_ipv4), "/sys/module/%s/parameters/bridge_ipv4", driver);
        
       if (access(bridge_mode, F_OK) && errno == ENOENT) {
            bridge_mode[0] = '\0';
        }
    }

    in_bridge = meig_iface_is_in_bridge(ifname);
    if (in_bridge) {
        dbg_time("notice: iface %s had add to bridge\n", ifname);   
    } else {
        return 0;
    }

    if (in_bridge && bridge_mode[0] == '\0') {
        dbg_time("warnning: can not find bride_mode file for %s\n", ifname);
        return 1;
    }

    n = meig_fread(bridge_mode, buf, sizeof(buf));
    
    if (in_bridge) {
        if (n <= 0 || buf[0] == '0') {
            dbg_time("warnning: should set 1 to bride_mode file for %s\n", ifname);
            return 1;
        }
    }
    else {
        if (buf[0] == '0') {
            return 0;
        }
    }
    
    memset(ipv4, 0, sizeof(ipv4));

    if (strstr(bridge_ipv4, "/sys/class/net/") || profile->qmap_mode == 0 || profile->qmap_mode == 1) {
        snprintf(ipv4, sizeof(ipv4), "0x%x", profile->ipv4.Address);
        dbg_time("echo '%s' > %s", ipv4, bridge_ipv4);
        meig_fwrite(bridge_ipv4, ipv4, strlen(ipv4));
    }
    else {
        snprintf(ipv4, sizeof(ipv4), "0x%x:%d", profile->ipv4.Address, profile->muxid);
        dbg_time("echo '%s' > %s", ipv4, bridge_ipv4);
        meig_fwrite(bridge_ipv4, ipv4, strlen(ipv4));
    }

    return 1;
}

int meig_enable_qmi_wwan_rawip_mode(PROFILE_T *profile) {
    char filename[256];
    char buf[4];
    size_t n;
    FILE *fp;

    if (!qmidev_is_qmiwwan(profile->qmichannel))
        return 0;

    snprintf(filename, sizeof(filename), "/sys/class/net/%s/qmi/rawip", profile->usbnet_adapter);
    n = meig_fread(filename, buf, sizeof(buf));

    if (n == 0)
        return 0;

    if (buf[0] == '1' || buf[0] == 'Y')
        return 0;

    fp = fopen(filename , "w");
    if (fp == NULL) {
        dbg_time("Fail to fopen(%s, \"w\"), errno: %d (%s)", filename, errno, strerror(errno));
        return 1;
    }

    buf[0] = 'Y';
    n = fwrite(buf, 1, 1, fp);
    if (n != 1) {
        dbg_time("Fail to fwrite(%s), errno: %d (%s)", filename, errno, strerror(errno));
        fclose(fp);
        return 1;
    }
    fclose(fp);

    return 0;
}

int meig_driver_type_detect(PROFILE_T *profile) {
    if (qmidev_is_gobinet(profile->qmichannel)) {
        profile->qmi_ops = &gobi_qmidev_ops;
    }
    else {
        profile->qmi_ops = &qmiwwan_qmidev_ops;
    }
    qmidev_send = profile->qmi_ops->send;

    return 0;
}

int meig_qmap_mode_detect(PROFILE_T *profile) {
    char buf[128];
    int n;
    char qmap_netcard[128];
    struct {
        char filename[255 * 2];
        char linkname[255 * 2];
    } *pl;
    
    pl = (typeof(pl)) malloc(sizeof(*pl));

    snprintf(pl->linkname, sizeof(pl->linkname), "/sys/class/net/%s/device/driver", profile->usbnet_adapter);
    n = readlink(pl->linkname, pl->filename, sizeof(pl->filename));
    pl->filename[n] = '\0';
    while (pl->filename[n] != '/')
        n--;
    strset(profile->driver_name, &pl->filename[n+1]);

    if (qmidev_is_gobinet(profile->qmichannel))
    {
        snprintf(pl->filename, sizeof(pl->filename), "/sys/class/net/%s/qmap_mode", profile->usbnet_adapter);

        n = meig_fread(pl->filename, buf, sizeof(buf));
        if (n > 0) {
            profile->qmap_mode = atoi(buf);
            
            if (profile->qmap_mode > 1) {
                profile->muxid = profile->pdp + 0x80; //muxis is 0x8X for PDN-X
                sprintf(qmap_netcard, "%s.%d", profile->usbnet_adapter, profile->pdp);
                profile->qmapnet_adapter = strdup(qmap_netcard);
           } if (profile->qmap_mode == 1) {
                profile->muxid = 0x81;
                profile->qmapnet_adapter = strdup(profile->usbnet_adapter);
           }
        }
    }
    else if(qmidev_is_qmiwwan(profile->qmichannel))
    {
        snprintf(pl->filename, sizeof(pl->filename), "/sys/module/%s/parameters/qmap_mode", profile->driver_name);

         if (access(pl->filename, R_OK) == 0) {
            //Meig Style QMAP qmi_wwan.c

            if (meig_fread(pl->filename, buf, sizeof(buf))) {
                profile->qmap_mode = atoi(buf);

                if (profile->qmap_mode > 1) {
                    profile->muxid = profile->pdp + 0x80; //muxis is 0x8X for PDN-X
                    sprintf(qmap_netcard, "%s.%d", profile->usbnet_adapter, profile->pdp);
                    profile->qmapnet_adapter = strdup(qmap_netcard);
#if 1 //TODO Ubuntu qmi_wwan 1-1.3:1.4 wwp0s26u1u3i4: renamed from wwan0
                    if (access(qmap_netcard, R_OK) && errno == ENOENT) {
                        sprintf(qmap_netcard, "%s.%d", "wwan0", profile->pdp);
                        free(profile->qmapnet_adapter);
                        profile->qmapnet_adapter = strdup(qmap_netcard);                        
                    }
#endif
                }
                else if (profile->qmap_mode == 1) {
                    profile->muxid = 0x81;
                    profile->qmapnet_adapter = strdup(profile->usbnet_adapter);
                }
            }
            else if (errno != ENOENT) {
                dbg_time("fail to access %s, errno: %d (%s)", pl->filename, errno, strerror(errno));
            }
            else {
                snprintf(pl->filename, sizeof(pl->filename), "/sys/class/net/qmimux%d", profile->pdp - 1);

                if (access(pl->filename, R_OK) == 0) {
                    //upstream Kernel Style QMAP qmi_wwan.c

                    snprintf(pl->filename, sizeof(pl->filename), "/sys/class/net/%s/qmi/add_mux", profile->usbnet_adapter);

                    n = meig_fread(pl->filename, buf, sizeof(buf));
                    if (n >= 3) {
                        profile->qmap_mode = n/3;
                        if (profile->qmap_mode > 1) {
                            //PDN-X map to qmimux-X
                            profile->muxid = (buf[3*(profile->pdp - 1) + 0] - '0')*16 + (buf[3*(profile->pdp - 1) + 1] - '0');
                            sprintf(qmap_netcard, "qmimux%d", profile->pdp - 1);
                            profile->qmapnet_adapter = strdup(qmap_netcard);
                        } else if (profile->qmap_mode == 1){
                            profile->muxid = (buf[3*0 + 0] - '0')*16 + (buf[3*0 + 1] - '0');
                            sprintf(qmap_netcard, "qmimux%d", 0);
                            profile->qmapnet_adapter = strdup(qmap_netcard);
                        }
                    }
                }
            }
        }
        else if (errno != ENOENT) {
            dbg_time("fail to access %s, errno: %d (%s)", pl->filename, errno, strerror(errno));
        }
    } 
    else if (qmidev_is_pciemhi(profile->qmichannel)) {
        profile->qmap_mode = 1;
        profile->muxid = 0x81;
        profile->qmapnet_adapter = strdup(profile->usbnet_adapter);
    }

    if (profile->qmap_mode) {
        dbg_time("qmap_mode = %d, muxid = 0x%02x, qmap_netcard = %s",
            profile->qmap_mode, profile->muxid, profile->qmapnet_adapter);
    }

    free(pl);

    return 0;
}
