/*
    Copyright 2023 Quectel Wireless Solutions Co.,Ltd

    Quectel hereby grants customers of Quectel a license to use, modify,
    distribute and publish the Software in binary form provided that
    customers shall have no right to reverse engineer, reverse assemble,
    decompile or reduce to source code form any portion of the Software.
    Under no circumstances may customers modify, demonstrate, use, deliver
    or disclose any portion of the Software in source code form.
*/

#include "usb_linux.h"
#include "sahara.h"

static uint32_t le_uint32(uint32_t v32)
{
    const int is_bigendian = 1;
    uint32_t tmp = v32;
    if ((*(char *)&is_bigendian) == 0)
    {
        unsigned char *s = (unsigned char *)(&v32);
        unsigned char *d = (unsigned char *)(&tmp);
        d[0] = s[3];
        d[1] = s[2];
        d[2] = s[1];
        d[3] = s[0];
    }
    return tmp;
}

static uint64_t le_uint64(uint64_t v64)
{
    const int is_bigendian = 1;
    uint64_t tmp = v64;
    if ((*(char *)&is_bigendian) == 0)
    {
        unsigned char *s = (unsigned char *)(&v64);
        unsigned char *d = (unsigned char *)(&tmp);
        d[0] = s[7];
        d[1] = s[6];
        d[2] = s[5];
        d[3] = s[4];
        d[4] = s[3];
        d[5] = s[2];
        d[6] = s[1];
        d[7] = s[0];
    }
    return tmp;
}

