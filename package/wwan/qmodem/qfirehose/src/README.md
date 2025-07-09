# QFIREHOSE 升级进度通知机制说明

> ​    QFirehose 目前支持两种进度通知方式。基于文件的通知方式，基于消息队列的通知机制。两种方式均可使用。Android设备由于系统限制，system V IPC 机制支持不完善，不能支持消息队列的方式获取进度。
>
> ​    其中基于文件的形式很容易替换成，有名管道的形式，只需把创建并打开改成创建并打开管道的形式（参考`man mkfifio`）。「注：管道需要先以读方式打开，再以写方式打开，否则会有错误」 

##  一、进度读写说明
> QFirehose 进度都是以<u>**整数**</u>形式写到文件或者消息队列里。

1. 在升级开始阶段写入进度**0**预示这升级开始。
2. 之后每次进度有变化都会重新更新进度信息。
3. 升级完成最后结果是**100**。
4. 升级发生异常会写入进度 **-1**. 「注：特殊情况，如程序异常崩溃进度信息可能来不及写入而是空的，需要第三方程序考虑文件内容为空的情况」

##  二、文件形式的通知机制
### A. 文件读写说明

​    文件方式的交互文件路径为: Android **“/data/update.conf”**, 其他 **“/tmp/update.conf”**。(修改QFirehose 源码可以修改这个文件）。另外需要保证/data 或者/tmp 这个目录存在，且QFirehose有读写、创建文件的权限。
​    由于文件是持续存在磁盘上的。为了保证命令行方式的cat 读与标准API 的read 两种方式的可读性。<u>**进度写方式为覆盖写，意思就是新的进度会覆盖掉之前的内容。**</u>表现在实现上就是，每次写之前移动文件指针到文件头，然后写入进度。读进度时候需要注意这一点！！！
​    另外注意的是QFirehose 不负责文件的删除，如果需要删除需要由第三方程序在升级结束/出错删除进度文件！

### B.使用说明
​    QFirehose 默认不使能通知功能。如需使能文件方式通知逻辑需要在编译时指定宏 **USE_IPC_FILE** , 建议在Makefile里用 **-DUSE_IPC_FILE**来使能. 如下代码所示

```makefile
NDK_BUILD:=/workspace/android-ndk/android-ndk-r10e/ndk-build

ifeq ($(CC),cc)
CC=${CROSS_COMPILE}gcc
endif

cflags += -Wno-format-overflow

linux: clean
	${CC} -g -Wall -DUSE_IPC_FILE -s ${cflags} firehose_protocol.c  qfirehose.c  sahara_protocol.c usb_linux.c stream_download_protocol.c md5.c usb2tcp.c -o QFirehose -lpthread -ldl

clean:
	rm -rf QFirehose obj libs android usb2tcp *~

```

## 三、消息队列的通知机制
### A. 原理说明
System V 方式消息队列。QFirehose 负责创建消息队列，写入进度。**不负责删除消息，不负责删除消息队列。**
如下图，QFirehose 定义的消息结构体，消息类型，与message key 获取机制。第三方应用需要与QFirehose 保持一致。如需修改，可以修改QFirehose 源码。

System V message queue：

```c
#define MSGBUFFSZ 16
struct message
{
    long mtype;
    char mtext[MSGBUFFSZ];
};

#define MSG_FILE "/etc/passwd"
#define MSG_TYPE_IPC 1
```

并同时修改编译脚本/源码，定义宏 **USE_IPC_MSG**, 如下所示

```makefile
NDK_BUILD:=/workspace/android-ndk/android-ndk-r10e/ndk-build

ifeq ($(CC),cc)
CC=${CROSS_COMPILE}gcc
endif

cflags += -Wno-format-overflow

linux: clean
	${CC} -g -Wall -DUSE_IPC_MSG -s ${cflags} firehose_protocol.c  qfirehose.c  sahara_protocol.c usb_linux.c stream_download_protocol.c md5.c usb2tcp.c -o QFirehose -lpthread -ldl

clean:
	rm -rf QFirehose obj libs android usb2tcp *~
```

QFirehose 实现了四个操作函数：消息队列的创建，删除，写，读。但是只用到了创建与读函数。另外两个仅供参考与测试用。
### B.使用说明
QFirehose 负责创建消息队列，写入进度。不会删除消息以及消息队列。建议第三方应用在升级程序退出之后主动删除消息队列。

QFirehose 支持对消息队列的测试，这需要启用宏 **IPC_TEST** 。开启这个宏之后，QFirehose 会在写入消息后再次读取消息，并打印到`STDOUT`，检查打印可知是否正确。

```c
/**
 * this function will not delete the msg queue
 */
int update_progress_msg(int percent)
{
    char buff[MSGBUFFSZ];
    int msgid = msg_get();
    if (msgid < 0)
        return -1;
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
```

