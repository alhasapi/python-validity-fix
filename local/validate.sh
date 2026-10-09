#!/usr/bin/env bash
# Record post-fix validation metrics. Read-only; run as your normal user.
set -uo pipefail

OUT="${1:-$(dirname "$0")/../docs/after-metrics.txt}"
{
  echo "# Post-fix metrics"
  echo "captured: $(date -Is)"
  echo
  echo "## Unit state"
  systemctl show python3-validity.service \
    -p Restart -p RestartUSec -p StartLimitBurst -p StartLimitIntervalUSec -p NRestarts -p ActiveState -p SubState
  echo
  echo "## Active state"
  systemctl is-active open-fprintd.service python3-validity.service
  echo
  echo "## Journal size"
  journalctl --disk-usage
  echo
  echo "## python-validity log volume since midnight"
  journalctl -u python3-validity.service --since today --no-pager | wc -l
  journalctl -u python3-validity.service --since today --no-pager | wc -c
  echo
  echo "## Init errors since midnight (expect none)"
  journalctl -u python3-validity.service --since today --no-pager |
    grep -E "Traceback|USBTimeoutError|Errno 110|Scheduled restart" || echo "none"
  echo
  echo "## Debug hex dumps since midnight (expect none)"
  journalctl -u python3-validity.service --since today --no-pager |
    grep -c "DEBUG:root" || true
} | tee "$OUT"

echo
echo "Wrote $OUT"
