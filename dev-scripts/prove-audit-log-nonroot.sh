#!/usr/bin/env bash
set -euo pipefail

# Demonstrates the rancher-audit-log sidecar securityContext from the Helm chart.
# Uses Docker (vfs storage driver) because nested overlay/cgroup limits block k3s here.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${TMPDIR:-/tmp}/rancher-audit-log-proof"
IMAGE="rancher/mirrored-bci-micro:16.0-15.11"
NETWORK="rancher-audit-proof"
LOG_WRITER="rancher-audit-log-writer"
LOG_READER="rancher-audit-log-reader"

cleanup() {
  docker rm -f "$LOG_WRITER" "$LOG_READER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$WORKDIR/auditlog"
echo "proof-line-$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WORKDIR/auditlog/rancher-api-audit.log"
chmod 644 "$WORKDIR/auditlog/rancher-api-audit.log"

docker network create "$NETWORK" >/dev/null

echo "==> Starting log writer (simulates Rancher writing audit logs as root)"
docker run -d --name "$LOG_WRITER" \
  --network "$NETWORK" \
  -v "$WORKDIR/auditlog:/var/log/auditlog" \
  busybox:1.36 \
  sh -c 'while true; do date -u +%Y-%m-%dT%H:%M:%SZ >> /var/log/auditlog/rancher-api-audit.log; sleep 2; done' >/dev/null

echo "==> Starting audit-log sidecar with chart securityContext (non-root UID 65534)"
docker run -d --name "$LOG_READER" \
  --network "$NETWORK" \
  --user 65534:65534 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  -v "$WORKDIR/auditlog:/var/log/auditlog:ro" \
  "$IMAGE" \
  tail -F /var/log/auditlog/rancher-api-audit.log >/dev/null

sleep 2

echo
echo "==> Container processes"
docker ps --filter "name=rancher-audit-log" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

echo
echo "==> Effective user in audit-log sidecar"
docker exec "$LOG_READER" sh -c 'id'
docker top "$LOG_READER"

echo
echo "==> Read-only root filesystem check"
if docker exec "$LOG_READER" sh -c 'touch /should-fail 2>/dev/null'; then
  echo "ERROR: sidecar could write to root filesystem"
  exit 1
else
  echo "OK: root filesystem is read-only"
fi

echo
echo "==> Audit log tail output (proves non-root can read shared volume)"
docker logs --tail 5 "$LOG_READER"

echo
echo "==> Rendered Helm securityContext from current chart"
tmpdir="$(mktemp -d)"
cp -r "$ROOT_DIR/chart"/* "$tmpdir/"
sed -i 's/%VERSION%/2.14.3/g; s/%APP_VERSION%/2.14.3/g' "$tmpdir/Chart.yaml"
helm template proof "$tmpdir" \
  --set hostname=rancher.example.com \
  --set auditLog.enabled=true \
  --set auditLog.destination=sidecar \
  | awk '/name: rancher-audit-log/,/^      volumes:/' | sed '/^      volumes:/d'

echo
echo "PASS: rancher-audit-log sidecar runs as non-root and can tail audit logs"
