package plugin

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha1"
	"crypto/sha512"
	_ "embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

//go:embed market.json
var embeddedMarketJSON []byte

//go:embed host.mjs
var embeddedHostMJS []byte

var (
	distBaseRaw      = "https://raw.githubusercontent.com/magpie-community/plugins/dist"
	distBaseJsDelivr = "https://cdn.jsdelivr.net/gh/magpie-community/plugins@dist"
	registryRaw      = "https://raw.githubusercontent.com/magpie-community/plugins/main/registry.json"
	registryJsDelivr = "https://cdn.jsdelivr.net/gh/magpie-community/plugins@main/registry.json"
	npmOfficial      = "https://registry.npmjs.org"
	npmChinaMirror   = "https://registry.npmmirror.com"

	distFileRe = regexp.MustCompile(`^tgz/[A-Za-z0-9._-]+\.tgz$`)
)

// MarketItem describes a plugin entry in the marketplace directory.
type MarketItem struct {
	Package   string            `json:"package"`
	Name      string            `json:"name"`
	Icon      string            `json:"icon,omitempty"`
	Kind      string            `json:"kind,omitempty"`
	Providers []string          `json:"providers,omitempty"`
	Replaces  string            `json:"replaces,omitempty"`
	Community bool              `json:"community"`
	Summary   map[string]string `json:"summary,omitempty"`
	SummaryZh string            `json:"summaryZh,omitempty"`
	SummaryEn string            `json:"summaryEn,omitempty"`
	Installed bool              `json:"installed"`
	Enabled   bool              `json:"enabled"`
	Version   string            `json:"version,omitempty"`
	Error     string            `json:"error,omitempty"`
}

var canonicalPluginAliases = map[string]string{
	"opencode-zen-free-auth":    "@magpie-community/opencode-zen-free-auth",
	"zen-free":                  "@magpie-community/opencode-zen-free-auth",
	"opencode-workbuddy-auth":   "@magpie-community/opencode-workbuddy-auth",
	"workbuddy":                 "@magpie-community/opencode-workbuddy-auth",
	"workbuddy-ai":              "@magpie-community/opencode-workbuddy-auth",
	"opencode-cursor-auth":      "@magpie-community/opencode-cursor-auth",
	"cursor":                    "@magpie-community/opencode-cursor-auth",
	"opencode-qoder-auth":       "@magpie-community/opencode-qoder-auth",
	"qoder":                     "@magpie-community/opencode-qoder-auth",
	"opencode-zcode-auth":       "@magpie-community/opencode-zcode-auth",
	"zcode":                     "@magpie-community/opencode-zcode-auth",
	"opencode-kiro-auth":        "@magpie-community/opencode-kiro-auth",
	"kiro":                      "@magpie-community/opencode-kiro-auth",
	"opencode-devin-auth":       "@magpie-community/opencode-devin-auth",
	"devin":                     "@magpie-community/opencode-devin-auth",
	"opencode-zed-auth":         "@magpie-community/opencode-zed-auth",
	"zed":                       "@magpie-community/opencode-zed-auth",
	"opencode-factory-auth":     "@magpie-community/opencode-factory-auth",
	"factory":                   "@magpie-community/opencode-factory-auth",
	"opencode-grok-auth":        "@magpie-community/opencode-grok-auth",
	"grok":                      "@magpie-community/opencode-grok-auth",
	"opencode-commandcode-auth": "@magpie-community/opencode-commandcode-auth",
	"commandcode":               "@magpie-community/opencode-commandcode-auth",
	"commandcode-plan":          "@magpie-community/opencode-commandcode-auth",
	"opencode-mimo-auth":        "@magpie-community/opencode-mimo-auth",
	"mimo":                      "@magpie-community/opencode-mimo-auth",
	"mimo-app":                  "@magpie-community/opencode-mimo-auth",
}

