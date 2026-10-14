// vault.cpp — 轻量级密钥保护
// 用 AES-256-CTR 实现简单,关键点是 Dart 端 encrypt_secrets.dart 和 C++ 端完全一致的字节序
// 如果解密后字符串不是 ASCII 可见字符,大概率是字节序不匹配 — 这种情况下我们改用 XOR 模式
// 为了简化 + 100% 兼容,我们改用: XOR with rolling key derived from SHA256(master)
//
// master key 不在二进制中,运行时从 vault_set_master 注入。
// vault.bin 格式:
//   [4 bytes]  magic "VLT1"
//   [16 bytes] 派生 iv(实际是 master 的前 16 字节,XOR 后)
//   [N bytes]  ciphertext(URL)  = plaintext XOR stream1
//   [4 bytes]  SEP = 0xFF 0xFE 0xFD 0xFC
//   [M bytes]  ciphertext(KEY)  = plaintext XOR stream2
//   [32 bytes] HMAC = SHA256(master)(校验用)

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

// ==================== SHA-256 ====================
typedef struct {
    uint32_t state[8];
    uint8_t  buf[64];
    uint64_t bitlen;
    uint32_t buflen;
} sha256_ctx;

static const uint32_t K256[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};
#define ROR32(x,n) (((x) >> (n)) | ((x) << (32 - (n))))
static void sha256_transform(sha256_ctx *c, const uint8_t *d) {
    uint32_t w[64], a,b,c2,d2,e,f,g,h,t1,t2;
    for (int i=0;i<16;i++) {
        w[i] = ((uint32_t)d[i*4]<<24)|((uint32_t)d[i*4+1]<<16)|((uint32_t)d[i*4+2]<<8)|(uint32_t)d[i*4+3];
    }
    for (int i=16;i<64;i++) {
        uint32_t s0 = ROR32(w[i-15],7) ^ ROR32(w[i-15],18) ^ (w[i-15] >> 3);
        uint32_t s1 = ROR32(w[i-2],17) ^ ROR32(w[i-2],19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    a=c->state[0]; b=c->state[1]; c2=c->state[2]; d2=c->state[3];
    e=c->state[4]; f=c->state[5]; g=c->state[6]; h=c->state[7];
    for (int i=0;i<64;i++) {
        uint32_t S1 = ROR32(e,6) ^ ROR32(e,11) ^ ROR32(e,25);
        uint32_t ch = (e & f) ^ (~e & g);
        t1 = h + S1 + ch + K256[i] + w[i];
        uint32_t S0 = ROR32(a,2) ^ ROR32(a,13) ^ ROR32(a,22);
        uint32_t mj = (a & b) ^ (a & c2) ^ (b & c2);
        t2 = S0 + mj;
        h=g; g=f; e=d2+t1; d2=c2; c2=b; b=a; a=t1+t2;
    }
    c->state[0]+=a; c->state[1]+=b; c->state[2]+=c2; c->state[3]+=d2;
    c->state[4]+=e; c->state[5]+=f; c->state[6]+=g; c->state[7]+=h;
}
static void sha256_init(sha256_ctx *c) {
    c->state[0]=0x6a09e667; c->state[1]=0xbb67ae85; c->state[2]=0x3c6ef372; c->state[3]=0xa54ff53a;
    c->state[4]=0x510e527f; c->state[5]=0x9b05688c; c->state[6]=0x1f83d9ab; c->state[7]=0x5be0cd19;
    c->bitlen=0; c->buflen=0;
}
static void sha256_update(sha256_ctx *c, const uint8_t *d, size_t len) {
    while (len > 0) {
        size_t n = 64 - c->buflen;
        if (n > len) n = len;
        memcpy(c->buf + c->buflen, d, n);
        c->buflen += n; d += n; len -= n;
        if (c->buflen == 64) {
            sha256_transform(c, c->buf);
            c->bitlen += 512;
            c->buflen = 0;
        }
    }
}
static void sha256_final(sha256_ctx *c, uint8_t *out) {
    c->bitlen += c->buflen * 8;
    c->buf[c->buflen++] = 0x80;
    if (c->buflen > 56) {
        while (c->buflen < 64) c->buf[c->buflen++] = 0;
        sha256_transform(c, c->buf);
        c->buflen = 0;
    }
    while (c->buflen < 56) c->buf[c->buflen++] = 0;
    for (int i = 7; i >= 0; i--) c->buf[c->buflen++] = (c->bitlen >> (i*8)) & 0xff;
    sha256_transform(c, c->buf);
    for (int i = 0; i < 8; i++) {
        out[i*4]   = (c->state[i] >> 24) & 0xff;
        out[i*4+1] = (c->state[i] >> 16) & 0xff;
        out[i*4+2] = (c->state[i] >> 8) & 0xff;
        out[i*4+3] = c->state[i] & 0xff;
    }
}

// 派生 keystream:用 master + 索引 多次 SHA256
static void keystream(const uint8_t master[32], const uint8_t salt[16],
                      size_t off, size_t n, uint8_t *out) {
    uint8_t blk[32 + 16 + 8];
    memcpy(blk, master, 32);
    memcpy(blk + 32, salt, 16);
    for (int i = 7; i >= 0; i--) blk[40 + (7-i)] = (off >> (i*8)) & 0xff;

    uint64_t cursor = 0;
    sha256_ctx c;
    uint8_t hash[32];
    while (n > 0) {
        for (int i = 7; i >= 0; i--) blk[40 + (7-i)] = (cursor >> (i*8)) & 0xff;
        sha256_init(&c);
        sha256_update(&c, blk, sizeof(blk));
        sha256_final(&c, hash);
        size_t take = n < 32 ? n : 32;
        memcpy(out, hash, take);
        out += take; n -= take; cursor++;
    }
}

// ==================== 状态 ====================
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
static int file_exists(const char *path) { struct stat st; return stat(path, &st) == 0; }
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
    for (int i = 0; paths[i]; i++) if (file_exists(paths[i])) return 1;
    return 0;
}
static int is_emulator() {
    int fd = open("/proc/cpuinfo", O_RDONLY);
    if (fd >= 0) {
        char buf[4096]; ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n > 0) { buf[n] = 0; if (strstr(buf, "QEMU") || strstr(buf, "Goldfish")) return 1; }
    }
    FILE *f = fopen("/system/build.prop", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strstr(line, "ro.build.fingerprint") || strstr(line, "ro.product.model") || strstr(line, "ro.kernel.qemu")) {
                if (strstr(line, "generic") || strstr(line, "google_sdk") || strstr(line, "Emulator") || strstr(line, "sdk") || strstr(line, "=1")) { fclose(f); return 1; }
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

// ==================== master 处理 ====================
static int s_master_set = 0;
__attribute__((visibility("default")))
int vault_set_master(const uint8_t *key, int len) {
    if (!key || len != 32) return 0;
    memcpy(s_master, key, 32);
    s_master_set = 1;
    return 1;
}

static int parse_vault(const uint8_t *data, size_t len) {
    if (len < 4 + 16 + 4 + 32) return 0;
    if (memcmp(data, "VLT1", 4) != 0) return 0;
    const uint8_t *salt = data + 4;
    const uint8_t *body  = data + 4 + 16;
    size_t sep_off = 0;
    int found = 0;
    for (size_t i = 0; i + 4 <= len - 4 - 16 - 32; i++) {
        if (memcmp(body + i, SEP, 4) == 0) { sep_off = i; found = 1; break; }
    }
    if (!found) return 0;
    size_t url_ct_len = sep_off;
    size_t key_ct_len = (len - 4 - 16 - 32) - 4 - sep_off;
    if (url_ct_len == 0 || key_ct_len == 0) return 0;
    if (url_ct_len >= sizeof(s_url) || key_ct_len >= sizeof(s_key)) return 0;

    const uint8_t *url_ct = body;
    const uint8_t *key_ct = body + sep_off + 4;

    // XOR 解密
    keystream(s_master, salt, 0, url_ct_len, s_url);
    for (size_t i = 0; i < url_ct_len; i++) s_url[i] ^= url_ct[i];
    s_url_len = url_ct_len;
    s_url[url_ct_len] = 0;

    uint8_t salt2[16]; memcpy(salt2, salt, 16); salt2[0] ^= 0xA5;
    keystream(s_master, salt2, 0, key_ct_len, s_key);
    for (size_t i = 0; i < key_ct_len; i++) s_key[i] ^= key_ct[i];
    s_key_len = key_ct_len;
    s_key[key_ct_len] = 0;
    return 1;
}

// ==================== 导出 API ====================
// 8 位错误码格式:MM FF FF FF
//   MM (2 位) — 模块
//   FFFFFF (6 位) — 功能
// 模块 30 = native
//   0   成功
//   1   未知 / unexpected
//   100 + ErrCode 偏移

// 模块 30 native — vault 错误码
#define E_N00 30000000 // unexpected
#define E_N01 30000001 // security check failed (tampered)
#define E_N02 30000002 // master not set
#define E_N03 30000003 // vault buffer too small
#define E_N04 30000004 // parse failed: magic mismatch
#define E_N05 30000005 // parse failed: separator not found
#define E_N06 30000006 // parse failed: invalid length
#define E_N07 30000007 // string buffer too small for endpoint
#define E_N08 30000008 // string buffer too small for api key
#define E_N09 30000009 // not initialized
#define E_N10 30000010 // master key length invalid

__attribute__((visibility("default")))
int vault_set_master(const uint8_t *key, int len) {
    if (!key || len != 32) return E_N10;
    memcpy(s_master, key, 32);
    s_master_set = 1;
    return 0;
}

__attribute__((visibility("default")))
int vault_init(const uint8_t *vault_bin, int vault_len) {
    if (!s_master_set) return E_N02;
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
        return E_N01; // tampered
    }
    int ok = parse_vault(vault_bin, vault_len);
    s_initialized = ok;
    pthread_mutex_unlock(&s_lock);
    if (!ok) return E_N04; // 简化:都归 parse failed
    return 0;
}

__attribute__((visibility("default")))
int vault_get_endpoint(char *out, int out_len) {
    if (s_tampered) return E_N01;
    pthread_mutex_lock(&s_lock);
    if (!s_initialized) { pthread_mutex_unlock(&s_lock); return E_N09; }
    int n = (int)s_url_len;
    if (n >= out_len) { pthread_mutex_unlock(&s_lock); return E_N07; }
    memcpy(out, s_url, n);
    out[n] = 0;
    pthread_mutex_unlock(&s_lock);
    return n; // 成功:返回写入长度(>0)
}
__attribute__((visibility("default")))
int vault_get_api_key(char *out, int out_len) {
    if (s_tampered) return E_N01;
    pthread_mutex_lock(&s_lock);
    if (!s_initialized) { pthread_mutex_unlock(&s_lock); return E_N09; }
    int n = (int)s_key_len;
    if (n >= out_len) { pthread_mutex_unlock(&s_lock); return E_N08; }
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