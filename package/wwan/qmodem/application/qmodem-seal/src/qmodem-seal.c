#define _POSIX_C_SOURCE 200809L

#include <sodium.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#define TOKEN_MIN 16
#define TOKEN_MAX 64
#define IO_CHUNK 65536
#define PAYLOAD_MAGIC "QMSPAY1\n"
#define KEY_MAGIC "QMSKEY1\n"
#define RECIPIENT_PREFIX "qms1:"
#define REVIEW_PREFIX "qmr1:"

static const unsigned char token_salt[crypto_pwhash_SALTBYTES] = {
    'Q','M','o','d','e','m','S','e','a','l','T','o','k','V','1','!'
};

static void usage(void)
{
    fprintf(stderr,
        "usage:\n"
        "  qmodem-seal identity derive [--token-stdin]\n"
        "  qmodem-seal seal --recipient PUB --input FILE --payload FILE --key FILE\n"
        "  qmodem-seal review-key --manifest FILE [--token-stdin]\n"
        "  qmodem-seal decrypt --input FEEDBACK.tar --output FILE [--review-key] [--token-stdin]\n");
    exit(2);
}

static void die(const char *message)
{
    fprintf(stderr, "qmodem-seal: %s\n", message);
    exit(1);
}

static int write_all(FILE *out, const void *data, size_t size)
{
    return fwrite(data, 1, size, out) == size ? 0 : -1;
}

static int read_secret(const char *prompt, char *buffer, size_t size, int stdin_mode)
{
    FILE *in = stdin;
    struct termios old_term, new_term;
    int tty_fd = -1;
    int hide = 0;

    if (!stdin_mode) {
        tty_fd = open("/dev/tty", O_RDWR);
        if (tty_fd < 0)
            return -1;
        in = fdopen(tty_fd, "r");
        if (!in) {
            close(tty_fd);
            return -1;
        }
        fprintf(stderr, "%s", prompt);
        fflush(stderr);
        if (tcgetattr(tty_fd, &old_term) == 0) {
            new_term = old_term;
            new_term.c_lflag &= (tcflag_t)~ECHO;
            if (tcsetattr(tty_fd, TCSAFLUSH, &new_term) == 0)
                hide = 1;
        }
    }

    if (!fgets(buffer, (int)size, in)) {
        if (hide)
            tcsetattr(tty_fd, TCSAFLUSH, &old_term);
        if (!stdin_mode)
            fclose(in);
        return -1;
    }
    if (hide) {
        tcsetattr(tty_fd, TCSAFLUSH, &old_term);
        fputc('\n', stderr);
    }
    if (!stdin_mode)
        fclose(in);

    buffer[strcspn(buffer, "\r\n")] = '\0';
    return 0;
}

