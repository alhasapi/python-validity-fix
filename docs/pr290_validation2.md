Two more commits added, plus a fuller local suspend/resume run.

### Added commits

- **`init: never print a traceback from the atexit reboot handler`** — `close()`
  only caught `RebootException`, so a USB error in `reboot()` (the device is
  usually already reset/gone during shutdown or suspend) produced
  `Exception ignored in atexit callback` on every stop.
- **`dbus: log expected verify/enroll cancel and timeout without a traceback`** —
  a cancelled verify (or one timing out waiting for a finger) raised
  `CancelledException`, hit the generic handler and logged a full chained
  traceback containing the 30s `USBTimeoutError`. That was a large share of the
  journal volume. Now handled explicitly with a single log line; status
  callbacks unchanged. 17 unit tests total.

### Real suspend/resume matrix (no longer simulated)

On the same `06cb:009a` host, with the old `python3-validity-suspend-hotfix`
restart disabled so the new in-process path is exercised:

- **14 real suspend/resume cycles** (kernel `PM: suspend entry (deep)` /
  `PM: suspend exit` confirmed for each).
- `open-fprintd-resume.service` calls `Manager.Resume()` -> python-validity
  `Device.Resume()` -> `init.resume()`; the sensor re-initializes in the same
  process (`Opening sensor: 57K0 FM-3367-001` after every resume).
- **Same PIDs before/after every cycle** (no restart), `NRestarts=0` throughout,
  `0` init tracebacks, `fprintd-list` returns all 4 enrolled prints immediately
  after wake.
- `journalctl --disk-usage` = 432 MiB (from 4.1 GiB).

Remaining before un-drafting: 2 full reboots. A reboot ends the agent session,
so those are being done by the machine owner and the results will be posted.
