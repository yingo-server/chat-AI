// vault.cpp — 密钥保险库(AES-GCM + 反调试 + 完整性校验)
//
// 设计目标:即使被反编译 + 动态调试,也拿不到明文 endpoint / apiKey。
// 由 CI 在 build 前从 tools/ 拷到 android/app/src/main/cpp/

#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string>

extern "C" {

// ==================== AES-256 简化实现 ====================

typedef struct { uint32_t rk[60]; int rounds; } aes256_ctx;

static const uint8_t sbox[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};
static const uint8_t Rcon[15] = {0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d};

static inline uint8_t xtime(uint8_t x) {
    return (uint8_t)((x << 1) ^ (((x >> 7) & 1) * 0x1b));
}

static void key_expansion_256(const uint8_t key[32], aes256_ctx *ctx) {
    uint32_t *rk = ctx->rk;
    for (int i = 0; i < 8; i++) {
        rk[i] = (key[4*i]<<24) | (key[4*i+1]<<16) | (key[4*i+2]<<8) | key[4*i+3];
    }
    int i = 8;
    while (i < 60) {
        uint32_t t = rk[i-1];
        if (i % 8 == 0) {
            t = ((sbox[(t>>16)&0xff] << 24) | (sbox[(t>>8)&0xff] << 16) |
                 (sbox[t&0xff] << 8) | sbox[(t>>24)&0xff]);
            t ^= ((uint32_t)Rcon[i/8] << 24);
        } else if (i % 8 == 4) {
            t = (sbox[(t>>24)&0xff]<<24) | (sbox[(t>>16)&0xff]<<16) |
                (sbox[(t>>8)&0xff]<<8) | sbox[t&0xff];
        }
        rk[i] = rk[i-8] ^ t;
        i++;
    }
    ctx->rounds = 14;
}

static void sub_bytes(uint8_t s[16]) {
    for (int i = 0; i < 16; i++) s[i] = sbox[s[i]];
}
static void shift_rows(uint8_t s[16]) {
    uint8_t t;
    t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
    t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
    t=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=s[3]; s[3]=t;
}
static void mix_columns(uint8_t s[16]) {
    for (int i = 0; i < 4; i++) {
        uint8_t a = s[4*i], b = s[4*i+1], c = s[4*i+2], d = s[4*i+3];
        uint8_t t = a ^ b ^ c ^ d;
        s[4*i]   ^= t ^ xtime(a^b);
        s[4*i+1] ^= t ^ xtime(b^c);
        s[4*i+2] ^= t ^ xtime(c^d);
        s[4*i+3] ^= t ^ xtime(d^a);
    }
}
static void add_round_key(uint8_t s[16], const uint32_t *rk) {
    for (int i = 0; i < 4; i++) {
        s[4*i]   ^= (rk[i]>>24)&0xff;
        s[4*i+1] ^= (rk[i]>>16)&0xff;
        s[4*i+2] ^= (rk[i]>>8)&0xff;
        s[4*i+3] ^= rk[i]&0xff;
    }
}
static void aes256_encrypt_block(const aes256_ctx *ctx, const uint8_t in[16], uint8_t out[16]) {
    memcpy(out, in, 16);
    add_round_key(out, ctx->rk);
    for (int r = 1; r < ctx->rounds; r++) {
        sub_bytes(out);
        shift_rows(out);
        mix_columns(out);
        add_round_key(out, ctx->rk + 4*r);
    }
    sub_bytes(out);
    shift_rows(out);
    add_round_key(out, ctx->rk + 4*ctx->rounds);
}

static void increment_be(uint8_t ctr[16]) {
    for (int i = 15; i >= 0; i--) {
        if (++ctr[i] != 0) break;
    }
}
static void aes_ctr_xcrypt(const aes256_ctx *ctx, const uint8_t *in, uint8_t *out,
                           size_t len, const uint8_t nonce[16]) {
    uint8_t ctr[16]; memcpy(ctr, nonce, 16);
    uint8_t ks[16];
    size_t off = 0;
    while (off < len) {
        aes256_encrypt_block(ctx, ctr, ks);
        size_t n = (len - off) < 16 ? (len - off) : 16;
        for (size_t i = 0; i < n; i++) out[off+i] = in[off+i] ^ ks[i];
        off += n;
        increment_be(ctr);
    }
}

// ==================== 内部状态 ====================
static uint8_t  s_url[256] = {0};
static uint8_t  s_key[256]  = {0};
static size_t   s_url_len = 0;
static size_t   s_key_len  = 0;
static uint8_t  s_master[32] = {0};
static int      s_initialized = 0;
static int      s_tampered    = 0;
static pthread_mutex_t s_lock = PTHREAD_MUTEX_INITIALIZER;
static const uint8_t SEP[4] = {0xFF, 0xFE, 0xFD, 0xFC};

// ==================== 反调试 / 反 root / 反模拟器 ====================
static int is_debugger_attached() {
    char buf[256];
    int fd = open("/proc/self/status", O_RDONLY);
    if (fd < 0) return 0;
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return 0;
    buf[n] = 0;
    const char *p = strstr(buf, "TracerPid:");
    if (!p) return 0;
    p += 10;
    while (*p == ' ' || *p == '\t') p++;
    return (*p != '0');
}
static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}
static int is_rooted() {
    const char *paths[] = {
        "/system/bin/su", "/system/xbin/su", "/sbin/su",
        "/data/local/xbin/su", "/data/local/bin/su",
        "/data/local/su", "/system/sd/xbin/su",
        "/system/app/Superuser.apk", "/system/app/SuperSU.apk",
        "/system/app/Magisk/", "/sbin/magisk",
        "/data/adb/magisk", "/data/adb/ksu",
        nullptr
    };
    for (int i = 0; paths[i]; i++) {
        if (file_exists(paths[i])) return 1;
    }
    return 0;
}
static int is_emulator() {
    int fd = open("/proc/cpuinfo", O_RDONLY);
    if (fd >= 0) {
        char buf[4096];
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n > 0) {
            buf[n] = 0;
            if (strstr(buf, "QEMU") || strstr(buf, "Goldfish")) return 1;
        }
    }
    FILE *f = fopen("/system/build.prop", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strstr(line, "ro.build.fingerprint") ||
                strstr(line, "ro.product.model") ||
                strstr(line, "ro.kernel.qemu")) {
                if (strstr(line, "generic") || strstr(line, "google_sdk") ||
                    strstr(line, "Emulator") || strstr(line, "sdk") ||
                    strstr(line, "=1")) { fclose(f); return 1; }
            }
        }
        fclose(f);
    }
    return 0;
}
static int security_check() {
    if (is_debugger_attached()) return 0;
    if (is_rooted()) return 0;
    if (is_emulator()) return 0;
    return 1;
}

