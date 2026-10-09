#!/usr/bin/env bash
# Run N real suspend/resume cycles and log validation for each.
# Usage: ./resume-matrix.sh N [gap_seconds]
# Requires passwordless sudo (uses `systemctl suspend -i` to bypass inhibitors).
#
# NOTE: `systemctl suspend` returns before the machine actually suspends, so we
# wait for a new kernel "PM: suspend exit" before validating.
set -uo pipefail

N="${1:-4}"
GAP="${2:-12}"
OUT="$(dirname "$0")/../docs/resume-matrix.txt"

wait_for_resume() {
  local since="$1" i
  for i in $(seq 1 300); do
    if journalctl -k --since "$since" --no-pager 2>/dev/null | grep -q "PM: suspend exit"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

for i in $(seq 1 "$N"); do
  TS=$(date -Is)
  PID_BEFORE=$(systemctl show python3-validity.service -p ExecMainPID --value)
  OFD_BEFORE=$(systemctl show open-fprintd.service -p ExecMainPID --value)
  NR_BEFORE=$(systemctl show python3-validity.service -p NRestarts --value)

  {
    echo "================ cycle $i ================"
    echo "suspend requested: $TS"
    echo "before: pv_pid=$PID_BEFORE ofd_pid=$OFD_BEFORE NRestarts=$NR_BEFORE"
  } | tee -a "$OUT"

  sudo -n systemctl suspend -i >/dev/null 2>&1

  if wait_for_resume "$TS"; then
    RESUMED=yes
  else
    RESUMED=NO
    echo "WARNING cycle $i: no suspend exit seen within 300s" | tee -a "$OUT"
  fi
  sleep 4

  PID_AFTER=$(systemctl show python3-validity.service -p ExecMainPID --value)
  OFD_AFTER=$(systemctl show open-fprintd.service -p ExecMainPID --value)
  NR_AFTER=$(systemctl show python3-validity.service -p NRestarts --value)
  ACT_PV=$(systemctl is-active python3-validity.service)
  ACT_OFD=$(systemctl is-active open-fprintd.service)

  REINIT=$(journalctl -u python3-validity.service --since "$TS" --no-pager -o cat 2>/dev/null | grep -cE "Opening sensor")
  ERRS=$(journalctl -u python3-validity.service --since "$TS" --no-pager 2>/dev/null | grep -cE "Traceback|USBTimeoutError|Errno 110|Scheduled restart")
  FPRINT=$(fprintd-list "$USER" 2>&1 | grep -c "right-index-finger")

  {
    echo "resumed: $RESUMED at $(date -Is)"
    echo "after:  pv_pid=$PID_AFTER ofd_pid=$OFD_AFTER NRestarts=$NR_AFTER active=$ACT_PV/$ACT_OFD"
    echo "pv_pid_same=$([ "$PID_BEFORE" = "$PID_AFTER" ] && echo yes || echo NO)  ofd_pid_same=$([ "$OFD_BEFORE" = "$OFD_AFTER" ] && echo yes || echo NO)"
    echo "in_process_reinit=$REINIT  init_errors=$ERRS  fprintd_index_found=$FPRINT"
    echo
  } | tee -a "$OUT"

  if [ "$i" -lt "$N" ]; then
    sleep "$GAP"
  fi
done
