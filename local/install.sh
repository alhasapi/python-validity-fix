#!/usr/bin/env bash
# Install the local python-validity fix, systemd drop-ins and journal cap.
# Requires root: run as `sudo ./install.sh`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$HERE/../aur/python-validity-0.15-2-any.pkg.tar.zst"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "error: run with sudo: sudo $0" >&2
  exit 1
fi
if [[ ! -f "$PKG" ]]; then
  echo "error: package not found: $PKG (run makepkg in ../aur first)" >&2
  exit 1
fi

echo "==> 1/5 Installing patched python-validity 0.15-2"
pacman -U --noconfirm "$PKG"

echo "==> 2/5 Installing systemd drop-ins"
install -Dm644 "$HERE/open-fprintd.service.d/10-no-debug.conf" \
  /etc/systemd/system/open-fprintd.service.d/10-no-debug.conf
install -Dm644 "$HERE/journald.conf.d/00-size.conf" \
  /etc/systemd/journald.conf.d/00-size.conf
systemctl daemon-reload

# The old workaround restarts both daemons on every suspend/resume, which
# races the lock screen (it tried fingerprint auth while the services were
# still restarting). The patched python-validity now re-acquires the USB
# device in-process on Resume(), and open-fprintd-suspend/resume invoke that
# path, so the hotfix is no longer needed.
if systemctl is-enabled --quiet python3-validity-suspend-hotfix.service; then
  systemctl disable --now python3-validity-suspend-hotfix.service
fi

echo "==> 3/5 Capping and vacuuming the journal"
systemctl restart systemd-journald
journalctl --vacuum-size=500M
journalctl --disk-usage

echo "==> 4/5 Restarting services"
systemctl restart open-fprintd.service
systemctl restart python3-validity.service
sleep 3

echo "==> 5/5 Validation"
systemctl show python3-validity.service \
  -p Restart -p RestartUSec -p StartLimitBurst -p StartLimitIntervalUSec -p NRestarts
systemctl is-active open-fprintd.service python3-validity.service
echo "--- recent init tracebacks (expect none) ---"
journalctl -u python3-validity.service --since "2 minutes ago" --no-pager |
  grep -E "Traceback|USBTimeoutError|Errno 110" || echo "none"
echo
echo "Done. Now run ./validate.sh to record before/after metrics, and perform"
echo "the reboot / suspend-resume matrix from docs/LOCAL_FIX.md."
