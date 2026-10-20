#ifndef TEST_FAKE_BLOBMSG_JSON_H
#define TEST_FAKE_BLOBMSG_JSON_H

#include <assert.h>
#include <stdint.h>
#include <string.h>

#define BLOBMSG_TYPE_STRING 3

struct blob_attr { int unused; };

typedef struct {
    char name[32];
    int type;
    uint64_t u64;
    char string[1024];
    size_t length;
} fake_blob_field_t;

struct blob_buf {
    struct blob_attr *head;
    fake_blob_field_t fields[16];
    size_t count;
};

static inline fake_blob_field_t *fake_blob_add(struct blob_buf *b,
                                                const char *name, int type)
{
    fake_blob_field_t *field = &b->fields[b->count++];
    memset(field, 0, sizeof(*field));
    strncpy(field->name, name, sizeof(field->name) - 1U);
    field->type = type;
    return field;
}

static inline void blob_buf_init(struct blob_buf *b, int id)
{
    (void)id;
    memset(b, 0, sizeof(*b));
    b->head = (struct blob_attr *)b;
}

static inline void blob_buf_free(struct blob_buf *b)
{
    (void)b;
}

static inline void blobmsg_add_string(struct blob_buf *b, const char *name,
                                      const char *value)
{
    fake_blob_field_t *field = fake_blob_add(b, name, BLOBMSG_TYPE_STRING);
    strncpy(field->string, value, sizeof(field->string) - 1U);
    field->length = strlen(field->string) + 1U;
}

static inline void blobmsg_add_u64(struct blob_buf *b, const char *name,
                                   uint64_t value)
{
    fake_blob_add(b, name, 0)->u64 = value;
}

static inline void blobmsg_add_field(struct blob_buf *b, int type,
                                     const char *name, const void *data,
                                     size_t length)
{
    fake_blob_field_t *field = fake_blob_add(b, name, type);
    assert(length <= sizeof(field->string));
    memcpy(field->string, data, length);
    field->length = length;
}

#endif
