## Local validation (part 1) — applied on the reporting machine

`06cb:009a`, Arch/Omarchy, Python 3.14.7, pyusb 1.3.1, libusb 1.0.30.
Patched build installed over 0.15 via a local AUR overlay carrying this exact
diff; `journald` capped at 500 MiB.

**Before** (from the journal): 12,701 scheduled restarts, max counter 5,075,
5,267 starts on 2026-10-06, 10,530 `USBTimeoutError [Errno 110]` lines that day,
journal pinned at 4.1 GiB.

**After install:**

- `NRestarts=0`, `ActiveState=active` through the whole run.
- **10x** `net.reactivated.Fprint.Manager.Resume` (exercises the new
  `init.resume()` re-acquire path) and **2x** `systemctl restart
  python3-validity` (exercises cold `init.open()`): `NRestarts=0` every time,
  no init tracebacks, `fprintd-list` still lists all 4 enrolled prints.
- Patched unit output since start: **96 lines / 9.9 KB**, 0 init tracebacks;
  the only 7 `DEBUG:root` lines are the *old* process shutting down.
- `journalctl --disk-usage` → **477.3 MiB** (from 4.1 GiB).

```
resume 1..10: NRestarts=0 active=active OK
restart 1:    NRestarts=0 active=active
restart 2:    NRestarts=0 active=active
```

Still to do before this comes out of draft: 2 full reboots and >=10 real
suspend/resume cycles with a verification after each. The 10 simulated resumes
+ 2 restarts cover the code paths, but not real USB re-enumeration.
