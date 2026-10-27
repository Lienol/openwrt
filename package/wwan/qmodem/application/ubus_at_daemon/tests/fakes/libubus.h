#ifndef TEST_FAKE_LIBUBUS_H
#define TEST_FAKE_LIBUBUS_H

struct blob_attr;
struct ubus_context { int unused; };
struct ubus_object { int unused; };
struct ubus_request_data { int unused; };

int ubus_send_event(struct ubus_context *ctx, const char *id,
                    struct blob_attr *msg);

#endif
