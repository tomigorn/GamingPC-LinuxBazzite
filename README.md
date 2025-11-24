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

Additionally, the function keys aren't set first, but the media keys are first. we need to use fn + function keys in order to get something like F1. The fix is to set the Kayboard Model to be Apple | Apple Aluminium (ANSI) and then write in the terminal:

```bash
echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode
```

# Steelseries Dock: Shutdown issue

The Steelseries Arctis Nova Pro Wireless Headset comes with a Dock. This dock sends the wireless signal and charges the battery. it also has some OLED screen info. Under Windows, it turns off when the system turns off, because there is the Firmware Software "Steelseries GG" Managing the power state of the Dock. on linux, this software doesn't exist.

We need to turn off the hubs USB power by hand. Fortunalty, this is fairly easy.

we can use the program uhubctl to turn the device off:
```bash
# first install the program
$ sudo rpm-ostree install uhubctl

# we need to reboot the system
$ systemctl reboot

# now try out the turning off of the device. we find it with the name under hub 1-3 and port 3
$ sudo uhubctl
ksshaskpass: Unable to parse phrase "[sudo] password for bazzite: "
Current status for hub 7-1 [05e3:0608 USB2.0 Hub, USB 2.00, 4 ports, ppps]
  Port 1: 0100 power
  Port 2: 0103 power enable connect [1532:0078 Razer Razer Viper]
  Port 3: 0103 power enable connect [05ac:024f DAREU USB DEVICE]
  Port 4: 0103 power enable connect [3151:4010 ROYUAN Gaming Keyboard]
Current status for hub 2-3 [0bda:0411 Generic USB3.2 Hub, USB 3.20, 4 ports, ppps]
  Port 1: 02a0 power 5gbps Rx.Detect
  Port 2: 02e0 power 5gbps Polling
  Port 3: 02a0 power 5gbps Rx.Detect
  Port 4: 0203 power 5gbps U0 enable connect [046d:085e Logitech BRIO B268A3D9]
Current status for hub 1-3 [0bda:5411 Generic USB2.1 Hub, USB 2.10, 4 ports, ppps]
  Port 1: 0100 power
  Port 2: 0100 power
  Port 3: 0103 power enable connect [1038:12e0 SteelSeries Arctis Nova Pro Wireless]
  Port 4: 0100 power

# input for the program is the before found hub 1-3 and port 3, and the command off.
# if this works successfully, we can continue with setting up a service.
$ sudo uhubctl -l 1-3 -p 3 -a off
```

to setup a service, that executes a script. the script will look up the correct input for uhubctl, so the correct hub and port for the usb device, and then execute the command.

we need two files, /usr/local/bin/steelseries-usb-off.sh and /etc/systemd/system/steelseries-poweroff.service

now turn on the service
```bash
$ sudo systemctl daemon-reload
$ sudo systemctl enable steelseries-poweroff.service
Created symlink '/etc/systemd/system/halt.target.wants/steelseries-poweroff.service' → '/etc/systemd/system/steelseries-poweroff.service'.
Created symlink '/etc/systemd/system/reboot.target.wants/steelseries-poweroff.service' → '/etc/systemd/system/steelseries-poweroff.service'.
Created symlink '/etc/systemd/system/poweroff.target.wants/steelseries-poweroff.service' → '/etc/systemd/system/steelseries-poweroff.service'.

$ sudo systemctl restart steelseries-poweroff.service

# check the status
$ systemctl status steelseries-poweroff.service
○ steelseries-poweroff.service - Turn off SteelSeries USB on shutdown
     Loaded: loaded (/etc/systemd/system/steelseries-poweroff.service; enabled; preset: disabled)
    Drop-In: /usr/lib/systemd/system/service.d
             └─10-timeout-abort.conf
     Active: inactive (dead)
bazzite@PrimeBazzite:~$ 

# test the service to see if the OLED screen turns off
$ sudo systemctl start steelseries-poweroff.service
```