// CanonicalPluginPackage normalizes a package name to its canonical scoped identifier if known.
func CanonicalPluginPackage(name string) string {
	s := strings.TrimSpace(strings.TrimPrefix(name, "npm:"))
	if s == "" {
		return ""
	}
	lower := strings.ToLower(s)
	if canon, ok := canonicalPluginAliases[lower]; ok {
		return canon
	}
	return s
}

func canonicalSpec(spec string) string {
	s := strings.TrimSpace(strings.TrimPrefix(spec, "npm:"))
	if s == "" {
		return ""
	}
	pkg := CanonicalPluginPackage(PackageNameOf(s))
	ver := PackageVersionOf(s)
	if ver != "" {
		return pkg + "@" + ver
	}
	return pkg
}

type marketDoc struct {
	Version int          `json:"version"`
	Plugins []MarketItem `json:"plugins"`
}

type distVersion struct {
	File      string          `json:"file"`
	Integrity string          `json:"integrity"`
	Manifest  json.RawMessage `json:"manifest"`
}

type distPackage struct {
	Latest   string                 `json:"latest"`
	Versions map[string]distVersion `json:"versions"`
}

type distIndex struct {
	Packages map[string]distPackage `json:"packages"`
}

// BuiltinMarket returns the curated embedded market.json entries.
func BuiltinMarket() []MarketItem {
	var doc marketDoc
	if err := json.Unmarshal(embeddedMarketJSON, &doc); err != nil {
		return nil
	}
	for i := range doc.Plugins {
		doc.Plugins[i].Package = CanonicalPluginPackage(doc.Plugins[i].Package)
		if doc.Plugins[i].Kind == "" {
			doc.Plugins[i].Kind = "provider"
		}
		if doc.Plugins[i].SummaryZh == "" {
			doc.Plugins[i].SummaryZh = doc.Plugins[i].Summary["zh"]
		}
		if doc.Plugins[i].SummaryEn == "" {
			doc.Plugins[i].SummaryEn = doc.Plugins[i].Summary["en"]
		}
	}
	return doc.Plugins
}

// FetchLiveMarket retrieves remote registry.json and merges with BuiltinMarket without bare/scoped duplicates.
func FetchLiveMarket(ctx context.Context, client *http.Client, chinaMirror bool) []MarketItem {
	base := BuiltinMarket()
	if client == nil {
		client = &http.Client{Timeout: 6 * time.Second}
	}
	urls := []string{registryRaw, registryJsDelivr}
	if chinaMirror {
		urls = []string{registryJsDelivr, registryRaw}
	}
	var remote []MarketItem
	for _, u := range urls {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		body, readErr := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
		resp.Body.Close()
		if resp.StatusCode == 200 && readErr == nil {
			var doc marketDoc
			if json.Unmarshal(body, &doc) == nil && len(doc.Plugins) > 0 {
				remote = doc.Plugins
				break
			}
		}
	}
	if len(remote) == 0 {
		return base
	}

	// Build dynamic alias table from any remote @magpie-community/* packages / replaces fields.
	dynAlias := make(map[string]string)
	for _, it := range remote {
		if strings.HasPrefix(it.Package, "@magpie-community/") {
			bare := strings.TrimPrefix(it.Package, "@magpie-community/")
			dynAlias[strings.ToLower(bare)] = it.Package
			if it.Replaces != "" {
				dynAlias[strings.ToLower(it.Replaces)] = it.Package
			}
		}
	}
	normPkg := func(pkg string) string {
		c := CanonicalPluginPackage(pkg)
		if mapped, ok := dynAlias[strings.ToLower(c)]; ok {
			return mapped
		}
		return c
	}

	byPkg := make(map[string]MarketItem, len(base)+len(remote))
	order := make([]string, 0, len(base)+len(remote))
	for _, it := range base {
		it.Package = normPkg(it.Package)
		if _, exists := byPkg[it.Package]; !exists {
			order = append(order, it.Package)
		}
		byPkg[it.Package] = it
	}
	for _, it := range remote {
		if it.Kind == "middleware" {
			continue
		}
		it.Package = normPkg(it.Package)
		if it.Kind == "" {
			it.Kind = "provider"
		}
		if it.SummaryZh == "" {
			it.SummaryZh = it.Summary["zh"]
		}
		if it.SummaryEn == "" {
			it.SummaryEn = it.Summary["en"]
		}
		if cur, ok := byPkg[it.Package]; ok {
			if len(it.Providers) > 0 && len(cur.Providers) == 0 {
				cur.Providers = it.Providers
			}
			if it.Replaces != "" && cur.Replaces == "" {
				cur.Replaces = it.Replaces
			}
			byPkg[it.Package] = cur
		} else {
			order = append(order, it.Package)
			byPkg[it.Package] = it
		}
	}
	out := make([]MarketItem, 0, len(order))
	for _, k := range order {
		out = append(out, byPkg[k])
	}
	return out
}

