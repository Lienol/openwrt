LOCAL_PATH:= $(call my-dir)
include $(CLEAR_VARS)
LOCAL_SRC_FILES:= firehose_protocol.c qfirehose.c sahara.c usb_linux.c stream_download_protocol.c md5.c usb2tcp.c
LOCAL_CFLAGS += -pie -fPIE -Wall -Wextra -Werror -O1
LOCAL_LDFLAGS += -pie -fPIE
LOCAL_MODULE_TAGS:= optional
LOCAL_MODULE:= QFirehose
include $(BUILD_EXECUTABLE)
