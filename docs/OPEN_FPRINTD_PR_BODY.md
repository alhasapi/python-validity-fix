## Summary

Two small, independent changes:

1. **Adopt the `PrepareForSleep` handling from #24** (by @fcatuhe): subscribe to
   logind's `PrepareForSleep` and drive the existing `Suspend()`/`Resume()`
   methods so the D-Bus service stays alive across a sleep cycle. This removes
   the need for the `open-fprintd-suspend/resume` units to exist for clients
   such as lock screens.
2. **Stop starting with `--debug`**: drop it from both
   `debian/open-fprintd.service` and `dbus_service/net.reactivated.Fprint.service`.
   Debug logging stays available via an explicit override.

Credit for change 1 goes entirely to @fcatuhe in #24; this PR only carries it
together with the logging change so the two related defaults land together. If
you prefer, #24 can be merged as-is and I can drop commit content here.

## Relationship

Companion to uunicorn/python-validity#290, which makes the driver re-acquire the
USB device on resume (`init.resume()`) instead of reusing a stale handle. With
both, resume is handled inside the services rather than by restarting them from
systemd units.

## Testing

- `python3 -m py_compile openfprintd/manager.py` clean.
- No `--debug` remains in either service definition
  (`grep -rn -- '--debug'` shows only the CLI option itself).
- Hardware suspend/resume validation (≥10 cycles) is being done alongside the
  python-validity PR and will be reported.

Marked draft until that validation is attached.