static int validate_token(const char *token)
{
    size_t i, len = strlen(token);
    if (len < TOKEN_MIN || len > TOKEN_MAX)
        return -1;
    for (i = 0; i < len; i++) {
        unsigned char c = (unsigned char)token[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-'))
            return -1;
    }
    return 0;
}

static int derive_keypair(const char *token, unsigned char pk[crypto_box_PUBLICKEYBYTES],
                          unsigned char sk[crypto_box_SECRETKEYBYTES])
{
    unsigned char seed[crypto_box_SEEDBYTES];
    int rc;

    if (validate_token(token) != 0)
        return -1;
    rc = crypto_pwhash(seed, sizeof(seed), token, strlen(token), token_salt,
                       crypto_pwhash_OPSLIMIT_MODERATE,
                       crypto_pwhash_MEMLIMIT_MODERATE,
                       crypto_pwhash_ALG_ARGON2ID13);
    if (rc != 0)
        return -1;
    crypto_box_seed_keypair(pk, sk, seed);
    sodium_memzero(seed, sizeof(seed));
    return 0;
}

static void encode_value(const char *prefix, const unsigned char *value, size_t value_len,
                         char *output, size_t output_len)
{
    size_t prefix_len = strlen(prefix);
    if (output_len <= prefix_len)
        die("internal encoding buffer is too small");
    memcpy(output, prefix, prefix_len);
    sodium_bin2base64(output + prefix_len, output_len - prefix_len, value, value_len,
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
}

static int decode_value(const char *encoded, const char *prefix, unsigned char *output,
                        size_t expected_len)
{
    size_t actual_len = 0;
    size_t prefix_len = strlen(prefix);
    if (strncmp(encoded, prefix, prefix_len) != 0)
        return -1;
    if (sodium_base642bin(output, expected_len, encoded + prefix_len,
                          strlen(encoded + prefix_len), NULL, &actual_len, NULL,
                          sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0)
        return -1;
    return actual_len == expected_len ? 0 : -1;
}

static void print_identity(const unsigned char pk[crypto_box_PUBLICKEYBYTES])
{
    unsigned char id[8];
    char recipient[64];
    size_t i;

    encode_value(RECIPIENT_PREFIX, pk, crypto_box_PUBLICKEYBYTES,
                 recipient, sizeof(recipient));
    crypto_generichash(id, sizeof(id), pk, crypto_box_PUBLICKEYBYTES, NULL, 0);
    printf("recipient=%s\nrecipient_id=qms1-", recipient);
    for (i = 0; i < sizeof(id); i++)
        printf("%02x", id[i]);
    putchar('\n');
}

static void command_identity(int argc, char **argv)
{
    char token[TOKEN_MAX + 2], confirm[TOKEN_MAX + 2];
    unsigned char pk[crypto_box_PUBLICKEYBYTES], sk[crypto_box_SECRETKEYBYTES];
    int stdin_mode = argc == 4 && strcmp(argv[3], "--token-stdin") == 0;

    if (argc < 3 || argc > 4 || strcmp(argv[2], "derive") != 0 ||
        (argc == 4 && !stdin_mode))
        usage();
    if (read_secret("Token: ", token, sizeof(token), stdin_mode) != 0 ||
        read_secret("Confirm token: ", confirm, sizeof(confirm), stdin_mode) != 0)
        die("failed to read token");
    if (strcmp(token, confirm) != 0)
        die("tokens do not match");
    if (validate_token(token) != 0)
        die("token must be 16-64 characters using A-Z, a-z, 0-9, '.', '_' or '-'");
    if (derive_keypair(token, pk, sk) != 0)
        die("failed to derive identity");
    print_identity(pk);
    sodium_memzero(sk, sizeof(sk));
    sodium_memzero(token, sizeof(token));
    sodium_memzero(confirm, sizeof(confirm));
}

static void write_u32(FILE *out, uint32_t value)
{
    unsigned char b[4] = {
        (unsigned char)(value >> 24), (unsigned char)(value >> 16),
        (unsigned char)(value >> 8), (unsigned char)value
    };
    if (write_all(out, b, sizeof(b)) != 0)
        die("failed to write encrypted payload");
}

static int read_u32(FILE *in, uint32_t *value)
{
    unsigned char b[4];
    size_t n = fread(b, 1, sizeof(b), in);
    if (n == 0 && feof(in))
        return 0;
    if (n != sizeof(b))
        return -1;
    *value = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
             ((uint32_t)b[2] << 8) | b[3];
    return 1;
}

static void encrypt_payload(const char *input_path, const char *output_path,
                            const unsigned char key[crypto_secretstream_xchacha20poly1305_KEYBYTES])
{
    FILE *in = fopen(input_path, "rb");
    FILE *out = NULL;
    crypto_secretstream_xchacha20poly1305_state state;
    unsigned char header[crypto_secretstream_xchacha20poly1305_HEADERBYTES];
    unsigned char plain[IO_CHUNK];
    unsigned char cipher[IO_CHUNK + crypto_secretstream_xchacha20poly1305_ABYTES];
    unsigned long long cipher_len;

    if (!in)
        die("failed to open input archive");
    out = fopen(output_path, "wb");
    if (!out) {
        fclose(in);
        die("failed to create encrypted payload");
    }
    crypto_secretstream_xchacha20poly1305_init_push(&state, header, key);
    if (write_all(out, PAYLOAD_MAGIC, 8) != 0 ||
        write_all(out, header, sizeof(header)) != 0)
        die("failed to write encrypted payload header");

    for (;;) {
        size_t n = fread(plain, 1, sizeof(plain), in);
        unsigned char tag;
        if (ferror(in))
            die("failed to read input archive");
        tag = (n < sizeof(plain) && feof(in)) ?
            crypto_secretstream_xchacha20poly1305_TAG_FINAL : 0;
        crypto_secretstream_xchacha20poly1305_push(&state, cipher, &cipher_len,
                                                    plain, n, NULL, 0, tag);
        write_u32(out, (uint32_t)cipher_len);
        if (write_all(out, cipher, (size_t)cipher_len) != 0)
            die("failed to write encrypted payload");
        if (tag == crypto_secretstream_xchacha20poly1305_TAG_FINAL)
            break;
    }
    if (fclose(in) != 0 || fclose(out) != 0)
        die("failed to finalize encrypted payload");
}

static void write_wrapped_key(const char *path, const unsigned char *key,
                              const unsigned char recipient[crypto_box_PUBLICKEYBYTES])
{
    unsigned char sealed[crypto_box_SEALBYTES + crypto_secretstream_xchacha20poly1305_KEYBYTES];
    FILE *out;
    crypto_box_seal(sealed, key, crypto_secretstream_xchacha20poly1305_KEYBYTES, recipient);
    out = fopen(path, "wb");
    if (!out)
        die("failed to create wrapped key");
    if (write_all(out, KEY_MAGIC, 8) != 0 || write_all(out, sealed, sizeof(sealed)) != 0 ||
        fclose(out) != 0)
        die("failed to write wrapped key");
}

static const char *option_value(int argc, char **argv, const char *name)
{
    int i;
    for (i = 2; i + 1 < argc; i++)
        if (strcmp(argv[i], name) == 0)
            return argv[i + 1];
    return NULL;
}

static int has_option(int argc, char **argv, const char *name)
{
    int i;
    for (i = 2; i < argc; i++)
        if (strcmp(argv[i], name) == 0)
            return 1;
    return 0;
}

static void command_seal(int argc, char **argv)
{
    const char *recipient_text = option_value(argc, argv, "--recipient");
    const char *input = option_value(argc, argv, "--input");
    const char *payload = option_value(argc, argv, "--payload");
    const char *key_path = option_value(argc, argv, "--key");
    unsigned char recipient[crypto_box_PUBLICKEYBYTES];
    unsigned char key[crypto_secretstream_xchacha20poly1305_KEYBYTES];
    char review[64];

    if (!recipient_text || !input || !payload || !key_path)
        usage();
    if (decode_value(recipient_text, RECIPIENT_PREFIX, recipient, sizeof(recipient)) != 0)
        die("invalid recipient");
    randombytes_buf(key, sizeof(key));
    encrypt_payload(input, payload, key);
    write_wrapped_key(key_path, key, recipient);
    encode_value(REVIEW_PREFIX, key, sizeof(key), review, sizeof(review));
    printf("review_key=%s\n", review);
    sodium_memzero(key, sizeof(key));
}

struct tar_members {
    FILE *payload;
    FILE *manifest;
};

static unsigned long long tar_size(const unsigned char *field, size_t len)
{
    unsigned long long value = 0;
    size_t i;
    for (i = 0; i < len && (field[i] == ' ' || field[i] == '\0'); i++) {}
    for (; i < len && field[i] >= '0' && field[i] <= '7'; i++)
        value = value * 8 + (unsigned long long)(field[i] - '0');
    return value;
}

static int copy_member(FILE *archive, FILE *out, unsigned long long size)
{
    unsigned char buffer[IO_CHUNK];
    while (size > 0) {
        size_t want = size > sizeof(buffer) ? sizeof(buffer) : (size_t)size;
        if (fread(buffer, 1, want, archive) != want || write_all(out, buffer, want) != 0)
            return -1;
        size -= want;
    }
    return 0;
}

static struct tar_members read_feedback_tar(const char *path)
{
    struct tar_members members = { tmpfile(), tmpfile() };
    FILE *archive = fopen(path, "rb");
    unsigned char header[512], discard[512];

    if (!archive || !members.payload || !members.manifest)
        die("failed to open feedback archive");
    for (;;) {
        char name[101];
        unsigned long long size, padded, consumed = 0;
        int all_zero = 1;
        size_t i;
        if (fread(header, 1, sizeof(header), archive) != sizeof(header))
            die("invalid feedback tar header");
        for (i = 0; i < sizeof(header); i++)
            if (header[i] != 0) { all_zero = 0; break; }
        if (all_zero)
            break;
        memcpy(name, header, 100);
        name[100] = '\0';
        size = tar_size(header + 124, 12);
        padded = (size + 511) & ~511ULL;
        if (strcmp(name, "payload.enc") == 0 || strcmp(name, "./payload.enc") == 0) {
            if (copy_member(archive, members.payload, size) != 0)
                die("failed to read payload member");
            consumed = size;
        } else if (strcmp(name, "manifest.json") == 0 || strcmp(name, "./manifest.json") == 0) {
            if (copy_member(archive, members.manifest, size) != 0)
                die("failed to read manifest member");
            consumed = size;
        }
        while (consumed < padded) {
            size_t want = padded - consumed > sizeof(discard) ? sizeof(discard) :
                          (size_t)(padded - consumed);
            if (fread(discard, 1, want, archive) != want)
                die("truncated feedback tar member");
            consumed += want;
        }
    }
    fclose(archive);
    if (ftell(members.payload) == 0 || ftell(members.manifest) == 0)
        die("feedback tar is missing payload.enc or manifest.json");
    rewind(members.payload);
    rewind(members.manifest);
    return members;
}

static void read_manifest_wrapped_key(FILE *manifest, unsigned char *wrapped,
                                      size_t wrapped_len)
{
    char json[8192];
    char *field, *value, *end;
    size_t json_len, decoded_len = 0;

    rewind(manifest);
    json_len = fread(json, 1, sizeof(json) - 1, manifest);
    if (ferror(manifest) || (!feof(manifest) && json_len == sizeof(json) - 1))
        die("manifest is too large or unreadable");
    json[json_len] = '\0';
    field = strstr(json, "\"wrapped_key_hex\"");
    if (!field || !(value = strchr(field, ':')))
        die("manifest is missing wrapped_key_hex");
    value++;
    while (*value == ' ' || *value == '\t' || *value == '\r' || *value == '\n')
        value++;
    if (*value++ != '\"' || !(end = strchr(value, '\"')))
        die("manifest has invalid wrapped_key_hex");
    if (sodium_hex2bin(wrapped, wrapped_len, value, (size_t)(end - value),
                       NULL, &decoded_len, NULL) != 0 || decoded_len != wrapped_len)
        die("manifest has invalid wrapped_key_hex");
}

static void unwrap_manifest_key(FILE *manifest,
                                const unsigned char pk[crypto_box_PUBLICKEYBYTES],
                                const unsigned char sk[crypto_box_SECRETKEYBYTES],
                                unsigned char *key)
{
    unsigned char wrapped[8 + crypto_box_SEALBYTES +
                          crypto_secretstream_xchacha20poly1305_KEYBYTES];
    read_manifest_wrapped_key(manifest, wrapped, sizeof(wrapped));
    if (memcmp(wrapped, KEY_MAGIC, 8) != 0 ||
        crypto_box_seal_open(key, wrapped + 8, sizeof(wrapped) - 8, pk, sk) != 0)
        die("token does not match feedback recipient");
}

static void command_review_key(int argc, char **argv)
{
    const char *manifest_path = option_value(argc, argv, "--manifest");
    int stdin_mode = has_option(argc, argv, "--token-stdin");
    unsigned char pk[crypto_box_PUBLICKEYBYTES], sk[crypto_box_SECRETKEYBYTES];
    unsigned char key[crypto_secretstream_xchacha20poly1305_KEYBYTES];
    char token[TOKEN_MAX + 2], review[64];
    FILE *manifest;

    if (!manifest_path)
        usage();
    manifest = fopen(manifest_path, "rb");
    if (!manifest)
        die("failed to open manifest");
    if (read_secret("Token: ", token, sizeof(token), stdin_mode) != 0 ||
        derive_keypair(token, pk, sk) != 0)
        die("invalid token or identity derivation failed");
    unwrap_manifest_key(manifest, pk, sk, key);
    encode_value(REVIEW_PREFIX, key, sizeof(key), review, sizeof(review));
    printf("review_key=%s\n", review);
    fclose(manifest);
    sodium_memzero(sk, sizeof(sk));
    sodium_memzero(key, sizeof(key));
    sodium_memzero(token, sizeof(token));
}

static void decrypt_payload(FILE *in, const char *output_path, const unsigned char *key)
{
    crypto_secretstream_xchacha20poly1305_state state;
    unsigned char magic[8], header[crypto_secretstream_xchacha20poly1305_HEADERBYTES];
    unsigned char cipher[IO_CHUNK + crypto_secretstream_xchacha20poly1305_ABYTES];
    unsigned char plain[IO_CHUNK];
    unsigned long long plain_len;
    unsigned char tag = 0;
    FILE *verified = tmpfile();
    FILE *out;
    int saw_final = 0;

    if (!verified)
        die("failed to create verification buffer");
    if (fread(magic, 1, sizeof(magic), in) != sizeof(magic) ||
        memcmp(magic, PAYLOAD_MAGIC, sizeof(magic)) != 0 ||
        fread(header, 1, sizeof(header), in) != sizeof(header) ||
        crypto_secretstream_xchacha20poly1305_init_pull(&state, header, key) != 0)
        die("invalid encrypted payload header");
    for (;;) {
        uint32_t cipher_len;
        int rc = read_u32(in, &cipher_len);
        if (rc == 0)
            break;
        if (rc < 0 || cipher_len < crypto_secretstream_xchacha20poly1305_ABYTES ||
            cipher_len > sizeof(cipher) || fread(cipher, 1, cipher_len, in) != cipher_len)
            die("invalid encrypted payload frame");
        if (saw_final || crypto_secretstream_xchacha20poly1305_pull(
                &state, plain, &plain_len, &tag, cipher, cipher_len, NULL, 0) != 0)
            die("encrypted payload authentication failed");
        if (write_all(verified, plain, (size_t)plain_len) != 0)
            die("failed to buffer decrypted output");
        if (tag == crypto_secretstream_xchacha20poly1305_TAG_FINAL)
            saw_final = 1;
        else if (tag != 0)
            die("unsupported encrypted payload tag");
    }
    if (!saw_final)
        die("encrypted payload is truncated");
    rewind(verified);
    out = fopen(output_path, "wb");
    if (!out)
        die("failed to create decrypted output");
    for (;;) {
        size_t n = fread(plain, 1, sizeof(plain), verified);
        if (n > 0 && write_all(out, plain, n) != 0)
            die("failed to write decrypted output");
        if (n < sizeof(plain)) {
            if (ferror(verified))
                die("failed to read verified plaintext");
            break;
        }
    }
    if (fclose(verified) != 0 || fclose(out) != 0)
        die("failed to finalize decrypted output");
}

static void command_decrypt(int argc, char **argv)
{
    const char *input = option_value(argc, argv, "--input");
    const char *output = option_value(argc, argv, "--output");
    int review_mode = has_option(argc, argv, "--review-key");
    int stdin_mode = has_option(argc, argv, "--token-stdin");
    struct tar_members members;
    unsigned char key[crypto_secretstream_xchacha20poly1305_KEYBYTES];
    char secret[TOKEN_MAX + 2];

    if (!input || !output)
        usage();
    members = read_feedback_tar(input);
    if (read_secret(review_mode ? "Review key: " : "Token: ", secret, sizeof(secret), stdin_mode) != 0)
        die("failed to read decryption secret");
    if (review_mode) {
        if (decode_value(secret, REVIEW_PREFIX, key, sizeof(key)) != 0)
            die("invalid review key");
    } else {
        unsigned char pk[crypto_box_PUBLICKEYBYTES], sk[crypto_box_SECRETKEYBYTES];
        if (derive_keypair(secret, pk, sk) != 0)
            die("invalid token or identity derivation failed");
        unwrap_manifest_key(members.manifest, pk, sk, key);
        sodium_memzero(sk, sizeof(sk));
    }
    decrypt_payload(members.payload, output, key);
    fclose(members.payload);
    fclose(members.manifest);
    sodium_memzero(key, sizeof(key));
    sodium_memzero(secret, sizeof(secret));
}

int main(int argc, char **argv)
{
    if (sodium_init() < 0)
        die("libsodium initialization failed");
    if (argc < 2)
        usage();
    if (strcmp(argv[1], "identity") == 0)
        command_identity(argc, argv);
    else if (strcmp(argv[1], "seal") == 0)
        command_seal(argc, argv);
    else if (strcmp(argv[1], "review-key") == 0)
        command_review_key(argc, argv);
    else if (strcmp(argv[1], "decrypt") == 0)
        command_decrypt(argc, argv);
    else
        usage();
    return 0;
}
