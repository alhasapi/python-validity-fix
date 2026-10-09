# Local application & validation

Build the patched package (no root needed) and install it:

```bash
cd aur
makepkg -f
sudo ../local/install.sh
```

`install.sh` will:

1. install `python-validity 0.15-2` (patched),
2. install drop-ins
   (`/etc/systemd/system/open-fprintd.service.d/10-no-debug.conf`,
   `/etc/systemd/journald.conf.d/00-size.conf`, `SystemMaxUse=500M`),
3. restart journald and vacuum the journal,
4. disable `python3-validity-suspend-hotfix.service` (the in-process
   `Resume()` path replaces it),
5. restart `open-fprintd` / `python3-validity` and print validation output.

## Validate

```bash
local/validate.sh            # post-fix metrics
local/resume-matrix.sh 10 12 # N real suspend/resume cycles, logged
local/post-reboot-check.sh   # run after each reboot
```

All output is appended under `docs/`.

## Rollback

```bash
sudo pacman -U /var/cache/pacman/pkg/python-validity-0.15-1-any.pkg.tar.zst   # if cached
# otherwise build the unpatched AUR PKGBUILD and install it, then:
sudo rm -f /etc/systemd/system/open-fprintd.service.d/10-no-debug.conf \
           /etc/systemd/journald.conf.d/00-size.conf
sudo systemctl daemon-reload
sudo systemctl enable --now python3-validity-suspend-hotfix.service
sudo systemctl restart systemd-journald open-fprintd python3-validity
```
