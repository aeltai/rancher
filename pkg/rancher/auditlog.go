package rancher

import (
	"io"
	"os"
	"path/filepath"

	"gopkg.in/natefinch/lumberjack.v2"
)

const auditLogFileMode = 0o644

// sidecarReadableAuditLog wraps lumberjack so the audit log stays world-readable.
// The sidecar tails this file as UID 65534 and cannot read root-only log files.
type sidecarReadableAuditLog struct {
	*lumberjack.Logger
	filename string
}

func newSidecarReadableAuditLog(filename string, maxAge, maxBackups, maxSize int) io.WriteCloser {
	return &sidecarReadableAuditLog{
		Logger: &lumberjack.Logger{
			Filename:   filename,
			MaxAge:     maxAge,
			MaxBackups: maxBackups,
			MaxSize:    maxSize,
		},
		filename: filename,
	}
}

func (l *sidecarReadableAuditLog) Write(p []byte) (int, error) {
	n, err := l.Logger.Write(p)
	if err == nil {
		_ = os.Chmod(l.filename, auditLogFileMode)
	}
	return n, err
}

func prepareAuditLogPath(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}

	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, auditLogFileMode)
	if err != nil {
		return err
	}

	return f.Close()
}
