# Bootstrap Kit

This repo is a fresh-machine bootstrap for Arch Linux and Debian/Ubuntu.

It gives you:

- An interactive `bootstrap.sh` that detects the distro, installs packages, and lets you retry, skip, or diagnose failed steps.
- GNU Stow-managed dotfiles for `tmux`, `i3`, `i3status`, helper scripts, and a Rust `mold` config.
- GNU Stow-managed dotfiles for `tmux`, `i3`, `i3status`, X startup/resources, zsh, Codex CLI config/rules, helper scripts, Oh My Zsh custom shell init, and a Rust `mold` config.
- Laptop-aware setup for NetworkManager, Bluetooth, power profiles, and lid-close hibernation when swap is present.

## Usage

Run the bootstrap as your normal user:

```bash
./bootstrap.sh
```

The script uses `sudo` only for system changes. It logs each step under `.bootstrap-logs/`.

## Why Stow

`stow` keeps the dotfiles in this repo and symlinks them into your home directory. That matters after a reinstall because:

- One repo becomes the source of truth instead of hand-copying configs.
- You can reapply the setup with one command.
- Updating a config here updates the live file cleanly through symlinks.

In this repo the Stow packages are under `dotfiles/`, and the bootstrap applies them to your home directory automatically.

## Notes

- Your current `~/.tmux.conf` has been copied into the `tmux` Stow package.
- The i3 config uses Alt as the modifier, `uxterm` as the terminal, `dmenu_run` as the launcher, `i3status` for the bar, and `maim` plus `xclip` for screenshot-to-clipboard.
- `~/.xinitrc` is managed by Stow, merges `~/.Xresources`, and runs `exec i3`, so `startx` does not fall back to the default three-xterm session.
- `~/.Xresources` is managed by Stow. `~/.Xauthority` is intentionally not tracked because it is generated runtime state.
- `zsh`, Oh My Zsh, `nvm`, and `pyenv` are installed together, with `~/.zshrc` and Oh My Zsh custom init managed by Stow.
- Codex CLI is installed with npm through `nvm`; `~/.codex/config.toml` and `~/.codex/rules/default.rules` are managed by Stow, while auth, logs, history, sessions, and caches stay untracked.
- `ripgrep` and `fd` are installed; on Debian/Ubuntu the shell aliases `fd` to `fdfind`.
- Slippi Launcher is built from source into `~/.local/src/slippi-launcher` and installed under `~/.local/opt/slippi-launcher`.
- Desktop applications include Thunar, GIMP, Discord, LibreOffice, VLC, OBS Studio, Google Chrome, calibre, and Slippi Launcher.
- Wi-Fi stays clickable through `nm-applet` in the i3 tray.
- On Debian/Ubuntu, Java 25 is installed from Eclipse Temurin and Google Chrome is installed from Google's `.deb`.
- The Rust Stow package enables `mold` for common Linux Rust targets via Cargo config.
- Full hibernation needs swap plus bootloader/initramfs resume wiring. The bootstrap attempts that for GRUB and systemd-boot, and leaves diagnostics in the log if your setup is different.
