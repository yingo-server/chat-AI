// vault.cpp — 密钥保险库(SHA-256 keystream XOR + 反调试)
//
// 设计:
//   vault.bin 格式:
//     [4 bytes]  magic "VLT1"
//     [16 bytes] salt(随机)
//     [N bytes]  ciphertext(URL)  = URL XOR keystream(master, salt, 0)
//     [4 bytes]  SEP = 0xFF 0xFE 0xFD 0xFC
//     [M bytes]  ciphertext(KEY)  = KEY XOR keystream(master, salt2, 0), salt2 = salt ^ [0]=0xA5
//     [32 bytes] trailer = SHA256(master)(用于检测 master 不匹配)
//
//   keystream(master, salt, n): 逐 32 字节块 SHA256(master 32B || salt 16B || counter 8B-BE)
//
// master key 由 Dart 端从 Android Keystore 派生并注入(vault_set_master)。
// 一切错误以负值返回;成功返回 >= 0。

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
#include <android/log.h>

// 构建时注入的混淆 master(CI 生成)。本地缺失时降级为未嵌入。
#if __has_include("vault_master.h")
#include "vault_master.h"
#endif
#ifndef VAULT_HAS_EMBEDDED_MASTER
#define VAULT_HAS_EMBEDDED_MASTER 0
#endif

#define LOG_TAG "VAULT"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

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
        // 标准轮转:h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
        // 原实现漏掉了 f=e,导致 f 永不更新 → SHA256 全错
        uint32_t e_new = d2 + t1;
        h=g; g=f; f=e; e=e_new; d2=c2; c2=b; b=a; a=t1+t2;
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

// ==================== keystream ====================
// 输入缓冲: master(32) || salt(16) || counter(8, big-endian)
// 缓冲区布局必须与 Dart 端 encrypt_secrets.dart 完全一致!
static void keystream(const uint8_t master[32], const uint8_t salt[16],
                      uint8_t *out, size_t n) {
    uint8_t blk[56];               // 32 + 16 + 8
    memcpy(blk, master, 32);
    memcpy(blk + 32, salt, 16);
    // NOTE: counter 写在 [48..55],绝不覆盖 salt!
    uint64_t cursor = 0;
    sha256_ctx c;
    uint8_t hash[32];
    size_t off = 0;
    while (off < n) {
        for (int i = 7; i >= 0; i--) {
            blk[48 + (7-i)] = (uint8_t)((cursor >> (i*8)) & 0xff);
        }
        sha256_init(&c);
        sha256_update(&c, blk, sizeof(blk));
        sha256_final(&c, hash);
        size_t take = (n - off) < 32 ? (n - off) : 32;
        memcpy(out + off, hash, take);
        off += take;
        cursor++;
    }
}

// ==================== 状态 ====================
static uint8_t  s_url[512] = {0};
static uint8_t  s_key[512] = {0};
static size_t   s_url_len = 0;
static size_t   s_key_len = 0;
static uint8_t  s_master[32] = {0};
static int      s_master_set = 0;
static int      s_initialized = 0;
static int      s_tampered = 0;
static pthread_mutex_t s_lock = PTHREAD_MUTEX_INITIALIZER;
static const uint8_t SEP[4] = {0xFF, 0xFE, 0xFD, 0xFC};

