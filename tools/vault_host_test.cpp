// tools/vault_host_test.cpp
// Runs the REAL vault.cpp chain on a host (CI runner) against a real vault.bin.
// Prints every step; exits non-zero on any mismatch.
//
// Build:  g++ -std=c++17 -I tools/android_shim -I tools -o /tmp/vault_test \
//             tools/vault_host_test.cpp tools/vault.cpp
// Run:    /tmp/vault_test --vault=/tmp/vault.bin \
//             --expect-endpoint="http://..." --expect-key="..."

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>

extern "C" {
int vault_init(const unsigned char *bin, int len);
int vault_get_endpoint(char *out, int outLen);
int vault_get_api_key(char *out, int outLen);
int vault_set_master(const unsigned char *key, int len);
void vault_wipe();
}

static std::vector<unsigned char> readFile(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(3); }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<unsigned char> out((size_t)n);
    size_t rd = fread(out.data(), 1, (size_t)n, f);
    fclose(f);
    if ((long)rd != n) { fprintf(stderr, "short read\n"); exit(3); }
    return out;
}

static void hex(const char *label, const unsigned char *d, size_t n) {
    printf("%-22s (%zuB): ", label, n);
    for (size_t i = 0; i < n; i++) printf("%02x", d[i]);
    printf("\n");
}

int main(int argc, char **argv) {
    const char *vaultPath = nullptr, *expectEp = nullptr, *expectKey = nullptr;
    for (int i = 1; i < argc; i++) {
        if (!strncmp(argv[i], "--vault=", 8)) vaultPath = argv[i] + 8;
        else if (!strncmp(argv[i], "--expect-endpoint=", 18)) expectEp = argv[i] + 18;
        else if (!strncmp(argv[i], "--expect-key=", 13)) expectKey = argv[i] + 13;
    }
    if (!vaultPath || !expectEp || !expectKey) {
        fprintf(stderr, "usage: --vault=PATH --expect-endpoint=URL --expect-key=KEY\n");
        return 2;
    }

    printf("========== VAULT HOST SELF-TEST ==========\n");
    auto bin = readFile(vaultPath);
    printf("vault.bin size        : %zu\n", bin.size());
    hex("vault.bin[0..8]", bin.data(), bin.size() < 8 ? bin.size() : 8);

    int failures = 0;

    // ---- Step 1: init with embedded master (generated header) ----
    int rc = vault_init(bin.data(), (int)bin.size());
    printf("vault_init()          : %d %s\n", rc, rc == 0 ? "(OK)" : "(FAIL)");
    if (rc != 0) failures++;

    {
        char st[256] = {0};
        extern int vault_debug_state(char *, int);
        int sn = vault_debug_state(st, sizeof(st));
        printf("vault_debug_state()   : %d -> %s\n", sn, st);
    }

    char buf[1024];
    memset(buf, 0, sizeof(buf));
    int n = vault_get_endpoint(buf, sizeof(buf));
    printf("vault_get_endpoint()  : %d -> '%s'\n", n, buf);
    if (n <= 0 || strcmp(buf, expectEp) != 0) {
        printf("  !! expected endpoint '%s'\n", expectEp);
        failures++;
    }
    memset(buf, 0, sizeof(buf));
    int k = vault_get_api_key(buf, sizeof(buf));
    printf("vault_get_api_key()   : %d -> '%s'\n", k, buf);
    if (k <= 0 || strcmp(buf, expectKey) != 0) {
        printf("  !! expected key '%s'\n", expectKey);
        failures++;
    }

    // ---- Step 2: tamper detection (flip one ciphertext byte) ----
    vault_wipe();
    {
        auto bad = bin;
        bad[30] ^= 0x01;   // inside URL ciphertext
        int rc2 = vault_init(bad.data(), (int)bad.size());
        printf("init(tampered body)   : %d (expect non-zero)\n", rc2);
        if (rc2 == 0) { printf("  !! tampered vault accepted\n"); failures++; }
    }

    // ---- Step 3: truncated blob ----
    vault_wipe();
    {
        std::vector<unsigned char> trunc(bin.begin(), bin.begin() + 20);
        int rc3 = vault_init(trunc.data(), (int)trunc.size());
        printf("init(truncated)       : %d (expect non-zero)\n", rc3);
        if (rc3 == 0) { printf("  !! truncated vault accepted\n"); failures++; }
    }

    // ---- Step 4: uninitialized getters ----
    vault_wipe();
    {
        int rc4 = vault_get_endpoint(buf, sizeof(buf));
        printf("get_endpoint(no init) : %d (expect non-zero)\n", rc4);
        if (rc4 == 0) { printf("  !! uninitialized vault served data\n"); failures++; }
    }

    printf("==========================================\n");
    printf("RESULT: %s (%d failure%s)\n", failures ? "FAIL" : "PASS",
           failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
