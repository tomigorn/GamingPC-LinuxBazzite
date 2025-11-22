# GamingPC-LinuxBazzite

Bazzite with KDE Plasma and Wayland with an AMD GPU

# hostname
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

# set VS Code terminal
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
