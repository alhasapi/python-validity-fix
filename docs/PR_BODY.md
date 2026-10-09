## What this fixes

On a Lenovo `06cb:009a` (Synaptics Metallica MIS) running Python 3.14, the daemon
can come up with an unresponsive sensor and then **crash-loop forever** while
flooding the journal:

```
init.open() -> open_common() -> init_flash() -> get_flash_info()
  -> tls.cmd('3e') -> usb.cmd() -> dev.write(1, out)
usb.core.USBTimeoutError: [Errno 110] Operation timed out
```

`atexit.register(close)` is only reached after a *successful* `open_common()`,
and `close()` is the only place that resets the USB device. So a failed init
never reset the sensor, and every systemd restart met the same stuck state.

Machine-generated evidence from the affected host (10 days):

| metric | value |
|---|---|
| `Scheduled restart job` | 12,701 |
| max systemd restart counter | 5,075 |
| starts on 2026-10-06 | 5,267 |
| `USBTimeoutError: [Errno 110]` lines that day | 10,530 |
| journal | pinned at the default 4 GiB ceiling |
| unit `--debug` only, no crash loop (2026-10-01) | 113,639 lines / ~106 MiB |

## Changes (one commit per concern)

1. **`flash: tolerate short/empty flash-info reply and never format an unknown IC`**
   A `0000`-only `3e` reply crashed `unpack()`. Return an empty `FlashInfo`,
   re-query once after `reset_blob`, and refuse to format if the flash IC is
   still unknown instead of guessing flash parameters.
2. **`usb: retry transient 0x0104/0x0401 busy status during send_init`**
   Bounded `cmd_retry_busy()` for the busy statuses and USB timeouts; stop
   asserting on the `init_hardcoded` reply so the clean-slate fallback works.
3. **`init: run send_init() before init_flash()`**
   The ordering that makes protected-flash commands time out on `06cb:009a`.
4. **`init: reset and re-open the sensor instead of crash-looping`**
   `usb.reset()`/`usb.reopen()` (re-discovery, so a re-enumerated device is
   found again) plus `_open_with_recovery()`: a bounded number of attempts with
   a hard reset/re-open in between. `RebootException` still propagates.
5. **`dbus: re-acquire the USB device on Resume`**
   `init.resume()` re-opens the device and rebuilds state instead of reusing a
   stale post-suspend PyUSB handle.
6. **`service: drop --debug default and throttle restarts`**
   Remove `--debug`, set `Restart=on-failure`, `RestartSec=5`, and bound the
   storm with `StartLimitIntervalSec=300` / `StartLimitBurst=5`.

## Relationship to existing work (nothing silently duplicated)

This is a consolidated PR that **adopts and credits** the open proposals and
adds the pieces none of them covered:

- **#272** (root-cause issue + patch): busy retry, short-reply tolerance,
  `send_init()`/`init_flash()` ordering. Commits 1–3 are based on it. Two gaps
  are fixed here: `partition_flash()` dereferenced `info.ic` unconditionally,
  and nothing reset a stuck sensor.
- **#245 / #273**: same init/flash area — folded in and extended.
- **#284**: drop `--debug` — commit 6.
- **#249 / #285**: resume — commit 5 takes the targeted `init.resume()` form.
- **#217 / #255**: broader roll-ups — left open; this PR is intentionally
  limited to initialization, recovery, resume and service logging.
- **open-fprintd #24** (`PrepareForSleep`): separate PR against that repo.

Happy to split or rebase any commit if you prefer a different grouping; they are
deliberately independent.

## Testing

- `tests/` (new, pytest, **no hardware required**): 15 tests —
  full/short flash replies, refusing to format an unknown IC, busy/timeout
  retry bounds, non-timeout errors not retried, init ordering, bounded
  reset/re-open recovery, `RebootException` propagation, resume re-acquire,
  and the unit file (no `--debug`, throttled restarts).
- `python -m py_compile` clean.
- Hardware validation on the reporter's `06cb:009a` (reboot + suspend/resume
  matrix) is in progress and will be posted here as a follow-up comment.

Marked **draft** until that hardware run is attached.

## Notes

- The repo has no CI; the tests run with `python -m pytest` and a local
  `pytest.ini`.
- No behavior change for already-working sensors: the normal path is unchanged,
  recovery only engages after a failure.
