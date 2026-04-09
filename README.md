# Bootstrap Kit

This repo is a fresh-machine bootstrap for Arch Linux and Debian/Ubuntu.

It gives you:

- An interactive `bootstrap.sh` that detects the distro, installs packages, and lets you retry, skip, or diagnose failed steps.
- GNU Stow-managed dotfiles for `tmux`, `i3`, `i3status`, helper scripts, and a Rust `mold` config.
- GNU Stow-managed dotfiles for `tmux`, `i3`, `i3status`, helper scripts, Oh My Zsh custom shell init, and a Rust `mold` config.
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
- The i3 bar uses `i3status` plus a small wrapper so you get CPU temperature and compact per-core CPU usage in the bar.
- `zsh`, Oh My Zsh, `nvm`, and `pyenv` are installed together, with shell init managed from an Oh My Zsh custom file.
- `ripgrep` and `fd` are installed; on Debian/Ubuntu the shell aliases `fd` to `fdfind`.
- Slippi Launcher is built from source into `~/.local/src/slippi-launcher` and installed under `~/.local/opt/slippi-launcher`.
- Wi-Fi and Bluetooth stay clickable through `nm-applet` and `blueman-applet` in the i3 tray.
- On Debian/Ubuntu, Java 25 is installed from Eclipse Temurin and Google Chrome is installed from Google's `.deb`.
- The Rust Stow package enables `mold` for common Linux Rust targets via Cargo config.
- Full hibernation needs swap plus bootloader/initramfs resume wiring. The bootstrap attempts that for GRUB and systemd-boot, and leaves diagnostics in the log if your setup is different.
