# Bootstrap Kit

This repo is a fresh-machine bootstrap for Arch Linux and Debian/Ubuntu.

It gives you:

- A one-command `install.sh` entry point for a machine with nothing on it: it installs `git`, clones this repo, and hands off to the bootstrap.
- An interactive `bootstrap.sh` that detects the distro, installs packages, and lets you retry, skip, or diagnose failed steps.
- GNU Stow-managed dotfiles for `tmux`, Sway, Waybar, zsh, Codex CLI config/rules, helper scripts, Oh My Zsh custom shell init, Git, foot, mako, GitHub CLI, btop, Chrome flags, desktop portal preferences, default app handlers, and a Rust `mold` config.
- Laptop-aware setup for NetworkManager, Bluetooth, power profiles, and lid-close hibernation, including provisioning a RAM-sized swap file when needed.
- A `system/etc/` snapshot of local Arch install-time config that is useful reference material but is not applied automatically.

## Usage

### Fresh machine

One command on a box with nothing on it. It installs `git`, clones this repo to
`~/dotfiles`, and hands off to `bootstrap.sh`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/chouithegewy/dotfiles/main/install.sh)"
```

Anything after `--` is passed straight through to `bootstrap.sh`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/chouithegewy/dotfiles/main/install.sh)" -- --min
bash -c "$(curl -fsSL https://raw.githubusercontent.com/chouithegewy/dotfiles/main/install.sh)" -- -y -e codex,java
```

Use the `bash -c "$(curl ...)"` form, not `curl ... | bash`. The bootstrap prompts
on stdin, and a pipe feeds it the script text instead of your answers. `install.sh`
reattaches the terminal where one exists; with no TTY at all (CI, a container),
pass `-y`.

Re-running updates the existing clone rather than recloning. `DOTFILES_REPO`,
`DOTFILES_DIR`, and `DOTFILES_BRANCH` override the defaults.

Do not run it as root. The bootstrap derives the target user from your login, so
a root run installs every dotfile into `/root`; it escalates per step with `sudo`
instead.

### Existing clone

Run the bootstrap as your normal user:

```bash
./bootstrap.sh
```

The script uses `sudo` only for system changes. It logs each step under `.bootstrap-logs/`.

After changing Secure Boot validation or repairing swap, rerun only the hibernation setup with:

```bash
./bootstrap.sh --hibernate-only
```

## Why Stow

`stow` keeps the dotfiles in this repo and symlinks them into your home directory. That matters after a reinstall because:

- One repo becomes the source of truth instead of hand-copying configs.
- You can reapply the setup with one command.
- Updating a config here updates the live file cleanly through symlinks.

In this repo the Stow packages are under `dotfiles/`, and the bootstrap applies them to your home directory automatically.

## Notes

- Your current `~/.tmux.conf` is managed by Stow, with the local mouse and clipboard settings plus copy-mode bindings for the system clipboard.
- The Sway config uses Super as the modifier, foot as the terminal, Rofi as the launcher, and Waybar for the bar.
- The foot config only overrides `font-decrease`, adding `Control+underscore` so Ctrl+Shift+- zooms out symmetrically with Ctrl+Shift+=. Overriding an action in `foot.ini` replaces its whole default list, so the built-in bindings are repeated there.
- `zsh`, Oh My Zsh, `pnpm`, and `pyenv` are installed together, with `~/.zshrc` and Oh My Zsh custom init managed by Stow. Node.js itself is installed and managed via `pnpm runtime set node lts -g` (no `nvm`); `pnpm add -g npm` makes `npm` available for third-party projects that expect it.
- Codex CLI is installed globally with `pnpm add -g @openai/codex`; `~/.codex/config.toml` and `~/.codex/rules/default.rules` are managed by Stow, while auth, logs, history, sessions, and caches stay untracked.
- `~/.config/chrome-flags.conf`, foot, Git, GitHub CLI non-auth config, btop, `~/.inputrc`, `~/.config/mimeapps.list`, and desktop portal preferences are managed by Stow. GitHub CLI hosts/auth files, browser profiles, cookies, tokens, and generated app state are intentionally not tracked.
- The Stow-managed `google-chrome` and `google-chrome-stable` launchers load `~/.config/chrome-flags.conf` and select native Wayland when a Wayland socket is available.
- `ripgrep` and `fd` are installed; on Debian/Ubuntu the shell aliases `fd` to `fdfind`.
- Slippi Launcher is built from source into `~/.local/src/slippi-launcher` and installed under `~/.local/opt/slippi-launcher`.
- Desktop applications include Thunar, GIMP, Discord, LibreOffice, VLC, OBS Studio, Google Chrome, calibre, and Slippi Launcher.
- Wi-Fi stays clickable through `nm-applet` under Sway. Waybar shows the active power profile, cycles profiles on click, and displays the selected profile and driver on hover.
- Notifications are handled by `mako`, which draws them through `wlr-layer-shell` on the `overlay` layer, so they float above the tiling layout instead of being tiled into it as ordinary windows. Chrome only probes for the `org.freedesktop.Notifications` D-Bus name at startup and falls back to drawing its own notification windows if nothing owns it, so restart Chrome once after the first install. `mako` is D-Bus activatable and the Sway config exports `WAYLAND_DISPLAY` into the activation environment, so it needs no `exec` line.
- Waybar shows volume and mute state via PipeWire's `wpctl`; scroll to adjust, left-click to toggle mute, right-click to open `pavucontrol` for per-app sliders and input/output device selection. `XF86AudioRaiseVolume`/`LowerVolume`/`Mute`/`MicMute` are bound in the Sway config (working even while locked) and also drive `wpctl`.
- On Debian/Ubuntu, Java 25 is installed from Eclipse Temurin and Google Chrome is installed from Google's `.deb`.
- The Rust Stow package enables `mold` for common Linux Rust targets via Cargo config.
- `system/etc/` currently captures the local Arch `fstab`, `mkinitcpio.conf`, locale, console/X keyboard settings, valid login shells, and `pcspkr` blacklist for reference. Review those files before applying them to another machine because they include machine-specific boot and device settings.
- Full hibernation needs one swap target large enough for RAM plus bootloader/initramfs resume wiring. The bootstrap selects the largest active swap, offers to grow or create a swap file rounded up to a 4 GiB boundary (16 GiB on a 16 GiB machine), and configures partition or swap-file resume for GRUB and systemd-boot.
- On Debian/Ubuntu, the hibernation setup installs an early polkit rule that enables hibernation only for active, local members of the `sudo` group. Reboot after the setup; the bootstrap deliberately does not restart logind inside an active graphical session.
- On Ubuntu, Secure Boot enables kernel lockdown and can remove the kernel's `disk` sleep state. The bootstrap detects this and stops before changing swap or lid behavior; disable Secure Boot validation, reboot, and rerun the hibernation step if full hibernation is desired.
