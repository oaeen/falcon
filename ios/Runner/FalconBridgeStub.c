#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#if defined(__GNUC__) || defined(__clang__)
#define FALCON_WEAK __attribute__((weak))
#else
#define FALCON_WEAK
#endif

/*
 * Weak default stubs for the Go falcon-bridge C ABI (`core/cmd/falcon-bridge/main.go`).
 *
 * When `FalconCore.xcframework` (`libfalcon_bridge.a`) is linked, its strong CGo
 * symbols automatically override these weak definitions. When building in Xcode
 * before `tooling/build-core.sh` has produced the Go archive, these stubs keep
 * the standalone Xcode build linking cleanly and report an informative status.
 */

int FalconStart(
    const char* dataDir,
    const char* cacheDir,
    int gatewayPort,
    const char* adminAddr,
    const char* adminToken,
    const char* dnsServers
);
void FalconStop(void);
const char* FalconStatus(void);
void FalconFreeString(const char* s);

FALCON_WEAK int FalconStart(
    const char* dataDir,
    const char* cacheDir,
    int gatewayPort,
    const char* adminAddr,
    const char* adminToken,
    const char* dnsServers
) {
    (void)dataDir;
    (void)cacheDir;
    (void)gatewayPort;
    (void)adminAddr;
    (void)adminToken;
    (void)dnsServers;
    return -1;
}

FALCON_WEAK void FalconStop(void) {
}

FALCON_WEAK const char* FalconStatus(void) {
    static const char kStubStatusJson[] =
        "{\"running\":false,\"stub\":true,\"pluginRuntimeMode\":\"embedded\","
        "\"error\":\"FalconCore.xcframework (libfalcon_bridge.a) is not linked; "
        "run tooling/build-core.sh ios-xcframework\"}";
    size_t len = sizeof(kStubStatusJson);
    char* copy = (char*)malloc(len);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, kStubStatusJson, len);
    return copy;
}

FALCON_WEAK void FalconFreeString(const char* s) {
    if (s != NULL) {
        free((void*)s);
    }
}
