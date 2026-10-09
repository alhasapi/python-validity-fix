Thanks for the root-cause analysis and patch — it matches a `06cb:009a` / Python 3.14 host exactly (Arch-based, pyusb 1.3.1, libusb 1.0.30). Two additions after reproducing the same `dev.write` timeout in `get_flash_info()`:

**1. The failure does not just crash once — it crash-loops forever.**
`atexit.register(close)` is only reached after a *successful* `open_common()`, and `close()` is the only code that resets the USB device. A failed init therefore never resets the stuck sensor, and each systemd restart hits the same state. On this host the journal shows:

- 12,701 `Scheduled restart job` / `Failed with result 'exit-code'`
- max systemd restart counter 5,075
- 5,267 starts on 2026-10-06 alone, 10,530 `USBTimeoutError: [Errno 110]` lines that day
- `Restart=on-failure` (the Arch package patches upstream `Restart=no`) with the default `RestartSec=100ms` and `StartLimitBurst=5 / 10s` never trips, because each attempt takes ~15s (the USB `default_timeout`)

So a fix for the busy/short-reply paths should be paired with (a) a hard reset/re-open on failed init and (b) systemd `RestartSec` + start limits.

**2. `partition_flash()` still dereferences `info.ic` unconditionally.**
Returning `FlashInfo(None, ...)` on the short reply (as in the patch above and in #245/#273) reaches `partition_flash()`, which does:

```python
logging.info('Detected Flash IC: %s, %d bytes' % (info.ic.name, info.ic.size))
```

i.e. `AttributeError: 'NoneType' object has no attribute 'name'`. Formatting must not guess flash parameters (size/sector size/erase command), so that path should re-query once after `reset_blob` and otherwise fail cleanly into the recovery loop rather than crash.

I've opened a consolidated draft PR that folds in your three fixes (with credit), plus the reset/re-open recovery, `Resume()` re-acquire, and `--debug`/restart-limit changes: **#290**. Happy to adjust the grouping — every concern is its own commit. Hardware validation on this `06cb:009a` is running and will be posted to the PR.
