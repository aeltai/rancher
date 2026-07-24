package rancher

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPrepareAuditLogPathCreatesReadableFile(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "rancher-api-audit.log")

	if err := prepareAuditLogPath(path); err != nil {
		t.Fatalf("prepareAuditLogPath() error = %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat() error = %v", err)
	}

	if info.Mode().Perm() != auditLogFileMode {
		t.Fatalf("file mode = %#o, want %#o", info.Mode().Perm(), auditLogFileMode)
	}
}

func TestSidecarReadableAuditLogKeepsFileReadable(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "rancher-api-audit.log")

	logger := newSidecarReadableAuditLog(path, 1, 1, 100)
	defer logger.Close()

	if _, err := logger.Write([]byte(`{"audit":true}` + "\n")); err != nil {
		t.Fatalf("Write() error = %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat() error = %v", err)
	}

	if info.Mode().Perm() != auditLogFileMode {
		t.Fatalf("file mode = %#o, want %#o", info.Mode().Perm(), auditLogFileMode)
	}
}
