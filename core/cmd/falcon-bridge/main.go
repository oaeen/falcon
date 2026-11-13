package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"unsafe"

	"github.com/falcon-gateway/falcon/core/internal/engine"
)

//export FalconStart
func FalconStart(dataDir, cacheDir *C.char, gatewayPort C.int, adminAddr, adminToken, dnsServers *C.char) C.int {
	cfg := engine.Config{
		DataDir:     cstr(dataDir),
		CacheDir:    cstr(cacheDir),
		GatewayPort: int(gatewayPort),
		AdminAddr:   cstr(adminAddr),
		AdminToken:  cstr(adminToken),
		DNSServers:  cstr(dnsServers),
	}
	if err := engine.Start(cfg); err != nil {
		return -1
	}
	return 0
}

//export FalconStop
func FalconStop() C.int {
	if err := engine.Stop(); err != nil {
		return -1
	}
	return 0
}

//export FalconStatus
func FalconStatus() *C.char {
	b, _ := json.Marshal(engine.Status())
	return C.CString(string(b))
}

//export FalconFreeString
func FalconFreeString(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

func cstr(s *C.char) string {
	if s == nil {
		return ""
	}
	return C.GoString(s)
}

func main() {}