// ReconcileInstalledEntries migrates legacy bare package names/directories to canonical @magpie-community/*
// entries and deduplicates any duplicate records in config.json.
func ReconcileInstalledEntries(dataDir string, entries []types.InstalledPluginEntry) ([]types.InstalledPluginEntry, bool) {
	if len(entries) == 0 {
		return entries, false
	}
	changed := false
	idxByCanon := make(map[string]int, len(entries))
	out := make([]types.InstalledPluginEntry, 0, len(entries))
	for _, ent := range entries {
		origPkg := PackageNameOf(ent.Package)
		canonPkg := CanonicalPluginPackage(origPkg)
		canonSp := canonicalSpec(ent.Spec)
		if canonSp == "" {
			canonSp = canonPkg
		}
		if ent.Package != canonPkg || ent.Spec != canonSp {
			changed = true
		}
		if dataDir != "" && origPkg != "" && origPkg != canonPkg {
			legacyDir := PackageDir(dataDir, origPkg)
			canonDir := PackageDir(dataDir, canonPkg)
			if _, lerr := os.Stat(legacyDir); lerr == nil {
				if _, cerr := os.Stat(canonDir); errors.Is(cerr, os.ErrNotExist) {
					_ = os.MkdirAll(filepath.Dir(canonDir), 0o755)
					_ = os.Rename(legacyDir, canonDir)
				} else {
					_ = os.RemoveAll(legacyDir)
				}
			}
		}
		ent.Package = canonPkg
		ent.Spec = canonSp
		if pos, exists := idxByCanon[canonPkg]; exists {
			changed = true
			if ent.Enabled {
				out[pos].Enabled = true
			}
			if PackageVersionOf(ent.Spec) != "" {
				out[pos].Spec = ent.Spec
			}
			continue
		}
		idxByCanon[canonPkg] = len(out)
		out = append(out, ent)
	}
	return out, changed
}

// PackageNameOf strips an optional @version suffix from an npm package spec.
func PackageNameOf(spec string) string {
	spec = strings.TrimSpace(spec)
	if idx := strings.LastIndex(spec, "@"); idx > 0 {
		return spec[:idx]
	}
	return spec
}

// PackageVersionOf returns the explicit @version suffix, if any.
func PackageVersionOf(spec string) string {
	spec = strings.TrimSpace(spec)
	if idx := strings.LastIndex(spec, "@"); idx > 0 {
		return spec[idx+1:]
	}
	return ""
}

// PackageDir returns the installation directory under <dataDir>/plugins/node_modules/<pkg>.
func PackageDir(dataDir, pkgName string) string {
	parts := strings.Split(pkgName, "/")
	args := append([]string{dataDir, "plugins", "node_modules"}, parts...)
	return filepath.Join(args...)
}

// InstalledVersion reads the installed package.json version, or "".
func InstalledVersion(dataDir, pkgName string) string {
	pjPath := filepath.Join(PackageDir(dataDir, pkgName), "package.json")
	raw, err := os.ReadFile(pjPath)
	if err != nil {
		return ""
	}
	var pj struct {
		Version string `json:"version"`
	}
	if json.Unmarshal(raw, &pj) != nil {
		return ""
	}
	return pj.Version
}

