# Development environment

## VS Code in a distrobox

The Flathub VS Code is sandboxed, which breaks the integrated terminal, language toolchains and dev containers. So VS Code runs from Microsoft's own RPM inside a Fedora **distrobox called `vscode`**, and the launcher is exported to the host start menu.

```bash
# on the host
distrobox create --name vscode --image registry.fedoraproject.org/fedora:latest
distrobox enter vscode

# inside the container: Microsoft's repo, then VS Code
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install code

# export to the host menu (creates ~/.local/share/applications/code.desktop)
distrobox-export --app code
```

How it fits together:

- **`~` is shared** between host and container: same files, same dotfiles.
- **Packages are not shared.** Build tools and runtimes go in the container with `sudo dnf install`, which keeps the host image clean.
- **Host commands** from inside the container: `distrobox-host-exec <cmd>`.
- **Host mounts** are under `/run/host`, e.g. `/run/host/mnt/Secondary`. The plain `/mnt/Secondary` path does not exist inside the container.
- The container's hostname is the host's (`bazzite-prime`). Check `/run/.containerenv` to tell which side you are on.
- Bazzite's updater upgrades the container too (`dnf upgrade` inside every distrobox), see [Updates](03-updates.md).

Packages added to the container on top of the Fedora image (as of 2026-11-01): `code`, `gcc`, `gcc-c++`, `cmake`, `git`, `ShellCheck`, `hidapi-devel`, `qt6-qtdeclarative-devel`, `python3-pillow`, `poppler-utils`, `qpdf`, `libjpeg-turbo-utils`, `gdu`, `bind-utils`, `mtr`, `tcpdump`, `traceroute`, `whois`, `tree`, `rsync`, `zip`/`unzip`, `cpio`, `pigz`, `bc`, `lsof`.

### Legacy: VS Code as a Flatpak

These fixes were needed while VS Code was the Flathub version. **None of them apply to the distrobox install.** They are kept here in case it ever goes back.

- **Terminal**: the Flatpak terminal opened inside the sandbox. A profile that calls `/usr/bin/flatpak-spawn --host --env=TERM=xterm-256color bash` and the font `Symbols Nerd Font Mono` gave a real host shell.
- **High CPU from `rg`**: the Flatpak's search indexer walked the whole 2 TB disk. Fixed with `"search.exclude": {"**/*": true, ...}`, un-excluding only Desktop, Documents, Downloads and Projects, plus `"search.followSymlinks": false`.
- **Lost logins (keyring)**: `"password-store": "kwallet5"` in *Configure Runtime Arguments*, plus `flatpak override --user --talk-name=org.kde.kwalletd5 --talk-name=org.freedesktop.secrets com.visualstudio.code`.

## Git, GitHub SSH key and commit signing

### SSH key

One Ed25519 key per purpose. GitHub's is `~/.ssh/gitHub-Tomigorn`:

```bash
ssh-keygen -t ed25519 -C "you@example.com -> GitHub" -f ~/.ssh/gitHub-Tomigorn
```

The public key is added on GitHub **twice**: once as an *Authentication key* and once as a *Signing key* (Settings → SSH and GPG keys).

`~/.ssh/config` (the GitHub block). Note that `User` must be `git`, not your email address:

```
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/gitHub-Tomigorn
    IdentitiesOnly yes
    PreferredAuthentications publickey
```

```bash
$ ssh -T git@github.com
Hi tomigorn! You've successfully authenticated, but GitHub does not provide shell access.
```

### Identity and signing per folder, not globally

There is deliberately **no global `user.name`/`user.email`**. Every repo under `~/Projects/` (or `~/development/private/`) picks up the private identity automatically through `includeIf`. A repo cloned anywhere else gets no identity and refuses to commit, so it can't accidentally be committed under the wrong name.

`~/.gitconfig`:

```ini
[init]
    defaultBranch = main
[pull]
    ff = only
[includeIf "gitdir:~/Projects/"]
    path = ~/.gitconfig-private
[includeIf "gitdir:~/development/private/"]
    path = ~/.gitconfig-private
```

`~/.gitconfig-private`:

```ini
[user]
    name = tomigorn
    email = you@example.com
    signingkey = ~/.ssh/gitHub-Tomigorn.pub
[core]
    sshCommand = ssh -i ~/.ssh/gitHub-Tomigorn -o IdentitiesOnly=yes
[gpg]
    format = ssh
[gpg "ssh"]
    allowedSignersFile = ~/.ssh/allowed_signers-private
[commit]
    gpgsign = true
[tag]
    gpgsign = true
```

Commits are signed with the **SSH key** (no GPG keyring needed), and GitHub shows them as *Verified*.

`~/.ssh/allowed_signers-private` lists every machine's signing public key, one line each (`you@example.com ssh-ed25519 AAAA...`). Without it git can't verify your own signatures locally, and `git log --show-signature` reports them as untrusted (`U`). Copy the same file to every machine you commit from.

```bash
# check: identity comes from the include, signatures verify ("G")
$ cd ~/Projects/GamingPC-LinuxBazzite
$ git config --show-origin user.email
file:/home/bazzite/.gitconfig-private   you@example.com
$ git log --format='%h %G? %s' -3
```

### Where the repos live

| Repo | Path |
|---|---|
| this one | `~/Projects/GamingPC-LinuxBazzite` |
| HomeLab-Unraid-Tower | `~/Projects/unraid-nas` |

## Claude Code

Claude Code runs as the VS Code extension inside the `vscode` distrobox, plus the CLI in `~/.local/bin/claude`. Its instructions for this machine live in `~/.claude/CLAUDE.md`, and what it has learned about the setup lives in `~/.claude/projects/-home-bazzite/memory/`.

`claude-remote.service` (user unit, copy in [`config/home/bazzite/.config/systemd/user/`](../config/home/bazzite/.config/systemd/user/)) keeps a `claude remote-control` session running so the machine can be reached from the Claude app, and `claude-remote-restart.timer` restarts it periodically.
