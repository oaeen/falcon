package cabundle

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func generateTestCert(t *testing.T, cn string, isCA bool) ([]byte, []byte) {
	t.Helper()
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: cn},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		IsCA:         isCA,
		KeyUsage:     x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &priv.PublicKey, priv)
	if err != nil {
		t.Fatal(err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	return der, pemBytes
}

func TestBuildCombinesAndDeduplicates(t *testing.T) {
	dir1 := t.TempDir()
	dir2 := t.TempDir()
	cacheDir := t.TempDir()

	der1, pem1 := generateTestCert(t, "RootCA-1", true)
	_, pem2 := generateTestCert(t, "RootCA-2", true)

	if err := os.WriteFile(filepath.Join(dir1, "a.0"), pem1, 0o644); err != nil {
		t.Fatal(err)
	}
	// Duplicate DER in dir2
	if err := os.WriteFile(filepath.Join(dir2, "a.der"), der1, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir2, "b.pem"), pem2, 0o644); err != nil {
		t.Fatal(err)
	}
	// Non-cert file should be ignored
	if err := os.WriteFile(filepath.Join(dir2, "junk.txt"), []byte("not a cert"), 0o644); err != nil {
		t.Fatal(err)
	}

	outPath, err := Build(cacheDir, dir1, dir2)
	if err != nil {
		t.Fatalf("Build error: %v", err)
	}
	if outPath != filepath.Join(cacheDir, "ca-bundle.pem") {
		t.Fatalf("unexpected outPath: %s", outPath)
	}

	data, err := os.ReadFile(outPath)
	if err != nil {
		t.Fatal(err)
	}

	var count int
	rest := data
	for {
		var blk *pem.Block
		blk, rest = pem.Decode(rest)
		if blk == nil {
			break
		}
		count++
	}
	if count != 2 {
		t.Fatalf("expected 2 deduplicated certs, got %d", count)
	}
}