// ResolveSpec resolves a short name, bare package, alias, or package spec against the canonical catalog.
func ResolveSpec(raw string, items []MarketItem) string {
	s := strings.TrimSpace(raw)
	s = strings.TrimPrefix(s, "npm:")
	if s == "" {
		return ""
	}
	name := CanonicalPluginPackage(PackageNameOf(s))
	ver := PackageVersionOf(s)
	lower := strings.ToLower(name)
	for _, it := range items {
		canonPkg := CanonicalPluginPackage(it.Package)
		if strings.ToLower(canonPkg) == lower || strings.ToLower(it.Package) == lower {
			if ver != "" {
				return canonPkg + "@" + ver
			}
			return canonPkg
		}
		bare := canonPkg
		if idx := strings.Index(bare, "/"); idx >= 0 {
			bare = bare[idx+1:]
		}
		if strings.ToLower(bare) == lower ||
			strings.ToLower(it.Name) == lower ||
			(it.Replaces != "" && strings.ToLower(it.Replaces) == lower) {
			if ver != "" {
				return canonPkg + "@" + ver
			}
			return canonPkg
		}
		for _, p := range it.Providers {
			if strings.ToLower(p) == lower {
				if ver != "" {
					return canonPkg + "@" + ver
				}
				return canonPkg
			}
		}
	}
	if ver != "" {
		return name + "@" + ver
	}
	return name
}

// InstallResult describes an installed plugin package on disk.
type InstallResult struct {
	Package string `json:"package"`
	Version string `json:"version"`
	Dir     string `json:"dir"`
	Source  string `json:"source"` // "dist" | "npm"
}

// InstallPackage downloads, verifies, and extracts a plugin package into <dataDir>/plugins/node_modules/<pkg>.
func InstallPackage(ctx context.Context, client *http.Client, dataDir, spec string, chinaMirror bool, bunPath string) (InstallResult, error) {
	if client == nil {
		client = &http.Client{Timeout: 45 * time.Second}
	}
	pkgName := CanonicalPluginPackage(PackageNameOf(spec))
	wantVer := PackageVersionOf(spec)
	if pkgName == "" {
		return InstallResult{}, errors.New("empty package spec")
	}

	var tgzBytes []byte
	var version string
	var source string
	var err error

	if strings.HasPrefix(pkgName, "@magpie-community/") {
		tgzBytes, version, err = fetchFromDistBranch(ctx, client, pkgName, wantVer, chinaMirror)
		source = "dist"
	} else {
		tgzBytes, version, err = fetchFromNPM(ctx, client, pkgName, wantVer, chinaMirror)
		if err != nil {
			// Fallback to community dist branch under @magpie-community/<pkgName> if available
			if b, v, derr := fetchFromDistBranch(ctx, client, "@magpie-community/"+pkgName, wantVer, chinaMirror); derr == nil {
				tgzBytes, version, err = b, v, nil
				pkgName = "@magpie-community/" + pkgName
				source = "dist"
			}
		} else {
			source = "npm"
		}
	}
	if err != nil {
		return InstallResult{}, err
	}

	destDir := PackageDir(dataDir, pkgName)
	stageDir := destDir + ".staging"
	_ = os.RemoveAll(stageDir)
	if err := ExtractTarGz(tgzBytes, stageDir); err != nil {
		_ = os.RemoveAll(stageDir)
		return InstallResult{}, fmt.Errorf("extract %s: %w", pkgName, err)
	}
	_ = os.RemoveAll(destDir)
	if err := os.MkdirAll(filepath.Dir(destDir), 0o755); err != nil {
		_ = os.RemoveAll(stageDir)
		return InstallResult{}, err
	}
	if err := os.Rename(stageDir, destDir); err != nil {
		_ = os.RemoveAll(stageDir)
		return InstallResult{}, err
	}
	if strings.HasPrefix(pkgName, "@magpie-community/") {
		bare := strings.TrimPrefix(pkgName, "@magpie-community/")
		_ = os.RemoveAll(PackageDir(dataDir, bare))
	}

	// Install runtime npm dependencies if declared and Bun is available (skipped on iOS / no bun)
	if bunPath != "" && runtime.GOOS != "ios" {
		_ = maybeInstallDeps(ctx, destDir, bunPath, chinaMirror)
	}

	if version == "" {
		version = InstalledVersion(dataDir, pkgName)
	}
	return InstallResult{
		Package: pkgName,
		Version: version,
		Dir:     destDir,
		Source:  source,
	}, nil
}

