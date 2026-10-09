## Final hardware validation — pulling out of draft

Two full reboots and 14 real suspend/resume cycles on the affected
`06cb:009a` machine. Everything below is machine-generated.

### Reboods (2/2)
| boot id | NRestarts | services | init errors | DEBUG dumps | prints |
|---|---|---|---|---|---|
| `316dddc6…` | 0 | active/active | 0 | 0 | 4 |
| `c4977e89…` | 0 | active/active | 0 | 0 | 4 |

### Suspend/resume (14/14)
- Each cycle confirmed by kernel `PM: suspend entry (deep)` / `PM: suspend exit`.
- `open-fprintd-resume.service` → `Manager.Resume()` → `Device.Resume()` →
  `init.resume()`; the daemon re-initializes **in the same PID**
  (`Opening sensor: 57K0 FM-3367-001` after every wake).
- Same PIDs before/after every cycle, `NRestarts=0`, 0 init tracebacks,
  all fingerprints listed immediately after wake.
- The old `python3-validity-suspend-hotfix` restart unit is disabled; the
  in-process path replaces it (and removes the ~2 s lock-screen race it caused).

### Journal volume
- `journalctl --disk-usage`: **452 MiB** (was 4.1 GiB; capped at 500 MiB).
- Projected after fix: **~2,731 lines/day**, i.e. **-97.6%** vs the
  debug-only day (113,639 lines) and **-98.9%** vs the worst crash-loop day
  (258,073 lines).

With the two extra commits (atexit hardening + expected cancel/timeout logging),
that is 8 commits and 17 unit tests.
