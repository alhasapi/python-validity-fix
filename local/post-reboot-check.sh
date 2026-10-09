#!/usr/bin/env bash
# Run after a reboot to capture the cold-boot state of the fingerprint stack.
# Usage: ./post-reboot-check.sh
set -uo pipefail

OUT="$(dirname "$0")/../docs/post-reboot.txt"

{
  echo "=== post-reboot check $(date -Is) ==="
  echo "boot id: $(cat /proc/sys/kernel/random/boot_id)"
  echo "uptime:  $(uptime -p)"
  echo "kernel:  $(uname -r)"
  echo
  systemctl show python3-validity.service \
    -p Restart -p RestartUSec -p StartLimitBurst -p StartLimitIntervalUSec \
    -p NRestarts -p ActiveState -p SubState -p ExecMainPID -p ExecMainStartTimestamp
  echo "active: $(systemctl is-active open-fprintd.service python3-validity.service | tr '\n' ' ')"
  echo "suspend-hotfix enabled: $(systemctl is-enabled python3-validity-suspend-hotfix.service 2>&1)"
  echo "journal: $(journalctl --disk-usage)"
  echo "open-fprintd ExecStart: $(systemctl show open-fprintd.service -p ExecStart --value | grep -o 'argv\[\]=[^;]*')"
  echo
  echo "--- init errors since boot (expect none) ---"
  journalctl -u python3-validity.service -b --no-pager |
    grep -E "Traceback|USBTimeoutError|Errno 110|Scheduled restart|Exception ignored" | head -20 || echo none
  echo "--- debug hex dumps since boot (expect 0 from the new process) ---"
  journalctl -u python3-validity.service -b --no-pager | grep -c "DEBUG:root" || true
  echo
  echo "--- sensor ---"
  fprintd-list "$USER" 2>&1 | head -8
  echo
} | tee -a "$OUT"

echo "Wrote $OUT"