#define dbg(log_level, fmt, arg...) \
    do                              \
    {                               \
        dbg_time(fmt "\n", ##arg);  \
    } while (0)

static int sahara_tx_data(void *usb_handle, void *tx_buffer, size_t bytes_to_send)
{
    int need_zlp = 0; // zlp is not mandatory
    return qusb_noblock_write(usb_handle, tx_buffer, bytes_to_send, bytes_to_send, 3000, need_zlp);
}

int qusb_use_usbfs_interface(const void *handle);
static int sahara_rx_data(void *usb_handle, void *rx_buffer, size_t bytes_to_read)
{
    q_sahara_packet_h *command_packet_header = NULL;
    size_t bytes_read = 0;

    const char *q_sahara_cmd_str[Q_SAHARA_NINETEEN] = {
        "Q_SAHARA_ZERO",      //          = 0x00,
        "Q_SAHARA_ONE",       //            = 0x01, // sent from target to host
        "Q_SAHARA_TWO",       //       = 0x02, // sent from host to target
        "Q_SAHARA_THREE",     //        = 0x03, // sent from target to host
        "Q_SAHARA_FOUR",      //     = 0x04, // sent from target to host
        "Q_SAHARA_FIVE",      //             = 0x05, // sent from host to target
        "Q_SAHARA_SIX",       //        = 0x06, // sent from target to host
        "Q_SAHARA_SEVEN",     //            = 0x07, // sent from host to target
        "Q_SAHARA_EIGTH",     //       = 0x08, // sent from target to host
        "Q_SAHARA_NINE",      //     = 0x09, // sent from target to host
        "Q_SAHARA_TEN",       //      = 0x0A, // sent from host to target
        "Q_SAHARA_ELEVEN",    //        = 0x0B, // sent from target to host
        "Q_SAHARA_TWELEVE",   //  = 0x0C, // sent from host to target
        "Q_SAHARA_THIRTEEN",  //         = 0x0D, // sent from host to target
        "Q_SAHARA_FOURTEEN",  //    = 0x0E, // sent from target to host
        "Q_SAHARA_FIFTEEN",   //    = 0x0F, // sent from host to target
        "Q_SAHARA_SIXTEEN",   // 	= 0x10, // sent from target to host
        "Q_SAHARA_SEVENTEEN", // 		= 0x11, // sent from host to target
        "Q_SAHARA_EIGHTEEN",  // 		= 0x12,
    };

    if (0 == bytes_to_read)
    {
        if (qusb_use_usbfs_interface(usb_handle))
        {
            bytes_read = qusb_noblock_read(usb_handle, rx_buffer, Q_SAHARA_RAW_BUF_SZ, 0, 5000);
            if (bytes_read < sizeof(q_sahara_packet_h)) return 0;
        }
        else
        {
            bytes_read =
                qusb_noblock_read(usb_handle, rx_buffer, sizeof(q_sahara_packet_h), 0, 5000);
            if (bytes_read != sizeof(q_sahara_packet_h)) return 0;
        }

        command_packet_header = (q_sahara_packet_h *)rx_buffer;
        if (le_uint32(command_packet_header->q_cmd) < Q_SAHARA_NINETEEN)
        {
            dbg(LOG_EVENT, "<=== %s", q_sahara_cmd_str[le_uint32(command_packet_header->q_cmd)]);

            if (!qusb_use_usbfs_interface(usb_handle))
            {
                bytes_read += qusb_noblock_read(
                    usb_handle, (uint8_t *)rx_buffer + sizeof(q_sahara_packet_h),
                    le_uint32(command_packet_header->q_len) - sizeof(q_sahara_packet_h), 0, 5000);
            }

            if (bytes_read != (le_uint32(command_packet_header->q_len)))
            {
                dbg(LOG_INFO, "Read %zd bytes, Header indicates q_cmd %d and packet q_len %d bytes",
                    bytes_read, le_uint32(command_packet_header->q_cmd),
                    le_uint32(command_packet_header->q_len));
                return 0;
            }
        }
        else
        {
            dbg(LOG_EVENT, "<=== SAHARA_CMD_UNKONOW_%d", le_uint32(command_packet_header->q_cmd));
            return 0;
        }
    }
    else
    {
        bytes_read = qusb_noblock_read(usb_handle, rx_buffer, bytes_to_read, bytes_to_read, 5000);
    }

    return 1;
}

static int send_reset_command(void *usb_handle, void *tx_buffer)
{
    struct sahara_pkt *sahara_reset;
    sahara_reset = (struct sahara_pkt *)tx_buffer;
    sahara_reset->q_header.q_cmd = le_uint32(Q_SAHARA_SEVEN);
    sahara_reset->q_header.q_len =
        le_uint32(sizeof(sahara_reset->q_sahara_reset_packet) + sizeof(q_sahara_packet_h));

    /* Send the Reset Request */
    dbg(LOG_EVENT, "SAHARA_RESET ===>");
    if (0 ==
        sahara_tx_data(usb_handle, tx_buffer,
                       sizeof(sahara_reset->q_sahara_reset_packet) + sizeof(q_sahara_packet_h)))
    {
        dbg(LOG_ERROR, "Sending RESET packet failed");
        return 0;
    }

    return 1;
}

static int send_done_packet(void *usb_handle, void *tx_buffer)
{
    struct sahara_pkt *sahara_done;
    sahara_done = (struct sahara_pkt *)tx_buffer;

    sahara_done->q_header.q_cmd = le_uint32(Q_SAHARA_FIVE);
    sahara_done->q_header.q_len =
        le_uint32(sizeof(sahara_done->q_sahara_done_packet) + sizeof(q_sahara_packet_h));
    // Send the image data
    dbg(LOG_EVENT, "Q_SAHARA_FIVE ===>");
    if (0 == sahara_tx_data(usb_handle, tx_buffer,
                            sizeof(sahara_done->q_sahara_done_packet) + sizeof(q_sahara_packet_h)))
    {
        dbg(LOG_ERROR, "Sending DONE packet failed");
        return 0;
    }
    return 1;
}

static int start_image_transfer(void *usb_handle, void *tx_buffer,
                                const struct sahara_pkt *pr_sahara_pkt, FILE *file_handle)
{
    int retval = 0;
    uint32_t bytes_read = 0, bytes_to_read_next;
    uint32_t q_image_id = le_uint32(pr_sahara_pkt->q_sahara_read_packet_data.q_image_id);
    uint32_t DataOffset = le_uint32(pr_sahara_pkt->q_sahara_read_packet_data.q_data_offset);
    uint32_t DataLength = le_uint32(pr_sahara_pkt->q_sahara_read_packet_data.q_data_length);

    if (le_uint32(pr_sahara_pkt->q_header.q_cmd) == Q_SAHARA_EIGHTEEN)
    {
        q_image_id = le_uint64(pr_sahara_pkt->q_sahara_read_packet_data_64bit.q_image_id);
        DataOffset = le_uint64(pr_sahara_pkt->q_sahara_read_packet_data_64bit.q_data_offset);
        DataLength = le_uint64(pr_sahara_pkt->q_sahara_read_packet_data_64bit.q_data_length);
    }

    dbg(LOG_INFO, "0x%08x 0x%08x 0x%08x", q_image_id, DataOffset, DataLength);

    if (fseek(file_handle, (long)DataOffset, SEEK_SET))
    {
        dbg(LOG_INFO, "%d errno: %d (%s)", __LINE__, errno, strerror(errno));
        return 0;
    }

    while (bytes_read < DataLength)
    {
        bytes_to_read_next = MIN((uint32_t)DataLength - bytes_read, Q_SAHARA_RAW_BUF_SZ);
        retval = fread(tx_buffer, 1, bytes_to_read_next, file_handle);

        if (retval < 0)
        {
            dbg(LOG_ERROR, "file read failed: %s", strerror(errno));
            return 0;
        }

        if ((uint32_t)retval != bytes_to_read_next)
        {
            dbg(LOG_ERROR, "Read %d bytes, but was asked for 0x%08x bytes", retval, DataLength);
            return 0;
        }

        /*send the image data*/
        if (0 == sahara_tx_data(usb_handle, tx_buffer, bytes_to_read_next))
        {
            dbg(LOG_ERROR, "Tx Sahara Image Failed");
            return 0;
        }

        bytes_read += bytes_to_read_next;
    }

    return 1;
}

static int send_hello_response(void *usb_handle, void *tx_buffer,
                               const struct sahara_pkt *sahara_hello)
{
    struct sahara_pkt *sahara_hello_resp;
    sahara_hello_resp = (struct sahara_pkt *)tx_buffer;

    // Recieved hello, send the hello response
    // Create a Hello request
    sahara_hello_resp->q_header.q_cmd = le_uint32(Q_SAHARA_TWO);
    sahara_hello_resp->q_header.q_len = le_uint32(
        sizeof(sahara_hello_resp->q_sahara_hello_packet_response) + sizeof(q_sahara_packet_h));
    sahara_hello_resp->q_sahara_hello_packet_response.q_ver =
        sahara_hello->q_sahara_hello_packet.q_ver;
    sahara_hello_resp->q_sahara_hello_packet_response.q_ver_sup =
        sahara_hello->q_sahara_hello_packet.q_ver_sup;
    sahara_hello_resp->q_sahara_hello_packet_response.q_status = le_uint32(Q_SAHARA_STATUS_ZERO);
    sahara_hello_resp->q_sahara_hello_packet_response.q_mode =
        sahara_hello->q_sahara_hello_packet.q_mode;
    sahara_hello_resp->q_sahara_hello_packet_response.q_reserve1 = le_uint32(1);
    sahara_hello_resp->q_sahara_hello_packet_response.q_reserve2 = le_uint32(2);
    sahara_hello_resp->q_sahara_hello_packet_response.q_reserve3 = le_uint32(3);
    sahara_hello_resp->q_sahara_hello_packet_response.q_reserve4 = le_uint32(4);
    sahara_hello_resp->q_sahara_hello_packet_response.q_reserve5 = le_uint32(5);
    sahara_hello_resp->q_sahara_hello_packet_response.q_reserve6 = le_uint32(6);

    if (le_uint32(sahara_hello->q_sahara_hello_packet.q_mode) != Q_SAHARA_MODE_ZERO)
    {
        dbg(LOG_ERROR, "ERROR NOT Q_SAHARA_MODE_ZERO");
        sahara_hello_resp->q_sahara_hello_packet_response.q_mode = Q_SAHARA_MODE_ZERO;
    }

    /*Send the Hello  Resonse Request*/
    dbg(LOG_EVENT, "Q_SAHARA_TWO ===>");
    if (0 == sahara_tx_data(usb_handle, tx_buffer,
                            sizeof(sahara_hello_resp->q_sahara_hello_packet_response) +
                                sizeof(q_sahara_packet_h)))
    {
        dbg(LOG_ERROR, "Tx Sahara Data Failed ");
        return 0;
    }

    return 1;
}

static int sahara_flash_all(void *usb_handle, void *tx_buffer, void *rx_buffer, FILE *file_handle)
{
    uint32_t q_image_id = 0;
    struct sahara_pkt *pr_sahara_pkt;

    pr_sahara_pkt = (struct sahara_pkt *)rx_buffer;

    if (0 == sahara_rx_data(usb_handle, rx_buffer, 0))
    {
        sahara_tx_data(usb_handle, tx_buffer, 1);
        if (0 == sahara_rx_data(usb_handle, rx_buffer, 0)) return 0;
    }

    if (le_uint32(pr_sahara_pkt->q_header.q_cmd) != Q_SAHARA_ONE)
    {
        dbg(LOG_ERROR, "Received a different q_cmd: %x while waiting for hello packet",
            pr_sahara_pkt->q_header.q_cmd);
        send_reset_command(usb_handle, rx_buffer);
        return 0;
    }

    if (0 == send_hello_response(usb_handle, tx_buffer, pr_sahara_pkt))
    {
        dbg(LOG_ERROR, "send_hello_response failed\n");
        return 0;
    }

    while (1)
    {
        if (0 == sahara_rx_data(usb_handle, rx_buffer, 0)) return 0;

        if (le_uint32(pr_sahara_pkt->q_header.q_cmd) == Q_SAHARA_THREE)
        {
            start_image_transfer(usb_handle, tx_buffer, pr_sahara_pkt, file_handle);
        }
        else if (le_uint32(pr_sahara_pkt->q_header.q_cmd) == Q_SAHARA_EIGHTEEN)
        {
            start_image_transfer(usb_handle, tx_buffer, pr_sahara_pkt, file_handle);
        }
        else if (le_uint32(pr_sahara_pkt->q_header.q_cmd) == Q_SAHARA_FOUR)
        {
            dbg(LOG_EVENT, "q_image_id = %d, q_status = %d",
                le_uint32(pr_sahara_pkt->q_sahara_end_packet_image_tx.q_image_id),
                le_uint32(pr_sahara_pkt->q_sahara_end_packet_image_tx.q_status));
            if (le_uint32(pr_sahara_pkt->q_sahara_end_packet_image_tx.q_status) ==
                Q_SAHARA_STATUS_ZERO)
            {
                q_image_id = le_uint32(pr_sahara_pkt->q_sahara_end_packet_image_tx.q_image_id);
                send_done_packet(usb_handle, tx_buffer);
                break;
            }
            else
            {
                return 0;
            }
        }
        else if (le_uint32(pr_sahara_pkt->q_header.q_cmd) == Q_SAHARA_ONE)
        {
            continue;
        }
        else
        {
            dbg(LOG_ERROR, "Received an unknown q_cmd: %d ",
                le_uint32(pr_sahara_pkt->q_header.q_cmd));
            send_reset_command(usb_handle, tx_buffer);
            return 0;
        }
    }

    if (0 == sahara_rx_data(usb_handle, rx_buffer, 0)) return 0;

    dbg(LOG_INFO, "q_image_tx_status = %d",
        le_uint32(pr_sahara_pkt->q_sahara_done_packet_response.q_image_tx_status));

    if (Q_SAHARA_MODE_ZERO ==
        le_uint32(pr_sahara_pkt->q_sahara_done_packet_response.q_image_tx_status))
    {
        if (q_image_id == 13) // prog_nand_firehose_9x07.mbn
            return 1;
        if (q_image_id == 7) // NPRG9x55.mbn
            return 1;
        if (q_image_id == 21) // sbl1.mbn, October 22 2020 2:12 PM, AG35CEVAR05A07T4G
            return 1;
    }
    else if (Q_SAHARA_MODE_ONE ==
             le_uint32(pr_sahara_pkt->q_sahara_done_packet_response.q_image_tx_status))
    {
        dbg(LOG_EVENT, "Successfully flash all images");
        return 1;
    }
    else
    {
        dbg(LOG_ERROR, "Received unrecognized q_status %d at Q_SAHARA_WAIT_FOUR state",
            le_uint32(pr_sahara_pkt->q_sahara_done_packet_response.q_image_tx_status));
        return 0;
    }

    return 0;
}

int sahara_main(const char *firehose_dir, const char *firehose_mbn, void *usb_handle,
                int edl_mode_05c69008)
{
    int retval = 0;
    char full_path[512];
    FILE *file_handle;
    void *tx_buffer;
    void *rx_buffer;

    if (edl_mode_05c69008)
    {
        if (is_upgrade_fimeware_zip_7z)
        {
            snprintf(full_path, sizeof(full_path), "/tmp/%.240s", firehose_mbn);
            dbg_time("%s full_path:%s\n", __func__, full_path);
        }
        else
        {
            snprintf(full_path, sizeof(full_path), "%.255s/%.240s", firehose_dir, firehose_mbn);
        }
    }
    else
    {
        char *prog_nand_firehose_filename = NULL;

        if (is_upgrade_fimeware_zip_7z)
        {
            int i;
            char prog_nand_firehose_filename_tmp[128] = {0};
            char prog_nand_firehose_filename_dir_tmp[256] = {0};

            prog_nand_firehose_filename = (char *)malloc(256);
            if (prog_nand_firehose_filename == NULL)
            {
                return ENOENT;
            }

            for (i = 0; i < file_name_b.file_name_count; i++)
            {
                if ((strstr(file_name_b.file_backup_c[i].zip_file_name_backup, "NPRG9x") &&
                     strstr(file_name_b.file_backup_c[i].zip_file_name_backup, ".mbn")))
                {
                    dbg_time("file_name_b.file_backup_c[i].zip_file_name_backup:%s\n",
                             file_name_b.file_backup_c[i].zip_file_name_backup);
                    dbg_time("file_name_b.file_backup_c[i].zip_file_dir_backup:%s\n",
                             file_name_b.file_backup_c[i].zip_file_dir_backup);

                    if (strstr(file_name_b.file_backup_c[i].zip_file_dir_backup, "update/firehose"))
                    {
                        memmove(prog_nand_firehose_filename_tmp,
                                file_name_b.file_backup_c[i].zip_file_name_backup,
                                strlen(file_name_b.file_backup_c[i].zip_file_name_backup));
                        memmove(prog_nand_firehose_filename_dir_tmp,
                                file_name_b.file_backup_c[i].zip_file_dir_backup,
                                strlen(file_name_b.file_backup_c[i].zip_file_dir_backup));
                        break;
                    }
                }
            }

            if (prog_nand_firehose_filename_tmp[0] != '\0')
            {
                memset(zip_cmd_buf, 0, sizeof(zip_cmd_buf));
                if (is_upgrade_fimeware_only_zip)
                {
                    snprintf(zip_cmd_buf, sizeof(zip_cmd_buf),
                             "unzip -o -q %.240s '*%.200s' -d /tmp/ > %s", firehose_dir,
                             prog_nand_firehose_filename_dir_tmp, ZIP_PROCESS_INFO);
                }
                else
                {
                    snprintf(zip_cmd_buf, sizeof(zip_cmd_buf), "7z x %.240s -o/tmp/ %.200s > %s",
                             firehose_dir, prog_nand_firehose_filename_dir_tmp, ZIP_PROCESS_INFO);
                }
                dbg_time("%s zip_cmd_buf:%s\n", __func__, zip_cmd_buf);
                if (-1 == system(zip_cmd_buf))
                {
                    dbg_time("%s system return error\n", __func__);
                    safe_free(prog_nand_firehose_filename);
                    return ENOENT;
                }
                usleep(1000);

                memmove(prog_nand_firehose_filename, prog_nand_firehose_filename_dir_tmp, 240);
                dbg(LOG_INFO, "prog_nand_firehose_filename = %s", prog_nand_firehose_filename);

                snprintf(full_path, sizeof(full_path), "/tmp/%.240s", prog_nand_firehose_filename);
            }
        }
        else
        {
            snprintf(full_path, sizeof(full_path), "%.255s/..", firehose_dir);
            if (!qfile_find_file(full_path, "NPRG9x", ".mbn", &prog_nand_firehose_filename) &&
                !qfile_find_file(full_path, "NPRG9x", ".mbn", &prog_nand_firehose_filename))
            {
                dbg(LOG_ERROR, "retrieve NPRG MBN failed.");
                safe_free(prog_nand_firehose_filename);
                return ENOENT;
            }
            dbg(LOG_INFO, "prog_nand_firehose_filename = %s", prog_nand_firehose_filename);

            snprintf(full_path, sizeof(full_path), "%.255s/../%.240s", firehose_dir,
                     prog_nand_firehose_filename);
        }

        safe_free(prog_nand_firehose_filename);
    }

    file_handle = fopen(full_path, "rb");
    if (file_handle == NULL)
    {
        dbg(LOG_INFO, "%s %d %s errno: %d (%s)", __func__, __LINE__, full_path, errno,
            strerror(errno));
        return ENOENT;
    }

    rx_buffer = malloc(Q_SAHARA_RAW_BUF_SZ);
    tx_buffer = malloc(Q_SAHARA_RAW_BUF_SZ);

    if (NULL == rx_buffer || NULL == tx_buffer)
    {
        dbg(LOG_ERROR, "Failed to allocate sahara buffers");
        safe_free(rx_buffer);
        safe_free(tx_buffer);
        fclose(file_handle);
        file_handle = NULL;
        return ENOMEM;
    }

    retval = sahara_flash_all(usb_handle, tx_buffer, rx_buffer, file_handle);
    if (0 == retval)
    {
        dbg(LOG_ERROR, "Sahara protocol error");
    }
    else
    {
        dbg(LOG_STATUS, "Sahara protocol completed");
    }

    safe_free(rx_buffer);
    safe_free(tx_buffer);
    fclose(file_handle);
    file_handle = NULL;

    if (is_upgrade_fimeware_zip_7z)
    {
        unlink(full_path);
    }

    if (retval) return 0;

    return __LINE__;
}
