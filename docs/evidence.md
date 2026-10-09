# python-validity crash-loop & journal-flood evidence
captured: 2026-10-09T07:30:59+01:00 on <host>

## 1. Host / stack
```
7.2.5-3-omarchy
Python 3.14.7
python-validity 0.15-1
open-fprintd 0.7-2
python-pyusb 1.3.1-2
libusb 1.0.30-1
python-cryptography 50.0.1-1
fprintd-clients-git 1.90.1.r2.g54e56d6-10
```

## 2. Current unit state
```
ActiveState=active
SubState=running
StartLimitIntervalUSec=10s
StartLimitBurst=5
Restart=on-failure
RestartUSec=100ms
NRestarts=0
ExecMainStartTimestamp=Fri 2026-10-09 05:55:05 WAT
```

## 3. Upstream vs AUR service definition
```
--- upstream master (uunicorn/python-validity/debian/python3-validity.service) ---
[Unit]
Description=python-validity driver dbus service
After=open-fprintd.service

[Service]
Type=simple
ExecStart=/usr/lib/python-validity/dbus-service --debug
Restart=no

[Install]
WantedBy=multi-user.target
--- installed on this host ---
[Unit]
Description=python-validity driver dbus service
After=open-fprintd.service

[Service]
Type=simple
ExecStart=/usr/lib/python-validity/dbus-service --debug
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## 4. Restart-loop metrics (from journal history)
```
max restart counter: 5075
scheduled restart jobs (all history): 12701
Failed with result 'exit-code': 12701
total journal bytes for this unit (all history): 405103691

Started events per day (last 10 days):
2026-09-30  starts=3  lines=54533  bytes=50976288
2026-10-01  starts=2  lines=113639  bytes=106019781
2026-10-02  starts=0  lines=100428  bytes=93655873
2026-10-03  starts=9  lines=3948  bytes=3618896
2026-10-04  starts=427  lines=21101  bytes=2301591
2026-10-05  starts=2041  lines=102869  bytes=12335599
2026-10-06  starts=5267  lines=258073  bytes=24444058
2026-10-07  starts=1976  lines=97735  bytes=10191786
2026-10-08  starts=3  lines=3260  bytes=3166892
2026-10-09  starts=1  lines=522  bytes=474404
```

## 5. Exact failure chain (crash-loop instance)
```
Traceback (most recent call last):
  File "/usr/lib/python-validity/dbus-service", line 305, in <module>
    main()
    ~~~~^^
  File "/usr/lib/python-validity/dbus-service", line 262, in main
    init.open()
    ~~~~~~~~~^^
  File "/usr/lib/python3.14/site-packages/validitysensor/init.py", line 50, in open
    open_common()
    ~~~~~~~~~~~^^
  File "/usr/lib/python3.14/site-packages/validitysensor/init.py", line 31, in open_common
    init_flash()
    ~~~~~~~~~~^^
  File "/usr/lib/python3.14/site-packages/validitysensor/init_flash.py", line 122, in init_flash
    info = get_flash_info()
  File "/usr/lib/python3.14/site-packages/validitysensor/flash.py", line 40, in get_flash_info
    rsp = tls.cmd(unhex('3e'))
  File "/usr/lib/python3.14/site-packages/validitysensor/tls.py", line 124, in cmd
    rsp = self.usb.cmd(cmd)
  File "/usr/lib/python3.14/site-packages/validitysensor/usb.py", line 104, in cmd
    self.dev.write(1, out)
    ~~~~~~~~~~~~~~^^^^^^^^
  File "/usr/lib/python3.14/site-packages/usb/core.py", line 1003, in write
    return fn(
            self._ctx.handle,
    ...<3 lines>...
            self.__get_timeout(timeout)
        )
  File "/usr/lib/python3.14/site-packages/usb/backend/libusb1.py", line 841, in bulk_write
    return self.__write(self.lib.libusb_bulk_transfer,
           ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                        dev_handle,
                        ^^^^^^^^^^^
    ...<2 lines>...
                        data,
                        ^^^^^
                        timeout)
                        ^^^^^^^^
  File "/usr/lib/python3.14/site-packages/usb/backend/libusb1.py", line 942, in __write
    _check(retval)
    ~~~~~~^^^^^^^^
  File "/usr/lib/python3.14/site-packages/usb/backend/libusb1.py", line 602, in _check
    raise USBTimeoutError(_strerror(ret), ret, _libusb_errno[ret])
usb.core.USBTimeoutError: [Errno 110] Operation timed out
python3-validity.service: Main process exited, code=exited, status=1/FAILURE
```

## 6. Error-frequency in the worst crash-loop day (2026-10-06)
```
USBTimeoutError [Errno 110] lines: 10530
usb.core.USBError [Errno 19] lines: 1
get_flash_info frames: 10532
Traceback lines: 5266
DEBUG lines: 5298
Finger not recognized: 0
```

## 7. journald state
```
Archived and active journals take up 4G in the file system.
--- effective config (defaults) ---
[Journal]
--- on-disk ---
4.1G	/var/log/journal
/dev/mapper/root  237G  115G  120G  49% /
```

## 8. Controlled reproduction

The stuck-sensor state is **intermittent and environmental** (it appears after reboots/suspend
when the sensor does not answer the first bulk write). It cannot be forced on demand without
risking leaving this machine's currently-healthy sensor in the same stuck state. Historical
journal proof is conclusive and machine-generated:

- 12,701 `Scheduled restart job` events, 12,701 `Failed with result 'exit-code'`.
- Max systemd restart counter: **5075**; worst day 2026-10-06 with **5,267 starts**, 258,073 lines,
  10,530 `USBTimeoutError: [Errno 110]` lines and 5,266 Python tracebacks.
- The exact uncaught chain is captured in section 5.

Mechanism confirmed by code inspection of 0.15:
```
14:def close():
29:def open_common():
31:    init_flash()
32:    usb.send_init()
44:    atexit.register(close)
45:    logging.debug('atexit registered')
```
-> `atexit.register(close)` runs only after a successful `open_common()`; `close()` is the only
   place that calls `usb.close()` -> `dev.reset()`. A failed init therefore never resets the
   sensor, so the next systemd start meets the same stuck state (infinite loop).

## 9. Log-volume decomposition
```
Two independent causes:
  A) --debug on the unit  -> DEBUG hex dumps of USB/TLS traffic.
     2026-10-01: only 2 starts but 113,639 lines / 106 MB.
     2026-10-02: 0 starts but 100,428 lines / 93.6 MB.
  B) restart crash-loop   -> ~35-line traceback per attempt + systemd lines.
     2026-10-06: 5,267 starts / 258,073 lines / 24.4 MB (dominated by tracebacks).
  journald is at its 4 GiB default ceiling: 4.1 GiB on disk.
```
