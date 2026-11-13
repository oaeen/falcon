#ifndef Runner_Bridging_Header_h
#define Runner_Bridging_Header_h

#import "GeneratedPluginRegistrant.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Starts the embedded Go Falcon gateway and admin server in-process.
/// Returns 0 on success or a non-zero error code on failure.
int FalconStart(
    const char* dataDir,
    const char* cacheDir,
    int gatewayPort,
    const char* adminAddr,
    const char* adminToken,
    const char* dnsServers
);

/// Stops the embedded Go Falcon gateway and admin server if running.
void FalconStop(void);

/// Returns a newly allocated JSON status string from the Go core.
/// Caller must release the returned pointer with FalconFreeString().
const char* FalconStatus(void);

/// Releases a C string previously returned by FalconStatus().
void FalconFreeString(const char* s);

#ifdef __cplusplus
}
#endif

#endif /* Runner_Bridging_Header_h */