func fetchFromDistBranch(ctx context.Context, client *http.Client, pkgName, wantVer string, chinaMirror bool) ([]byte, string, error) {
	bases := []string{distBaseRaw, distBaseJsDelivr}
	if chinaMirror {
		bases = []string{distBaseJsDelivr, distBaseRaw}
	}
	var idx distIndex
	var chosenBase string
	var lastErr error
	for _, base := range bases {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/index.json", nil)
		if err != nil {
			lastErr = err
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		raw, rerr := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
		resp.Body.Close()
		if resp.StatusCode != 200 || rerr != nil {
			lastErr = fmt.Errorf("dist index HTTP %d", resp.StatusCode)
			continue
		}
		if err := json.Unmarshal(raw, &idx); err != nil {
			lastErr = err
			continue
		}
		chosenBase = base
		break
	}
	if chosenBase == "" {
		if lastErr == nil {
			lastErr = errors.New("unable to fetch community dist index")
		}
		return nil, "", lastErr
	}

	pkg, ok := idx.Packages[pkgName]
	if !ok {
		return nil, "", fmt.Errorf("package %s not found in community dist index", pkgName)
	}
	verKey := wantVer
	if verKey == "" || verKey == "latest" {
		verKey = pkg.Latest
	}
	ver, ok := pkg.Versions[verKey]
	if !ok {
		return nil, "", fmt.Errorf("version %q of %s not found in dist index", verKey, pkgName)
	}
	if !distFileRe.MatchString(ver.File) {
		return nil, "", fmt.Errorf("invalid tarball path in dist index: %s", ver.File)
	}

	tgzURL := chosenBase + "/" + ver.File
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, tgzURL, nil)
	if err != nil {
		return nil, "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, "", fmt.Errorf("download tarball HTTP %d", resp.StatusCode)
	}
	tgzBytes, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return nil, "", err
	}

	if err := VerifyIntegrity(tgzBytes, ver.Integrity, ""); err != nil {
		return nil, "", err
	}
	return tgzBytes, verKey, nil
}

func fetchFromNPM(ctx context.Context, client *http.Client, pkgName, wantVer string, chinaMirror bool) ([]byte, string, error) {
	registries := []string{npmOfficial, npmChinaMirror}
	if chinaMirror {
		registries = []string{npmChinaMirror, npmOfficial}
	}
	escaped := url.PathEscape(pkgName)
	// Preserve slash only? npm registry accepts %2f for scoped packages
	var meta struct {
		DistTags map[string]string `json:"dist-tags"`
		Versions map[string]struct {
			Dist struct {
				Tarball   string `json:"tarball"`
				Integrity string `json:"integrity"`
				Shasum    string `json:"shasum"`
			} `json:"dist"`
		} `json:"versions"`
	}
	var lastErr error
	loaded := false
	for _, reg := range registries {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, reg+"/"+escaped, nil)
		if err != nil {
			lastErr = err
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		raw, rerr := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
		resp.Body.Close()
		if resp.StatusCode != 200 || rerr != nil {
			lastErr = fmt.Errorf("npm registry HTTP %d", resp.StatusCode)
			continue
		}
		if err := json.Unmarshal(raw, &meta); err != nil {
			lastErr = err
			continue
		}
		loaded = true
		break
	}
	if !loaded {
		if lastErr == nil {
			lastErr = fmt.Errorf("npm metadata unavailable for %s", pkgName)
		}
		return nil, "", lastErr
	}
	verKey := wantVer
	if verKey == "" || verKey == "latest" {
		verKey = meta.DistTags["latest"]
	}
	vInfo, ok := meta.Versions[verKey]
	if !ok || vInfo.Dist.Tarball == "" {
		return nil, "", fmt.Errorf("version %q not found on npm for %s", verKey, pkgName)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, vInfo.Dist.Tarball, nil)
	if err != nil {
		return nil, "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, "", fmt.Errorf("npm tarball HTTP %d", resp.StatusCode)
	}
	tgzBytes, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return nil, "", err
	}
	if err := VerifyIntegrity(tgzBytes, vInfo.Dist.Integrity, vInfo.Dist.Shasum); err != nil {
		return nil, "", err
	}
	return tgzBytes, verKey, nil
}

