package cabundle

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"strings"
)

// DefaultAndroidCADirs are the standard Android system CA directories.
var DefaultAndroidCADirs = []string{
	"/apex/com.android.conscrypt/cacerts",
	"/system/etc/security/cacerts",
}

// Build scans Android system CA directories (or custom dirs if provided) and
// writes a combined PEM file to <cacheDir>/ca-bundle.pem.
// Returns the bundle path if at least one certificate was written, or "" otherwise.
func Build(cacheDir string, dirs ...string) (string, error) {
	if len(dirs) == 0 {
		dirs = DefaultAndroidCADirs
	}
	if strings.TrimSpace(cacheDir) == "" {
		return "", nil
	}

	seen := make(map[[32]byte]struct{})
	var roots, intermediates [][]byte

	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, ent := range entries {
			if ent.IsDir() {
				continue
			}
			p := filepath.Join(dir, ent.Name())
			raw, err := os.ReadFile(p)
			if err != nil || len(raw) == 0 {
				continue
			}
			extractCerts(raw, seen, &roots, &intermediates)
		}
	}

	if len(roots) == 0 && len(intermediates) == 0 {
		return "", nil
	}

	var buf bytes.Buffer
	for _, der := range roots {
		_ = pem.Encode(&buf, &pem.Block{Type: "CERTIFICATE", Bytes: der})
	}
	for _, der := range intermediates {
		_ = pem.Encode(&buf, &pem.Block{Type: "CERTIFICATE", Bytes: der})
	}

	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return "", err
	}
	outPath := filepath.Join(cacheDir, "ca-bundle.pem")
	if existing, err := os.ReadFile(outPath); err == nil && bytes.Equal(existing, buf.Bytes()) {
		return outPath, nil
	}
	tmp, err := os.CreateTemp(cacheDir, ".ca-bundle-*.pem")
	if err != nil {
		return "", err
	}
	tmpPath := tmp.Name()
	if _, err := tmp.Write(buf.Bytes()); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return "", err
	}
	if err := tmp.Chmod(0o644); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return "", err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return "", err
	}
	if err := os.Rename(tmpPath, outPath); err != nil {
		_ = os.Remove(tmpPath)
		return "", err
	}
	return outPath, nil
}

func extractCerts(raw []byte, seen map[[32]byte]struct{}, roots, intermediates *[][]byte) {
	rest := raw
	foundPEM := false
	for {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" || len(block.Bytes) == 0 {
			continue
		}
		foundPEM = true
		addDER(block.Bytes, seen, roots, intermediates)
	}
	if !foundPEM {
		if _, err := x509.ParseCertificate(raw); err == nil {
			addDER(raw, seen, roots, intermediates)
		}
	}
}

func addDER(der []byte, seen map[[32]byte]struct{}, roots, intermediates *[][]byte) {
	sum := sha256.Sum256(der)
	if _, ok := seen[sum]; ok {
		return
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return
	}
	seen[sum] = struct{}{}
	if bytes.Equal(cert.RawSubject, cert.RawIssuer) {
		*roots = append(*roots, der)
	} else {
		*intermediates = append(*intermediates, der)
	}
}
