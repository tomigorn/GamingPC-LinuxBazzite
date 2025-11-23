# GamingPC-LinuxBazzite

Bazzite with KDE Plasma and Wayland with an AMD GPU

# set PC hostname
```bash
# set the hostname to PrimeBazzite
$ sudo hostnamectl set-hostname PrimeBazzite

# check the hostname:
$ hostnamectl
     Static hostname: PrimeBazzite
           Icon name: computer-desktop
             Chassis: desktop 🖥️
          Machine ID: == REDACTED ==
             Boot ID: == REDACTED ==
    Operating System: Bazzite                         
         CPE OS Name: cpe:/o:universal-blue:bazzite:43
      OS Support End: Wed 2026-12-02
OS Support Remaining: 1y 1w 2d                        
            OS Image: bazzite-43.20251118
              Kernel: Linux 6.17.7-ba14.fc43.x86_64
        Architecture: x86-64
     Hardware Vendor: Gigabyte Technology Co., Ltd.
      Hardware Model: B650 AORUS ELITE AX
    Firmware Version: FA3a
       Firmware Date: Tue 2024-02-06
        Firmware Age: 1y 9month 2w 2d
```

# set VS Code terminal colours
- File -> Preferences -> Settings -> top right corener: Open Settings (JSON)
- or ctrl + , -> top right corener: Open Settings (JSON)

and add the lines:

```json
   "terminal.integrated.defaultProfile.linux": "bash",
   "terminal.integrated.profiles.linux": {
      "bash": {
      "path": "/usr/bin/flatpak-spawn",
      "args": ["--host", "--env=TERM=xterm-256color", "bash"],
      "icon": "terminal-bash",
      "overrideName": true
      }
   },
    "terminal.integrated.fontFamily": "Symbols Nerd Font Mono",
```

# VS Code: high CPU usage because of process 'rg'
the process rg scans the filesystem and indexes files. this is important for later searches and such. however, because this is my personal Computer with 2TB SSD and lots of Games and such, the files take quite long to index. we can exclude everything we don´t need:


- File -> Preferences -> Settings -> top right corener: Open Settings (JSON)
- or ctrl + , -> top right corener: Open Settings (JSON)

```json
    "search.exclude": {
        "**/*": true,
        "/home/bazzite/Desktop/**": false,
        "/home/bazzite/Documents/**": false,
        "/home/bazzite/Downloads/**": false,
        "/home/bazzite/Projects/**": false
    },
    "search.followSymlinks": false
```

# VS Code: keyring / keychain issue

on KDE and with the flatpak version of VS code, there is the issue, that it will loose your login information because of not being able to connect to the OS keychain. to solve this do 2 things:

- CTRL + Shift + P : Configure Runtime Arguments
add the line
```bash
	"password-store":"kwallet5"
```
- and adjust the flatpak launch arguments with
```bash
$ flatpak override --user --talk-name=org.kde.kwalletd5 --talk-name=org.freedesktop.secrets com.visualstudio.code
```
then restart the computer.

# Brave: Teams PWA App shortcut
In Brave we can make Apps from websites. One such example is Teams. Because the Teams app doesn´t exist on Bazzite anymore, also not with flathub, we can simply install this PWA app. This is as easy as pressing the install top button at the right of the URL input.

However, I would like to treat Teams as a program, and be able to search it in the start menu, or perhaps also have a shortcut on my desktop or in the start menu.

In Brave, open:
```plaintext
brave://apps/
```

right click the Teams PWA and create shortcut in the application menu

# create a GitHub SSH key

Ed is better and recommended by GitHub:

| Feature               | Ed25519                   | RSA                     |
| --------------------- | ------------------------- | ----------------------- |
| Security              | ✅ Stronger, modern crypto | ✅ Secure but older      |
| Speed                 | ⚡ Faster                  | 🐢 Slower               |
| Key size              | 🔹 Very small             | 🔸 Very large           |
| Resistance to attacks | ✅ Better                  | ⚠️ More legacy risk     |
| GitHub recommendation | ✅ Preferred               | ⚠️ Supported but legacy |

```bash
$ ssh-keygen -t ed25519 -C "tomigorn@gmail.com -> GitHub" -f ~/.ssh/GitHub
```

then in the ~/.ssh/config also add GitHub as a host. this is only needed because we want a non-default file name for the ssh-key.

```bash
Host github.com
    User tomigorn@gmail.com
    IdentityFile ~/.ssh/GitHub
```

Then make sure to also set the username and email for the local git user:

```bash
$ git config --global user.name "tomigorn"
$ git config --global user.name
tomigorn

$ git config --global user.email "tomigorn@gmail.com"
$ git config --global user.email
tomigorn@gmail.com
```

# Fix Keyboard Layout
The keyboard layout of US intl or US intl with dead keys isn't the same as in windows. on a immutable OS like Bazzite, we sadly can't fix this. closest is to use English (intl., with AltGr dead keys) and get used to the slight differences.