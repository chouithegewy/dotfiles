# Bootstrap Kit

This repo is a fresh-machine bootstrap for Arch Linux and Debian/Ubuntu.

It gives you:

- An interactive `bootstrap.sh` that detects the distro, installs packages, and lets you retry, skip, or diagnose failed steps.
- GNU Stow-managed dotfiles for `tmux`, Sway, `i3status`, zsh, Codex CLI config/rules, helper scripts, Oh My Zsh custom shell init, Git, Ghostty, GitHub CLI, btop, Chrome flags, desktop portal preferences, default app handlers, and a Rust `mold` config.
- Laptop-aware setup for NetworkManager, Bluetooth, power profiles, and lid-close hibernation when swap is present.
- A `system/etc/` snapshot of local Arch install-time config that is useful reference material but is not applied automatically.

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

- Your current `~/.tmux.conf` is managed by Stow, with the local mouse and clipboard settings plus copy-mode bindings for the system clipboard.
- The Sway config uses Super as the modifier, Ghostty as the terminal, Rofi as the launcher, and `i3status` for the bar.
- `zsh`, Oh My Zsh, `nvm`, and `pyenv` are installed together, with `~/.zshrc` and Oh My Zsh custom init managed by Stow.
- Codex CLI is installed with npm through `nvm`; `~/.codex/config.toml` and `~/.codex/rules/default.rules` are managed by Stow, while auth, logs, history, sessions, and caches stay untracked.
- `~/.config/chrome-flags.conf`, Ghostty, Git, GitHub CLI non-auth config, btop, `~/.inputrc`, `~/.config/mimeapps.list`, and desktop portal preferences are managed by Stow. GitHub CLI hosts/auth files, browser profiles, cookies, tokens, and generated app state are intentionally not tracked.
- The Stow-managed `google-chrome` and `google-chrome-stable` launchers load `~/.config/chrome-flags.conf` and select native Wayland when a Wayland socket is available.
- `ripgrep` and `fd` are installed; on Debian/Ubuntu the shell aliases `fd` to `fdfind`.
- Slippi Launcher is built from source into `~/.local/src/slippi-launcher` and installed under `~/.local/opt/slippi-launcher`.
- Desktop applications include Thunar, GIMP, Discord, LibreOffice, VLC, OBS Studio, Google Chrome, calibre, and Slippi Launcher.
- Wi-Fi stays clickable through `nm-applet` under Sway.
- On Debian/Ubuntu, Java 25 is installed from Eclipse Temurin and Google Chrome is installed from Google's `.deb`.
- The Rust Stow package enables `mold` for common Linux Rust targets via Cargo config.
- `system/etc/` currently captures the local Arch `fstab`, `mkinitcpio.conf`, locale, console/X keyboard settings, valid login shells, and `pcspkr` blacklist for reference. Review those files before applying them to another machine because they include machine-specific boot and device settings.
- Full hibernation needs swap plus bootloader/initramfs resume wiring. The bootstrap attempts that for GRUB and systemd-boot, and leaves diagnostics in the log if your setup is different.
