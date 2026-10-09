# python-validity fix: `06cb:009a` init crash-loop + journal flooding

A tested fix for [uunicorn/python-validity](https://github.com/uunicorn/python-validity)
**0.15**, where the Synaptics Metallica MIS fingerprint reader (`06cb:009a`)
can stop answering and send the daemon into an **unbounded restart loop** while
flooding the system journal.

| | |
|---|---|
| Upstream PR | [uunicorn/python-validity#290](https://github.com/uunicorn/python-validity/pull/290) (ready for review) |
| Companion PR | [uunicorn/open-fprintd#30](https://github.com/uunicorn/open-fprintd/pull/30) |
| Root-cause issue + patch | [uunicorn/python-validity#272](https://github.com/uunicorn/python-validity/issues/272) |
| Related open PRs credited | #245, #273, #284, #249, #285, #217, #255, open-fprintd #24 |

This repository is the standalone overlay: the patch, the Arch packaging to
apply it, the local remediation scripts, and the raw validation evidence.

---

## Symptoms

On an Arch-based system (Omarchy) with Python 3.14 / pyusb 1.3.1 / libusb 1.0.30:

- Fingerprint login works, then stops after a reboot/suspend, and
  `python3-validity.service` keeps restarting.
- `journalctl -u python3-validity` is full of `usb.core.USBTimeoutError:
  [Errno 110] Operation timed out`.
- The system journal balloons; `journalctl --disk-usage` sat at the default
  **4 GiB** ceiling.

## Root cause

```
init.open() -> open_common() -> init_flash() -> get_flash_info()
  -> tls.cmd('3e') -> usb.cmd() -> dev.write(1, out)
usb.core.USBTimeoutError: [Errno 110] Operation timed out
```

1. `atexit.register(close)` runs only **after** a successful `open_common()`,
   and `close()` is the only code that resets the USB device. A failed init
   therefore never resets the stuck sensor, so the next start hits the same
   state.
2. Arch's AUR PKGBUILD patches upstream `Restart=no` to `Restart=on-failure`
   with the default `RestartSec=100ms` and `StartLimitBurst=5 / 10s`. Because
   each attempt takes ~15 s (the USB `default_timeout`), that start limit never
   trips: the loop is unbounded.
3. On `06cb:009a` the sensor can transiently report busy (`0x0104`/`0x0401`),
   reply to `3e` with only the status word (no flash header), and requires
   `send_init()` to run before the protected-flash commands in `init_flash()`.
4. Both `python3-validity.service` and `open-fprintd.service` shipped with
   `--debug`, dumping hex traffic (including key material) into the journal.

Measured on the affected machine:

| metric | value |
|---|---|
| `Scheduled restart job` events | **12,701** |
| max systemd restart counter | **5,075** |
| starts on the worst day | **5,267** |
| `USBTimeoutError [Errno 110]` that day | **10,530** |
| journal | pinned at **4.1 GiB** |
| `--debug` only, no crash loop (one day) | 113,639 lines / ~106 MiB |

## The fix (8 commits, one concern each)

Full diff: [`patch/fix.patch`](patch/fix.patch).

1. **`flash`: tolerate a short/empty flash-info reply** — a `0000`-only `3e`
   reply no longer crashes `unpack()`; an unknown flash IC is never formatted
   with guessed parameters.
2. **`usb`: retry transient `0x0104`/`0x0401` busy** — bounded `cmd_retry_busy()`
   also retries USB timeouts; the `init_hardcoded` reply is no longer asserted
   so the clean-slate fallback is reachable.
3. **`init`: run `send_init()` before `init_flash()`** — the ordering
   `06cb:009a` needs.
4. **`init`: reset and re-open the sensor instead of crash-looping** —
   `usb.reset()`/`usb.reopen()` plus `_open_with_recovery()`: a bounded number
   of attempts with a hard reset/re-open in between.
5. **`dbus`: re-acquire the USB device on `Resume()`** — `init.resume()` opens a
   fresh handle instead of reusing the stale pre-suspend one.
6. **`service`: drop `--debug` and throttle restarts** — `Restart=on-failure`,
   `RestartSec=5`, `StartLimitIntervalSec=300`, `StartLimitBurst=5`.
7. **`init`: never print a traceback from the atexit reboot handler.**
8. **`dbus`: log expected verify/enroll cancel and timeout without a traceback.**

17 unit tests (pytest, no hardware): [`upstream PR #290`](https://github.com/uunicorn/python-validity/pull/290).

## Validation (real hardware, `06cb:009a`)

- **2 full reboots**: `NRestarts=0`, services active, 0 init errors, 0 debug
  dumps, all fingerprints listed. See [`docs/post-reboot.txt`](docs/post-reboot.txt).
- **14 real suspend/resume cycles**: same PIDs throughout (no restart),
  `NRestarts=0`, in-process re-init after each wake, 0 init errors, fingerprints
  available immediately. See [`docs/resume-matrix.txt`](docs/resume-matrix.txt).
- **Journal**: `4.1 GiB -> 452 MiB` (capped at 500 MiB).
- **Log volume**: projected **~2,731 lines/day**, i.e. **-97.6%** vs the
  debug-only day and **-98.9%** vs the worst crash-loop day.
  See [`docs/final-metrics.txt`](docs/final-metrics.txt).

The local setup also disables the old
`python3-validity-suspend-hotfix.service` restart unit and relies on
`open-fprintd`'s `Suspend()`/`Resume()` path, which removes a ~2 s window where
the lock screen raced the restart.

## Apply locally (Arch / Arch-based)

```bash
git clone https://github.com/alhasapi/python-validity-fix
cd python-validity-fix/aur
makepkg -f                     # builds python-validity 0.15-2 with the patch
sudo ../local/install.sh       # installs it + drop-ins + journal cap, restarts services
```

`local/install.sh`:

1. installs the patched package,
2. installs `/etc/systemd/system/open-fprintd.service.d/10-no-debug.conf` and
   `/etc/systemd/journald.conf.d/00-size.conf` (`SystemMaxUse=500M`),
3. restarts journald and vacuums the journal,
4. disables the now-redundant `python3-validity-suspend-hotfix.service`,
5. restarts `open-fprintd` / `python3-validity` and prints validation output.

Validate with [`local/validate.sh`](local/validate.sh),
[`local/resume-matrix.sh`](local/resume-matrix.sh) and
[`local/post-reboot-check.sh`](local/post-reboot-check.sh).
See [`docs/LOCAL_FIX.md`](docs/LOCAL_FIX.md) for the rollback procedure.

## Repository layout

```
patch/   combined diff + commit list
aur/     PKGBUILD overlay that applies the patch to 0.15
local/   install/validate scripts and systemd/journald drop-ins
docs/    evidence, upstream links, PR texts and raw validation output
```

## Credits

Built on the analysis and patches of the upstream contributors, in particular
**#272** (root cause + patch), **#245**, **#273**, **#284**, **#249**,
**#285**, **#217**, **#255**, and **open-fprintd #24** (`PrepareForSleep`).
See [`docs/UPSTREAM.md`](docs/UPSTREAM.md) for the full list of notifications.

## License

MIT for the scripts and documentation in this repository, matching
`python-validity` (MIT). The patch modifies upstream MIT-licensed code.
See [`LICENSE`](LICENSE).