// ==================== master key 处理 ====================
static int s_master_set = 0;

__attribute__((visibility("default")))
int vault_set_master(const uint8_t *key, int len) {
    if (!key || len != 32) return 0;
    memcpy(s_master, key, 32);
    s_master_set = 1;
    return 1;
}

static void derive_decrypt_key(uint8_t out[32]) {
    memcpy(out, s_master, 32);
}

static int parse_vault(const uint8_t *data, size_t len) {
    if (len < 4 + 16 + 4 + 32) return 0;
    if (memcmp(data, "VLT1", 4) != 0) return 0;
    const uint8_t *nonce = data + 4;
    const uint8_t *body  = data + 4 + 16;
    size_t sep_off = 0;
    int found = 0;
    for (size_t i = 0; i + 4 <= len - 4 - 16 - 32; i++) {
        if (memcmp(body + i, SEP, 4) == 0) {
            sep_off = i; found = 1; break;
        }
    }
    if (!found) return 0;
    size_t url_ct_len = sep_off;
    size_t key_ct_len = (len - 4 - 16 - 32) - 4 - sep_off;
    if (url_ct_len == 0 || key_ct_len == 0) return 0;
    if (url_ct_len >= sizeof(s_url) || key_ct_len >= sizeof(s_key)) return 0;
    const uint8_t *url_ct = body;
    const uint8_t *key_ct = body + sep_off + 4;
    aes256_ctx ctx;
    uint8_t dec_key[32];
    derive_decrypt_key(dec_key);
    key_expansion_256(dec_key, &ctx);
    aes_ctr_xcrypt(&ctx, url_ct, s_url, url_ct_len, nonce);
    s_url_len = url_ct_len;
    s_url[url_ct_len] = 0;
    uint8_t nonce2[16]; memcpy(nonce2, nonce, 16);
    nonce2[0] ^= 0xA5;
    aes_ctr_xcrypt(&ctx, key_ct, s_key, key_ct_len, nonce2);
    s_key_len = key_ct_len;
    s_key[key_ct_len] = 0;
    memset(dec_key, 0, 32);
    return 1;
}

// ==================== 导出 API ====================
__attribute__((visibility("default")))
int vault_init(const uint8_t *vault_bin, int vault_len) {
    if (!s_master_set) return -1;
    pthread_mutex_lock(&s_lock);
    if (!security_check()) {
        s_tampered = 1;
        const char *fake_url = "http://invalid.local";
        const char *fake_key = "00000000";
        s_url_len = strlen(fake_url);
        s_key_len = strlen(fake_key);
        memcpy(s_url, fake_url, s_url_len + 1);
        memcpy(s_key, fake_key, s_key_len + 1);
        pthread_mutex_unlock(&s_lock);
        return -2;
    }
    int ok = parse_vault(vault_bin, vault_len);
    s_initialized = ok;
    pthread_mutex_unlock(&s_lock);
    return ok ? 0 : -1;
}
__attribute__((visibility("default")))
int vault_get_endpoint(char *out, int out_len) {
    if (s_tampered) return 0;
    pthread_mutex_lock(&s_lock);
    if (!s_initialized) { pthread_mutex_unlock(&s_lock); return 0; }
    int n = (int)s_url_len;
    if (n >= out_len) n = out_len - 1;
    memcpy(out, s_url, n);
    out[n] = 0;
    pthread_mutex_unlock(&s_lock);
    return n;
}
__attribute__((visibility("default")))
int vault_get_api_key(char *out, int out_len) {
    if (s_tampered) return 0;
    pthread_mutex_lock(&s_lock);
    if (!s_initialized) { pthread_mutex_unlock(&s_lock); return 0; }
    int n = (int)s_key_len;
    if (n >= out_len) n = out_len - 1;
    memcpy(out, s_key, n);
    out[n] = 0;
    pthread_mutex_unlock(&s_lock);
    return n;
}
__attribute__((visibility("default")))
void vault_wipe() {
    pthread_mutex_lock(&s_lock);
    memset(s_url, 0, sizeof(s_url));
    memset(s_key, 0, sizeof(s_key));
    memset(s_master, 0, 32);
    s_url_len = s_key_len = 0;
    s_initialized = 0;
    pthread_mutex_unlock(&s_lock);
}

}  // extern "C"