/*
    Copyright 2023 Quectel Wireless Solutions Co.,Ltd

    Quectel hereby grants customers of Quectel a license to use, modify,
    distribute and publish the Software in binary form provided that
    customers shall have no right to reverse engineer, reverse assemble,
    decompile or reduce to source code form any portion of the Software.
    Under no circumstances may customers modify, demonstrate, use, deliver
    or disclose any portion of the Software in source code form.
*/

#ifndef _QUECTEL_MD5_H
#define _QUECTEL_MD5_H

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include "usb_linux.h"

typedef struct md5_ctx
{
    uint32_t lo, hi;
    uint32_t a, b, c, d;
    unsigned char buffer[64];
} md5_ctx_t;

// void dbg_time (const char *fmt, ...);
extern int md5_check(const char *);

#endif /* _QUECTEL_MD5_H */
