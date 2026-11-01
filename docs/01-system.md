# System basics

## The machine

| | |
|---|---|
| Board | Gigabyte B650 AORUS ELITE AX, AMD GPU |
| OS | Bazzite (KDE Plasma, Wayland), image `ghcr.io/ublue-os/bazzite:stable` |
| Image as of 2026-11-01 | `44.20261026`, kernel `7.2.11-ogc4.1.fc44` |
| Disks | `nvme0n1` = Windows, `nvme1n1` = Bazzite (LUKS + btrfs, TPM2 unlock) + the `Secondary` NTFS data partition |
| Dual boot | GRUB, Windows is the default entry |

## Hostname

The hostname is now **`bazzite-prime`** (it was `PrimeBazzite` when this repo was started). Same command either way:

```bash
$ sudo hostnamectl set-hostname bazzite-prime
$ hostnamectl
```

## GRUB boot order: Windows first

Edit `/etc/default/grub` and add `GRUB_DEFAULT`:

```bash
$ sudo nano /etc/default/grub

GRUB_DEFAULT="Windows Boot Manager (on /dev/nvme0n1p1)"
GRUB_TIMEOUT=3
GRUB_TIMEOUT_STYLE=menu
GRUB_TERMINAL_OUTPUT="console"
```

```bash
# regenerate GRUB config
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# make sure Fedora/Bazzite (= GRUB) is first in the UEFI order, otherwise GRUB
# never runs and Windows boots directly
sudo efibootmgr -o 0001,0000
```

After a reboot the GRUB menu shows the same entries, but Windows is highlighted.

## What survives updates on an "immutable" OS

Bazzite is image based, but it is less immutable than it sounds:

- **`/usr` is read-only.** That is the only part that really is.
- **`/etc` persists.** `rpm-ostree` does a 3-way merge on every update (old image `/etc` → new image `/etc` → your `/etc`) and *your* edits win. The image defaults live in `/usr/etc`; if a file has no counterpart there (e.g. `/etc/fstab`) it is pure local state and can never conflict.
- **`/var` persists**, which includes `/home` (→ `/var/home`), `/mnt` (→ `/var/mnt`) and `/usr/local` (→ `/var/usrlocal`).

So a plain edit in `/etc` is the right way to configure the host. No overlay or "re-apply at boot" service is needed. `sudo ostree admin config-diff` lists everything that differs from the image.

One trap: **groups that ship with the image** (e.g. `plugdev`) live in `/usr/lib/group`, so `usermod -aG plugdev bazzite` silently does nothing. Seed the line into `/etc/group` first:

```bash
sudo sh -c 'grep -q "^plugdev:" /etc/group || getent group plugdev >> /etc/group
            usermod -aG plugdev bazzite'
```

Then **reboot**. Logging out is not enough, because the user has `Linger=yes` and `user@1000.service` keeps its old group set until the next boot.

## Layered packages

Only two packages are layered onto the image. Each one costs a reboot and slows updates down, so keep this list short:

```bash
$ rpm-ostree status --booted | grep Layered
          LayeredPackages: ghostty uhubctl
```

| Package | Why |
|---|---|
| `uhubctl` | Switching USB port power, see [USB peripherals](06-usb-peripherals.md) |
| `ghostty` | Terminal emulator |

Everything else goes into Flatpak, Homebrew or the `vscode` distrobox. See [Apps](04-apps.md).

## Keyboard: layout and function keys

**Layout.** The US international layouts on Linux do not behave exactly like Windows. The closest is *English (intl., with AltGr dead keys)*.

**Function row.** The keyboard (Cidoo ABM 084, which reports itself with an Apple USB id, `05ac:024f`) is driven by the `hid_apple` module, which puts the media keys first. `fnmode=2` makes F1–F12 the default again. With the keyboard model set to *Apple | Apple Aluminium (ANSI)*, it is applied in two places:

```bash
# /etc/modprobe.d/hid-apple.conf (copy in config/etc/modprobe.d/)
options hid_apple fnmode=2

# and as a kernel argument
$ rpm-ostree kargs --append-if-missing=hid_apple.fnmode=2
```

This replaces the original `fnkeys.service`, which wrote to `/sys/module/hid_apple/parameters/fnmode` at boot and is kept in [`archive/`](../archive/). The module option applies before the device binds, so there is no window where the keys are wrong.

## Running privileged commands

Claude Code (which maintains much of this setup) cannot run `sudo`. Anything that needs root is done by hand in a host terminal. Reading system state without root (`systemctl status`, `findmnt`, `ls /etc/...`) works fine.