// ==================== 反调试 / 反 root / 反模拟器 ====================
static int is_debugger_attached() {
    char buf[512];
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
    // build.prop 整行子串匹配太宽("sdk"/"=1" 任何位置都命中)→ 改为精确键值对检查
    FILE *f = fopen("/system/build.prop", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            // 仅匹配具体属性值,不做任意子串扫描
            if (strstr(line, "ro.kernel.qemu=1") ||
                strstr(line, "ro.build.characteristics=emulator")) {
                fclose(f); return 1;
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

// ==================== 8 位错误码(模块 30)====================
// 返回约定:成功 >= 0;错误 = 负的 8 位码(如 -30000002)
#define E_N01 (-30000001) // security check failed (tampered)
#define E_N02 (-30000002) // master not set
#define E_N03 (-30000003) // buffer too small
#define E_N04 (-30000004) // parse failed (magic/length/separator)
#define E_N09 (-30000009) // not initialized
#define E_N10 (-30000010) // master length invalid
#define E_N11 (-30000011) // trailer SHA256(master) mismatch

// 计算 SHA256(master) 并填充 32 字节
static void sha256_of_master(const uint8_t master[32], uint8_t out[32]) {
    sha256_ctx c; sha256_init(&c); sha256_update(&c, master, 32); sha256_final(&c, out);
}

// ==================== 导出 API ====================
// 成功返回 0;失败返回负的 8 位错误码
__attribute__((visibility("default")))
int vault_set_master(const uint8_t *key, int len) {
    if (!key || len != 32) return E_N10;
    pthread_mutex_lock(&s_lock);
    memcpy(s_master, key, 32);
    s_master_set = 1;
    pthread_mutex_unlock(&s_lock);
    return 0;
}

static int parse_vault_locked(const uint8_t *data, size_t len) {
    if (len < 4 + 16 + 4 + 32) return E_N04;
    if (memcmp(data, "VLT1", 4) != 0) return E_N04;
    const uint8_t *salt = data + 4;
    const uint8_t *body  = data + 20;
    size_t body_len = len - 4 - 16 - 32;
    if (body_len < 4 + 1 + 1) return E_N04; // 至少 sep + 1 + 1

    // 校验 trailer: SHA256(master || salt || 密文) — 同时验证 master 正确性与内容完整性
    uint8_t expected[32];
    {
        sha256_ctx c;
        sha256_init(&c);
        sha256_update(&c, s_master, 32);
        sha256_update(&c, data, len - 32);   // 含 "VLT1" 魔数,与 Dart 端 bin 范围一致
        sha256_final(&c, expected);
    }
    if (memcmp(data + len - 32, expected, 32) != 0) return E_N11;

    // 找分隔符
    size_t sep_off = (size_t)-1;
    for (size_t i = 0; i + 4 <= body_len; i++) {
        if (memcmp(body + i, SEP, 4) == 0) { sep_off = i; break; }
    }
    if (sep_off == (size_t)-1) return E_N04;
    size_t url_ct_len = sep_off;
    size_t key_ct_len = body_len - 4 - sep_off;
    if (url_ct_len == 0 || key_ct_len == 0) return E_N04;
    if (url_ct_len >= sizeof(s_url) || key_ct_len >= sizeof(s_key)) return E_N03;

    const uint8_t *url_ct = body;
    const uint8_t *key_ct = body + sep_off + 4;

    // URL: XOR keystream(master, salt)
    keystream(s_master, salt, s_url, url_ct_len);
    for (size_t i = 0; i < url_ct_len; i++) s_url[i] ^= url_ct[i];
    s_url_len = url_ct_len;
    s_url[url_ct_len] = 0;

    // KEY: XOR keystream(master, salt2), salt2[0] ^= 0xA5
    uint8_t salt2[16]; memcpy(salt2, salt, 16); salt2[0] ^= 0xA5;
    keystream(s_master, salt2, s_key, key_ct_len);
    for (size_t i = 0; i < key_ct_len; i++) s_key[i] ^= key_ct[i];
    s_key_len = key_ct_len;
    s_key[key_ct_len] = 0;

    // 明文合理性检查:URL 应以 http 开头
    if (s_url_len < 4 ||
        memcmp(s_url, "http", 4) != 0) return E_N04;
    return 0;
}

__attribute__((visibility("default")))
int vault_init(const uint8_t *vault_bin, int vault_len) {
    pthread_mutex_lock(&s_lock);
    // 重置状态(允许重新初始化)
    s_tampered = 0;
    s_initialized = 0;
    memset(s_url, 0, sizeof(s_url));
    memset(s_key, 0, sizeof(s_key));
    s_url_len = s_key_len = 0;

#if VAULT_HAS_EMBEDDED_MASTER
    if (!s_master_set) {
        decode_master(s_master);
        s_master_set = 1;
    }
#endif

    if (!s_master_set) {
        pthread_mutex_unlock(&s_lock);
        return E_N02;
    }
    if (!vault_bin || vault_len <= 0) {
        pthread_mutex_unlock(&s_lock);
        return E_N04;
    }
    if (!security_check()) {
        // NOTE: 检测到 root/调试器/模拟器时【绝不】替换真实凭据 —— 那会让正常用户
        // 拿到 "http://invalid.local" 从而显示"请检查配置"。仅记录日志,继续正常初始化。
        s_tampered = 1;
        LOGE("[vault] security_check flagged (root/debugger/emulator) - continuing with REAL data");
    } else {
        LOGI("[vault] security_check passed");
    }
    int rc = parse_vault_locked(vault_bin, (size_t)vault_len);
    if (rc == 0) {
        s_initialized = 1;
        LOGI("[vault] parse OK url_len=%zu key_len=%zu", s_url_len, s_key_len);
    } else {
        LOGE("[vault] parse FAILED rc=%d", rc);
    }
    pthread_mutex_unlock(&s_lock);
    return rc;
}

// 诊断:计算 SHA256(用于主机自测校验手写实现)
__attribute__((visibility("default")))
void vault_debug_sha256(const uint8_t *in, int len, uint8_t out[32]) {
    sha256_ctx c; sha256_init(&c); sha256_update(&c, in, (size_t)len); sha256_final(&c, out);
}

// 诊断导出:返回写入长度。用于主机自测 / logcat 排查。
__attribute__((visibility("default")))
int vault_debug_state(char *out, int out_len) {
    char tmp[256];
    int sec = 0;
    sec = security_check() ? 1 : 0;
    int n = snprintf(tmp, sizeof(tmp),
                     "master_set=%d initialized=%d tampered=%d seccheck=%d url_len=%d key_len=%d",
                     s_master_set, s_initialized, s_tampered, sec,
                     (int)s_url_len, (int)s_key_len);
    if (n < 0) return -1;
    if (n >= out_len) n = out_len - 1;
    memcpy(out, tmp, (size_t)n);
    out[n] = 0;
    return n;
}

// 成功:返回明文长度(>0);错误:返回负的 8 位码;未初始化:0
__attribute__((visibility("default")))
int vault_get_endpoint(char *out, int out_len) {
    pthread_mutex_lock(&s_lock);
    if (!s_initialized) { pthread_mutex_unlock(&s_lock); return E_N09; }
    int n = (int)s_url_len;
    if (n >= out_len) { pthread_mutex_unlock(&s_lock); return E_N03; }
    memcpy(out, s_url, n);
    out[n] = 0;
    pthread_mutex_unlock(&s_lock);
    return n;
}

__attribute__((visibility("default")))
int vault_get_api_key(char *out, int out_len) {
    pthread_mutex_lock(&s_lock);
    if (!s_initialized) { pthread_mutex_unlock(&s_lock); return E_N09; }
    int n = (int)s_key_len;
    if (n >= out_len) { pthread_mutex_unlock(&s_lock); return E_N03; }
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
    s_master_set = 0;
    s_tampered = 0;
    pthread_mutex_unlock(&s_lock);
}

}  // extern "C"