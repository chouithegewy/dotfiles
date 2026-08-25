#!/usr/bin/env bash
# Fresh-machine entry point. This script exists only to get the repo onto a box
# that has nothing on it yet: install git, clone, then hand off to bootstrap.sh,
# which does all the real work. Keep it small enough to read before running it.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/chouithegewy/dotfiles/main/install.sh)"
#
# Arguments after `--` are passed straight through to bootstrap.sh:
#
#   bash -c "$(curl -fsSL .../install.sh)" -- --min
#   bash -c "$(curl -fsSL .../install.sh)" -- -y -e codex,java
#
# Overridable: DOTFILES_REPO, DOTFILES_DIR, DOTFILES_BRANCH.
set -Eeuo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/chouithegewy/dotfiles.git}"
REPO_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
REPO_BRANCH="${DOTFILES_BRANCH:-main}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# bootstrap.sh runs as the target user and escalates per-task, so mirror that:
# never run the whole thing as root, or TARGET_USER resolves to root and every
# dotfile lands in /root.
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required but not installed."
  SUDO="sudo"
fi

# Same detection bootstrap.sh does, so an unsupported distro fails here rather
# than halfway through a clone.
detect_distro() {
  [ -r /etc/os-release ] || die "Cannot read /etc/os-release."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    arch|cachyos|endeavouros|manjaro) PKG_FAMILY="arch" ;;
    debian|ubuntu|pop|linuxmint|raspbian) PKG_FAMILY="deb" ;;
    *)
      case " ${ID_LIKE:-} " in
        *arch*) PKG_FAMILY="arch" ;;
        *debian*|*ubuntu*) PKG_FAMILY="deb" ;;
        *) die "Unsupported distro: ${ID:-unknown}" ;;
      esac
      ;;
  esac
}

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  log "git is missing; installing it so the repo can be cloned."
  case "$PKG_FAMILY" in
    arch) $SUDO pacman -Sy --needed --noconfirm git ca-certificates ;;
    deb)
      $SUDO apt-get update
      $SUDO apt-get install -y --no-install-recommends git ca-certificates
      ;;
  esac
  command -v git >/dev/null 2>&1 || die "git installation failed."
}

# Clone over HTTPS: a fresh box has no SSH key registered yet, and the repo is
# public. The tracked .gitconfig sets url.pushInsteadOf, so once stow runs,
# pushes go over SSH without touching the remote here.
fetch_repo() {
  if [ -e "$REPO_DIR" ]; then
    [ -d "$REPO_DIR/.git" ] || die "$REPO_DIR exists but is not a git repository."
    log "Repo already at $REPO_DIR; updating."
    git -C "$REPO_DIR" fetch --tags origin
    git -C "$REPO_DIR" pull --ff-only \
      || die "Cannot fast-forward $REPO_DIR. Resolve local changes and re-run."
  else
    log "Cloning $REPO_URL into $REPO_DIR"
    git clone --branch "$REPO_BRANCH" --recurse-submodules "$REPO_URL" "$REPO_DIR"
  fi
  # Re-run unconditionally: an interrupted first clone can leave the Neovim
  # submodule empty, which the dotfiles task then refuses to stow.
  git -C "$REPO_DIR" submodule update --init --recursive
}

main() {
  detect_distro
  ensure_git
  fetch_repo

  [ -f "$REPO_DIR/bootstrap.sh" ] || die "bootstrap.sh not found in $REPO_DIR."
  chmod +x "$REPO_DIR/bootstrap.sh"

  # bootstrap.sh prompts with `read -r -p`, which reads stdin. Under a
  # `curl | bash` pipe stdin is the script text, so every prompt would eat a
  # line of source or hit EOF. Reattach the terminal before handing off.
  #
  # Probe by opening /dev/tty, not with `[ -r /dev/tty ]`: with no controlling
  # terminal (cron, CI, a container) the node is readable but the open fails,
  # and under `set -e` that would kill the run. No tty just means prompts are
  # unavailable, so pass -y in that case.
  if [ ! -t 0 ] && { : < /dev/tty; } 2>/dev/null; then
    exec < /dev/tty
  fi

  log "Handing off to bootstrap.sh ${*:-(no arguments)}"
  exec "$REPO_DIR/bootstrap.sh" "$@"
}

main "$@"