// VerifyIntegrity validates sha512-<base64> or hex sha1 shasum against tgzBytes.
func VerifyIntegrity(data []byte, integrity, shasum string) error {
	if strings.HasPrefix(integrity, "sha512-") {
		sum := sha512.Sum512(data)
		got := "sha512-" + base64.StdEncoding.EncodeToString(sum[:])
		if got != integrity {
			return fmt.Errorf("sha512 integrity mismatch: got %s want %s", got, integrity)
		}
		return nil
	}
	if shasum != "" {
		sum := sha1.Sum(data)
		got := hex.EncodeToString(sum[:])
		if !strings.EqualFold(got, shasum) {
			return fmt.Errorf("sha1 shasum mismatch: got %s want %s", got, shasum)
		}
	}
	return nil
}

// ExtractTarGz unpacks an npm .tgz archive safely into destDir, stripping the leading "package/" directory.
func ExtractTarGz(tgzBytes []byte, destDir string) error {
	gz, err := gzip.NewReader(bytes.NewReader(tgzBytes))
	if err != nil {
		return err
	}
	defer gz.Close()

	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return err
	}
	cleanDest := filepath.Clean(destDir)

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return err
		}
		rel := filepath.ToSlash(hdr.Name)
		rel = strings.TrimPrefix(rel, "./")
		if idx := strings.IndexByte(rel, '/'); idx >= 0 {
			rel = rel[idx+1:]
		} else {
			continue
		}
		if rel == "" || rel == "." {
			continue
		}
		target := filepath.Join(cleanDest, filepath.FromSlash(rel))
		if target != cleanDest && !strings.HasPrefix(target, cleanDest+string(filepath.Separator)) {
			return fmt.Errorf("illegal path in tarball: %s", hdr.Name)
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
			if err != nil {
				return err
			}
			_, copyErr := io.Copy(f, io.LimitReader(tr, 64<<20))
			closeErr := f.Close()
			if copyErr != nil {
				return copyErr
			}
			if closeErr != nil {
				return closeErr
			}
		}
	}
	return nil
}

func maybeInstallDeps(ctx context.Context, pkgDir, bunPath string, chinaMirror bool) error {
	raw, err := os.ReadFile(filepath.Join(pkgDir, "package.json"))
	if err != nil {
		return err
	}
	var pj struct {
		Dependencies map[string]string `json:"dependencies"`
	}
	if json.Unmarshal(raw, &pj) != nil || len(pj.Dependencies) == 0 {
		return nil
	}
	needInstall := false
	for dep := range pj.Dependencies {
		if !strings.HasPrefix(dep, "@opencode-ai/") {
			needInstall = true
			break
		}
	}
	if !needInstall {
		return nil
	}
	cmd := exec.CommandContext(ctx, bunPath, "install", "--production", "--ignore-scripts")
	cmd.Dir = pkgDir
	if chinaMirror {
		cmd.Env = append(os.Environ(), "NPM_CONFIG_REGISTRY="+npmChinaMirror)
	}
	return cmd.Run()
}
