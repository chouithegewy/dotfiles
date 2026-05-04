#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${ROOT_DIR}/.bootstrap-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
CURRENT_LOG="${LOG_DIR}/bootstrap.log"

DISTRO_ID=""
DISTRO_LIKE=""
PKG_FAMILY=""
AUR_HELPER=""
IS_CONTAINER=0
IS_LAPTOP=0
SWAP_NAME=""
SWAP_TYPE=""
SWAP_SIZE_BYTES=0
MEM_TOTAL_BYTES=0

ARCH_COMMON_PACKAGES=(
  acpi
  base-devel
  blueman
  bluez
  bluez-utils
  ca-certificates
  calibre
  curl
  dbus
  dex
  dmenu
  eza
  git
  fd
  gimp
  i3-wm
  i3lock
  i3status
  jq
  libpulse
  libreoffice-fresh
  lm_sensors
  maim
  mold
  neovim
  network-manager-applet
  networkmanager
  obs-studio
  polkit-gnome
  power-profiles-daemon
  psmisc
  ripgrep
  rofi
  rustup
  stow
  thunar
  tmux
  unzip
  vlc
  wget
  xclip
  xdg-desktop-portal
  xdg-desktop-portal-xapp
  xorg-server
  xorg-xinit
  xorg-xrandr
  xorg-xsetroot
  xss-lock
  xterm
  zsh
  zip
)

DEB_COMMON_PACKAGES=(
  acpi
  bluez
  blueman
  build-essential
  ca-certificates
  curl
  dbus-user-session
  dex
  dmenu
  eza
  fd-find
  git
  gimp
  gnupg
  i3-wm
  i3lock
  i3status
  jq
  libreoffice
  lm-sensors
  maim
  neovim
  network-manager
  network-manager-gnome
  obs-studio
  policykit-1-gnome
  power-profiles-daemon
  psmisc
  pulseaudio-utils
  ripgrep
  rofi
  stow
  thunar
  tmux
  unzip
  vlc
  wget
  xclip
  xdg-desktop-portal
  xdg-desktop-portal-xapp
  xorg
  xss-lock
  xterm
  zsh
  zip
)

MOLD_BUILD_DEPS=(
  clang
  cmake
  lld
  ninja-build
  pkg-config
  zlib1g-dev
)

PYENV_DEB_BUILD_DEPS=(
  libbz2-dev
  libffi-dev
  liblzma-dev
  libncursesw5-dev
  libreadline-dev
  libsqlite3-dev
  libssl-dev
  tk-dev
  xz-utils
  zlib1g-dev
)

PYENV_ARCH_BUILD_DEPS=(
  bzip2
  libffi
  openssl
  readline
  sqlite
  tk
  xz
  zlib
)

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

human_bytes() {
  numfmt --to=iec --suffix=B "$1"
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's|[ /]+|-|g; s|[^a-z0-9._-]||g'
}

prompt() {
  local message="$1"
  local default="${2:-}"
  local answer

  if [ -n "$default" ]; then
    read -r -p "${message} [${default}]: " answer
    printf '%s' "${answer:-$default}"
    return
  fi

  read -r -p "${message}: " answer
  printf '%s' "$answer"
}

confirm_yes() {
  local message="$1"
  local answer
  answer="$(prompt "${message} [Y/n]" "Y")"
  case "${answer,,}" in
    y|yes|"") return 0 ;;
    n|no) return 1 ;;
    *) warn "Please answer y or n."; confirm_yes "$message" ;;
  esac
}

run_logged() {
  local description="$1"
  shift

  log
  log "==> ${description}"
  printf '    ' | tee -a "$CURRENT_LOG" >/dev/null
  printf '%q ' "$@" | tee -a "$CURRENT_LOG" >/dev/null
  printf '\n' | tee -a "$CURRENT_LOG" >/dev/null

  "$@" 2>&1 | tee -a "$CURRENT_LOG"
}

run_root_logged() {
  local description="$1"
  shift

  if [ "$EUID" -eq 0 ]; then
    run_logged "$description" "$@"
  else
    run_logged "$description" sudo "$@"
  fi
}

run_target_shell_logged() {
  local description="$1"
  local script="$2"

  if [ "$EUID" -eq 0 ]; then
    run_logged "$description" sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" bash -lc "$script"
  else
    run_logged "$description" bash -lc "$script"
  fi
}

ensure_target_file() {
  local file="$1"

  if [ "$EUID" -eq 0 ]; then
    run_logged "Create ${file}" sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" bash -lc "mkdir -p '$(dirname "$file")' && touch '$file'"
  else
    run_logged "Create ${file}" bash -lc "mkdir -p '$(dirname "$file")' && touch '$file'"
  fi
}

replace_or_append_assignment() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"
  if [ -f "$file" ]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { done = 0 }
      $0 ~ "^" key "=" {
        print key "=" value
        done = 1
        next
      }
      { print }
      END {
        if (!done) {
          print key "=" value
        }
      }
    ' "$file" >"$tmp"
  else
    printf '%s=%s\n' "$key" "$value" >"$tmp"
  fi

  run_root_logged "Install ${file}" install -m 0644 "$tmp" "$file"
  rm -f "$tmp"
}

ensure_grub_kernel_arg() {
  local arg="$1"
  local grub_file="/etc/default/grub"
  local current quoted

  [ -f "$grub_file" ] || return 1

  current="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" | head -n1 || true)"
  if [ -n "$current" ]; then
    current="${current#*=}"
    current="${current%\"}"
    current="${current#\"}"
  else
    current="$(grep -E '^GRUB_CMDLINE_LINUX=' "$grub_file" | head -n1 || true)"
    current="${current#*=}"
    current="${current%\"}"
    current="${current#\"}"
  fi

  current="$(printf '%s' "$current" | sed -E 's/(^| )resume=[^ ]+//g; s/(^| )resume_offset=[^ ]+//g; s/  +/ /g; s/^ //; s/ $//')"
  current="${current:+${current} }${arg}"
  quoted="\"${current}\""

  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
    replace_or_append_assignment "$grub_file" "GRUB_CMDLINE_LINUX_DEFAULT" "$quoted"
  else
    replace_or_append_assignment "$grub_file" "GRUB_CMDLINE_LINUX" "$quoted"
  fi
}

ensure_loader_entry_arg() {
  local arg="$1"
  local entry file tmp default_pattern

  if [ -f /boot/loader/loader.conf ]; then
    default_pattern="$(awk '/^default[[:space:]]+/ { print $2; exit }' /boot/loader/loader.conf)"
    default_pattern="${default_pattern%.conf}"
    if [ -n "$default_pattern" ]; then
      shopt -s nullglob
      local -a matches=(/boot/loader/entries/${default_pattern}.conf)
      shopt -u nullglob
      if [ "${#matches[@]}" -gt 0 ]; then
        entry="${matches[0]}"
      fi
    fi
  fi

  if [ -z "${entry:-}" ]; then
    entry="$(find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' | head -n1 || true)"
  fi
  [ -n "$entry" ] || return 1

  file="$entry"
  tmp="$(mktemp)"
  awk -v arg="$arg" '
    BEGIN { done = 0 }
    /^options[[:space:]]+/ {
      line = $0
      sub(/(^| )resume=[^ ]+/, "", line)
      sub(/(^| )resume_offset=[^ ]+/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      sub(/[[:space:]]+$/, "", line)
      print line " " arg
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print "options " arg
      }
    }
  ' "$file" >"$tmp"
  run_root_logged "Install ${file}" install -m 0644 "$tmp" "$file"
  rm -f "$tmp"
}

require_linux() {
  [ "$(uname -s)" = "Linux" ] || die "This bootstrap only supports Linux."
}

detect_container() {
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    IS_CONTAINER=1
    return
  fi

  if grep -qaE '(docker|podman|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
    IS_CONTAINER=1
  fi
}

detect_distro() {
  [ -r /etc/os-release ] || die "Cannot read /etc/os-release."
  # shellcheck source=/dev/null
  . /etc/os-release

  DISTRO_ID="${ID:-}"
  DISTRO_LIKE="${ID_LIKE:-}"

  case "$DISTRO_ID" in
    arch)
      PKG_FAMILY="arch"
      ;;
    ubuntu|debian)
      PKG_FAMILY="deb"
      ;;
    *)
      case "$DISTRO_LIKE" in
        *arch*)
          PKG_FAMILY="arch"
          ;;
        *debian*|*ubuntu*)
          PKG_FAMILY="deb"
          ;;
        *)
          die "Unsupported distro: ${DISTRO_ID:-unknown}"
          ;;
      esac
      ;;
  esac

  if [ "$PKG_FAMILY" = "arch" ]; then
    if command -v paru >/dev/null 2>&1; then
      AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then
      AUR_HELPER="yay"
    fi
  fi
}

detect_laptop() {
  if [ "$IS_CONTAINER" -eq 1 ]; then
    IS_LAPTOP=0
    return
  fi

  if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    IS_LAPTOP=1
    return
  fi

  if [ -r /sys/class/dmi/id/chassis_type ]; then
    case "$(cat /sys/class/dmi/id/chassis_type)" in
      8|9|10|14)
        IS_LAPTOP=1
        ;;
    esac
  fi
}

detect_swap() {
  if [ "$IS_CONTAINER" -eq 1 ]; then
    SWAP_NAME=""
    SWAP_TYPE=""
    SWAP_SIZE_BYTES=0
    MEM_TOTAL_BYTES=0
    return
  fi

  MEM_TOTAL_BYTES="$(( $(awk '/MemTotal:/ { print $2 }' /proc/meminfo) * 1024 ))"

  if command -v swapon >/dev/null 2>&1; then
    local line
    line="$(swapon --show=NAME,TYPE,SIZE --bytes --noheadings | head -n1 || true)"
    if [ -n "$line" ]; then
      read -r SWAP_NAME SWAP_TYPE SWAP_SIZE_BYTES <<<"$line"
    fi
  fi
}

print_summary() {
  log "Bootstrap root: ${ROOT_DIR}"
  log "Logs: ${LOG_DIR}"
  log "Target user: ${TARGET_USER}"
  log "Target home: ${TARGET_HOME}"
  log "Distro family: ${PKG_FAMILY} (${DISTRO_ID})"
  if [ "$IS_CONTAINER" -eq 1 ]; then
    log "Container detection: yes"
  else
    log "Container detection: no"
  fi

  if [ -n "$AUR_HELPER" ]; then
    log "Arch helper: ${AUR_HELPER}"
  elif [ "$PKG_FAMILY" = "arch" ]; then
    log "Arch helper: none detected"
  fi

  if [ "$IS_LAPTOP" -eq 1 ]; then
    log "Laptop detection: yes"
  else
    log "Laptop detection: no"
  fi

  if [ -n "$SWAP_NAME" ]; then
    log "Swap: ${SWAP_NAME} (${SWAP_TYPE}, $(human_bytes "$SWAP_SIZE_BYTES"))"
  else
    log "Swap: none detected"
  fi
}

task() {
  local label="$1"
  local run_fn="$2"
  local diag_fn="$3"
  local choice

  if ! confirm_yes "Run step '${label}'?"; then
    log "Skipped: ${label}"
    return 0
  fi

  CURRENT_LOG="${LOG_DIR}/$(slugify "$label").log"
  : >"$CURRENT_LOG"

  while true; do
    if "$run_fn"; then
      log
      log "Completed: ${label}"
      return 0
    fi

    warn "Step failed: ${label}"
    warn "Log: ${CURRENT_LOG}"
    choice="$(prompt "Choose retry, skip, diagnose, or abort [r/s/d/a]" "r")"

    case "${choice,,}" in
      r|retry)
        continue
        ;;
      s|skip)
        log "Skipped after failure: ${label}"
        return 0
        ;;
      d|diagnose)
        "$diag_fn"
        ;;
      a|abort)
        die "Aborted during ${label}"
        ;;
      *)
        warn "Unknown choice: ${choice}"
        ;;
    esac
  done
}

diagnose_packages() {
  log
  log "Package manager diagnostics:"
  case "$PKG_FAMILY" in
    arch)
      log "- pacman version: $(pacman --version | head -n1)"
      if [ -n "$AUR_HELPER" ]; then
        log "- AUR helper version: $($AUR_HELPER --version | head -n1)"
      else
        log "- No AUR helper detected."
      fi
      ;;
    deb)
      log "- apt version: $(apt-get --version | head -n1)"
      ;;
  esac
}

diagnose_dotfiles() {
  log
  log "Stow diagnostics:"
  run_target_shell_logged "List dotfile packages" "cd '$ROOT_DIR/dotfiles' && find . -maxdepth 2 -type f | sort"
}

diagnose_java() {
  log
  log "Java diagnostics:"
  command -v java >/dev/null 2>&1 && java -version || true
  command -v javac >/dev/null 2>&1 && javac -version || true
}

diagnose_chrome() {
  log
  log "Chrome diagnostics:"
  if [ "$PKG_FAMILY" = "arch" ] && [ -z "$AUR_HELPER" ]; then
    log "- Chrome on Arch needs an AUR helper. The bootstrap can build paru-bin if you allow it."
  fi
  command -v google-chrome >/dev/null 2>&1 && google-chrome --version || true
  command -v google-chrome-stable >/dev/null 2>&1 && google-chrome-stable --version || true
}

diagnose_discord() {
  log
  log "Discord diagnostics:"
  command -v discord >/dev/null 2>&1 && log "- discord command: $(command -v discord)" || log "- discord command: missing"
  case "$PKG_FAMILY" in
    arch)
      pacman -Q discord >/dev/null 2>&1 && pacman -Q discord || true
      ;;
    deb)
      dpkg-query -W -f='${Package} ${Version}\n' discord 2>/dev/null || true
      ;;
  esac
}

diagnose_calibre() {
  log
  log "Calibre diagnostics:"
  command -v calibre >/dev/null 2>&1 && calibre --version || true
}

diagnose_rust() {
  log
  log "Rust diagnostics:"
  run_target_shell_logged "Rust toolchain check" "command -v rustup >/dev/null 2>&1 && rustup show || true"
}

diagnose_shell_tooling() {
  log
  log "Shell tooling diagnostics:"
  command -v zsh >/dev/null 2>&1 && zsh --version || true
  run_target_shell_logged "Shell runtime check" "printf 'Default shell: %s\n' \"\$(getent passwd '$TARGET_USER' | cut -d: -f7)\"; [ -d '$TARGET_HOME/.oh-my-zsh' ] && printf 'oh-my-zsh: installed\n' || printf 'oh-my-zsh: missing\n'; [ -d '$TARGET_HOME/.nvm' ] && printf 'nvm dir: present\n' || printf 'nvm dir: missing\n'; [ -d '$TARGET_HOME/.pyenv' ] && printf 'pyenv dir: present\n' || printf 'pyenv dir: missing\n'; zsh -lic 'command -v nvm >/dev/null 2>&1 && echo nvm: ready || echo nvm: missing; command -v pyenv >/dev/null 2>&1 && echo pyenv: ready || echo pyenv: missing; command -v fd >/dev/null 2>&1 && echo fd: ready || command -v fdfind >/dev/null 2>&1 && echo fdfind: ready || echo fd: missing'"
}

diagnose_codex_cli() {
  log
  log "Codex CLI diagnostics:"
  run_target_shell_logged "Codex CLI check" "export NVM_DIR='$TARGET_HOME/.nvm'; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; command -v codex >/dev/null 2>&1 && codex --version || echo 'codex: missing'"
}

diagnose_mold() {
  log
  log "mold diagnostics:"
  command -v mold >/dev/null 2>&1 && mold --version || true
  run_target_shell_logged "Cargo mold config" "if [ -f '$TARGET_HOME/.cargo/config.toml' ]; then sed -n '1,120p' '$TARGET_HOME/.cargo/config.toml'; fi"
}

diagnose_services() {
  log
  log "Service diagnostics:"
  run_root_logged "Systemctl status summary" systemctl --no-pager --full status NetworkManager bluetooth power-profiles-daemon || true
}

diagnose_hibernate() {
  log
  log "Hibernate diagnostics:"
  log "- Memory: $(human_bytes "$MEM_TOTAL_BYTES")"
  if [ -n "$SWAP_NAME" ]; then
    log "- Swap: ${SWAP_NAME} (${SWAP_TYPE}, $(human_bytes "$SWAP_SIZE_BYTES"))"
  else
    log "- No swap detected."
  fi
  log "- Kernel cmdline:"
  cat /proc/cmdline
  log "- Known boot targets:"
  [ -f /etc/default/grub ] && log "  * /etc/default/grub"
  [ -d /boot/loader/entries ] && log "  * /boot/loader/entries"
}

diagnose_slippi() {
  log
  log "Slippi diagnostics:"
  run_target_shell_logged "Slippi install check" "if [ -x '$TARGET_HOME/.local/bin/slippi-launcher' ]; then echo 'launcher wrapper: present'; else echo 'launcher wrapper: missing'; fi; if [ -d '$TARGET_HOME/.local/opt/slippi-launcher/current' ]; then printf 'install dir: %s\n' '$TARGET_HOME/.local/opt/slippi-launcher/current'; find '$TARGET_HOME/.local/opt/slippi-launcher/current' -maxdepth 1 \\( -type f -o -type l \\) | sort; else echo 'install dir: missing'; fi; if [ -d '$TARGET_HOME/.local/src/slippi-launcher/.git' ]; then printf 'source dir: %s\n' '$TARGET_HOME/.local/src/slippi-launcher'; fi; zsh -lic 'command -v node >/dev/null 2>&1 && node -v || true; command -v npm >/dev/null 2>&1 && npm -v || true'"
}

refresh_arch() {
  run_root_logged "Refresh and upgrade pacman packages" pacman -Syu --noconfirm
}

refresh_deb() {
  run_root_logged "Refresh apt metadata" apt-get update
}

install_common_arch() {
  run_root_logged "Install Arch base packages" pacman -S --needed --noconfirm "${ARCH_COMMON_PACKAGES[@]}"
}

install_common_deb() {
  run_root_logged "Install Debian/Ubuntu base packages" apt-get install -y "${DEB_COMMON_PACKAGES[@]}"
}

ensure_aur_helper() {
  local tmpdir

  [ -n "$AUR_HELPER" ] && return 0

  if ! confirm_yes "No AUR helper detected. Build and install 'paru-bin' so Google Chrome can be installed?"; then
    return 1
  fi

  if [ "$EUID" -eq 0 ]; then
    tmpdir="$(sudo -u "$TARGET_USER" mktemp -d)"
  else
    tmpdir="$(mktemp -d)"
  fi

  run_root_logged "Install Arch AUR build dependencies" pacman -S --needed --noconfirm base-devel git
  run_target_shell_logged "Clone paru-bin" "git clone https://aur.archlinux.org/paru-bin.git '$tmpdir/paru-bin'"
  run_target_shell_logged "Build and install paru-bin" "cd '$tmpdir/paru-bin' && makepkg -si --noconfirm"
  AUR_HELPER="paru"
}

install_java_arch() {
  run_root_logged "Install OpenJDK 25 on Arch" pacman -S --needed --noconfirm jdk-openjdk
}

install_java_deb() {
  local tmpdir archive extracted

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/openjdk25.tar.gz"
  run_logged "Download Temurin OpenJDK 25" curl -fsSL -o "$archive" "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"
  run_logged "Extract Temurin archive" tar -xzf "$archive" -C "$tmpdir"
  extracted="$(find "$tmpdir" -maxdepth 1 -type d -name 'jdk-*' | head -n1)"
  [ -n "$extracted" ] || return 1

  run_root_logged "Refresh /opt/jdk-25" rm -rf /opt/jdk-25
  run_root_logged "Install JDK 25 into /opt/jdk-25" mv "$extracted" /opt/jdk-25
  run_root_logged "Register java alternative" update-alternatives --install /usr/bin/java java /opt/jdk-25/bin/java 2525
  run_root_logged "Register javac alternative" update-alternatives --install /usr/bin/javac javac /opt/jdk-25/bin/javac 2525
  run_root_logged "Select java alternative" update-alternatives --set java /opt/jdk-25/bin/java
  run_root_logged "Select javac alternative" update-alternatives --set javac /opt/jdk-25/bin/javac

  local profile_file tmp_profile
  profile_file="/etc/profile.d/java25.sh"
  tmp_profile="$(mktemp)"
  cat >"$tmp_profile" <<'EOF'
export JAVA_HOME=/opt/jdk-25
export PATH="$JAVA_HOME/bin:$PATH"
EOF
  run_root_logged "Install ${profile_file}" install -m 0644 "$tmp_profile" "$profile_file"
  rm -f "$tmp_profile"
}

install_java() {
  case "$PKG_FAMILY" in
    arch) install_java_arch ;;
    deb) install_java_deb ;;
  esac
}

install_chrome_arch() {
  ensure_aur_helper || return 1
  run_target_shell_logged "Install Google Chrome from AUR" "$AUR_HELPER -S --needed --noconfirm google-chrome"
}

install_chrome_deb() {
  local tmpdir deb_path

  tmpdir="$(mktemp -d)"
  deb_path="${tmpdir}/google-chrome-stable_current_amd64.deb"
  run_logged "Download Google Chrome" curl -fsSL -o "$deb_path" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
  run_root_logged "Install Google Chrome" apt install -y "$deb_path"
}

install_chrome() {
  case "$PKG_FAMILY" in
    arch) install_chrome_arch ;;
    deb) install_chrome_deb ;;
  esac
}

install_discord_arch() {
  run_root_logged "Install Discord on Arch" pacman -S --needed --noconfirm discord
}

install_discord_deb() {
  local tmpdir deb_path

  tmpdir="$(mktemp -d)"
  deb_path="${tmpdir}/discord.deb"
  run_logged "Download Discord" curl -fL -o "$deb_path" "https://discord.com/api/download?platform=linux&format=deb"
  run_root_logged "Install Discord" apt install -y "$deb_path"
}

install_discord() {
  case "$PKG_FAMILY" in
    arch) install_discord_arch ;;
    deb) install_discord_deb ;;
  esac
}

install_calibre_arch() {
  run_root_logged "Ensure calibre is installed on Arch" pacman -S --needed --noconfirm calibre
}

install_calibre_deb() {
  run_root_logged "Install calibre from the official Linux installer" bash -lc "wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sh /dev/stdin"
}

install_calibre() {
  case "$PKG_FAMILY" in
    arch) install_calibre_arch ;;
    deb) install_calibre_deb ;;
  esac
}

install_rust_arch() {
  run_root_logged "Ensure rustup is installed on Arch" pacman -S --needed --noconfirm rustup
  run_target_shell_logged "Install Rust stable toolchain" "rustup default stable && rustup component add clippy rustfmt"
}

install_rust_deb() {
  run_target_shell_logged "Install Rustup stable" "if [ ! -x '$TARGET_HOME/.cargo/bin/rustup' ]; then curl https://sh.rustup.rs -sSf | sh -s -- -y --profile default --default-toolchain stable; fi"
  run_target_shell_logged "Install Rust stable components" "source '$TARGET_HOME/.cargo/env' && rustup component add clippy rustfmt"
}

install_rust() {
  case "$PKG_FAMILY" in
    arch) install_rust_arch ;;
    deb) install_rust_deb ;;
  esac
}

install_shell_tooling_arch() {
  run_root_logged "Install pyenv build dependencies on Arch" pacman -S --needed --noconfirm "${PYENV_ARCH_BUILD_DEPS[@]}"
}

install_shell_tooling_deb() {
  run_root_logged "Install pyenv build dependencies on Debian/Ubuntu" apt-get install -y "${PYENV_DEB_BUILD_DEPS[@]}"
}

install_shell_tooling() {
  local zsh_path current_shell

  case "$PKG_FAMILY" in
    arch) install_shell_tooling_arch ;;
    deb) install_shell_tooling_deb ;;
  esac

  zsh_path="$(command -v zsh)"
  [ -n "$zsh_path" ] || return 1

  if [ ! -d "${TARGET_HOME}/.oh-my-zsh" ]; then
    ensure_target_file "${TARGET_HOME}/.zshrc"
    run_target_shell_logged "Install Oh My Zsh" "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"
  fi

  current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  if [ "$current_shell" != "$zsh_path" ]; then
    if confirm_yes "Make ${zsh_path} the default shell for ${TARGET_USER}?"; then
      run_root_logged "Set default shell to zsh" chsh -s "$zsh_path" "$TARGET_USER"
    fi
  fi

  if [ ! -d "${TARGET_HOME}/.nvm" ]; then
    run_target_shell_logged "Install nvm" "PROFILE=/dev/null bash -lc 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash'"
  fi

  run_target_shell_logged "Install latest Node LTS via nvm" "export NVM_DIR='$TARGET_HOME/.nvm'; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install --lts; nvm alias default 'lts/*'"

  if [ ! -d "${TARGET_HOME}/.pyenv" ]; then
    run_target_shell_logged "Install pyenv" "curl -fsSL https://pyenv.run | bash"
  fi
}

install_codex_cli() {
  run_target_shell_logged "Install Codex CLI" "export NVM_DIR='$TARGET_HOME/.nvm'; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install --lts; nvm use --lts; npm install -g @openai/codex"
}

install_mold_arch() {
  run_root_logged "Ensure mold is installed on Arch" pacman -S --needed --noconfirm mold
}

install_mold_from_source() {
  local tmpdir tag archive srcdir json

  tmpdir="$(mktemp -d)"
  run_root_logged "Install mold build dependencies" apt-get install -y "${MOLD_BUILD_DEPS[@]}"

  json="$(curl -fsSL https://api.github.com/repos/rui314/mold/releases/latest)"
  tag="$(printf '%s' "$json" | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$tag" ] || return 1

  archive="${tmpdir}/mold-${tag}.tar.gz"
  run_logged "Download mold ${tag}" curl -fsSL -o "$archive" "https://github.com/rui314/mold/archive/refs/tags/${tag}.tar.gz"
  run_logged "Extract mold sources" tar -xzf "$archive" -C "$tmpdir"
  srcdir="$(find "$tmpdir" -maxdepth 1 -type d -name 'mold-*' | head -n1)"
  [ -n "$srcdir" ] || return 1

  run_logged "Configure mold build" bash -lc "cd '$srcdir' && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++"
  run_logged "Build mold" bash -lc "cd '$srcdir' && cmake --build build -j'$(nproc)'"
  run_root_logged "Install mold" bash -lc "cd '$srcdir' && cmake --install build"
}

install_mold_deb() {
  if apt-cache show mold >/dev/null 2>&1; then
    run_root_logged "Install mold from apt" apt-get install -y mold
  else
    warn "mold is not available from apt on this system. Falling back to a source build."
    install_mold_from_source
  fi
}

install_mold() {
  case "$PKG_FAMILY" in
    arch) install_mold_arch ;;
    deb) install_mold_deb ;;
  esac
}

install_slippi_from_source() {
  local custom_env

  custom_env="${ROOT_DIR}/dotfiles/oh-my-zsh-custom/.oh-my-zsh/custom/bootstrap-env.zsh"
  [ -f "$custom_env" ] || die "Missing zsh custom environment file: ${custom_env}"

  run_target_shell_logged "Clone or update Slippi Launcher source" "mkdir -p '$TARGET_HOME/.local/src'; if [ -d '$TARGET_HOME/.local/src/slippi-launcher/.git' ]; then git -C '$TARGET_HOME/.local/src/slippi-launcher' pull --ff-only; else git clone https://github.com/project-slippi/slippi-launcher.git '$TARGET_HOME/.local/src/slippi-launcher'; fi"
  run_target_shell_logged "Build Slippi Launcher from source" "export NVM_DIR='$TARGET_HOME/.nvm'; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install --lts; nvm use --lts; cd '$TARGET_HOME/.local/src/slippi-launcher'; npm install; npm run package"
  run_target_shell_logged "Install Slippi Launcher into ~/.local/opt" "set -e; src='$TARGET_HOME/.local/src/slippi-launcher/release/build'; dest='$TARGET_HOME/.local/opt/slippi-launcher'; rm -rf \"\$dest/current\"; mkdir -p \"\$dest\" '$TARGET_HOME/.local/share/icons/hicolor/512x512/apps'; if [ -d \"\$src/linux-unpacked\" ]; then cp -a \"\$src/linux-unpacked\" \"\$dest/current\"; elif appimage=\$(find \"\$src\" -maxdepth 1 -type f -name '*.AppImage' | head -n1); [ -n \"\${appimage:-}\" ]; then mkdir -p \"\$dest/current\"; cp -a \"\$appimage\" \"\$dest/current/slippi-launcher.AppImage\"; chmod +x \"\$dest/current/slippi-launcher.AppImage\"; else echo 'No installable Slippi build artifact found.' >&2; exit 1; fi; if [ -f '$TARGET_HOME/.local/src/slippi-launcher/assets/icons/512x512.png' ]; then cp -f '$TARGET_HOME/.local/src/slippi-launcher/assets/icons/512x512.png' '$TARGET_HOME/.local/share/icons/hicolor/512x512/apps/slippi-launcher.png'; fi"
}

apply_dotfiles() {
  run_target_shell_logged "Apply Stow packages" "stamp=\$(date +%Y%m%d-%H%M%S); for file in '$TARGET_HOME/.zshrc' '$TARGET_HOME/.codex/config.toml' '$TARGET_HOME/.codex/rules/default.rules'; do if [ -e \"\$file\" ] && [ ! -L \"\$file\" ]; then mv \"\$file\" \"\$file.pre-stow-\$stamp\"; fi; done; cd '$ROOT_DIR/dotfiles' && stow -R -t '$TARGET_HOME' tmux i3 i3status bin cargo oh-my-zsh-custom applications x zsh codex; mkdir -p '$TARGET_HOME/.config'; nvim_target='$ROOT_DIR/dotfiles/nvim'; nvim_link='$TARGET_HOME/.config/nvim'; if [ -e \"\$nvim_link\" ] || [ -L \"\$nvim_link\" ]; then current=\$(readlink -f \"\$nvim_link\" || true); if [ \"\$current\" != \"\$nvim_target\" ]; then mv \"\$nvim_link\" \"\$nvim_link.pre-stow-\$stamp\"; ln -s \"\$nvim_target\" \"\$nvim_link\"; fi; else ln -s \"\$nvim_target\" \"\$nvim_link\"; fi"
}

enable_core_services() {
  if [ "$IS_CONTAINER" -eq 1 ]; then
    log "Container detected; skipping service enablement."
    return 0
  fi

  case "$PKG_FAMILY" in
    arch)
      run_root_logged "Enable NetworkManager" systemctl enable --now NetworkManager
      run_root_logged "Enable Bluetooth" systemctl enable --now bluetooth
      run_root_logged "Enable power-profiles-daemon" systemctl enable --now power-profiles-daemon
      ;;
    deb)
      run_root_logged "Enable NetworkManager" systemctl enable --now NetworkManager
      run_root_logged "Enable Bluetooth" systemctl enable --now bluetooth
      run_root_logged "Enable power-profiles-daemon" systemctl enable --now power-profiles-daemon
      ;;
  esac
}

configure_laptop_power() {
  [ "$IS_LAPTOP" -eq 1 ] || return 0

  run_root_logged "Enable NetworkManager" systemctl enable --now NetworkManager
  run_root_logged "Enable Bluetooth" systemctl enable --now bluetooth
  run_root_logged "Enable power-profiles-daemon" systemctl enable --now power-profiles-daemon
  run_target_shell_logged "Set a battery-friendly default profile" "$TARGET_HOME/.local/bin/power-mode-auto || true"
}

resume_uuid_from_swap() {
  [ -n "$SWAP_NAME" ] || return 1
  [ "$SWAP_TYPE" = "partition" ] || return 1
  blkid -s UUID -o value "$SWAP_NAME"
}

configure_hibernate() {
  local resume_uuid resume_arg logind_tmp logind_dir logind_file

  [ "$IS_LAPTOP" -eq 1 ] || return 0
  [ -n "$SWAP_NAME" ] || die "No swap detected. Hibernation needs swap."
  [ "$SWAP_TYPE" = "partition" ] || die "Only swap partitions are handled automatically right now. Detected: ${SWAP_TYPE}"

  if [ "$SWAP_SIZE_BYTES" -lt "$MEM_TOTAL_BYTES" ]; then
    warn "Swap is smaller than RAM. Hibernation may fail."
    if ! confirm_yes "Continue configuring hibernation anyway?"; then
      return 1
    fi
  fi

  resume_uuid="$(resume_uuid_from_swap)"
  [ -n "$resume_uuid" ] || return 1
  resume_arg="resume=UUID=${resume_uuid}"

  logind_dir="/etc/systemd/logind.conf.d"
  logind_file="${logind_dir}/99-lid-switch.conf"
  logind_tmp="$(mktemp)"
  cat >"$logind_tmp" <<'EOF'
[Login]
HandleLidSwitch=hibernate
HandleLidSwitchExternalPower=hibernate
HandleLidSwitchDocked=ignore
EOF
  run_root_logged "Create ${logind_dir}" mkdir -p "$logind_dir"
  run_root_logged "Install ${logind_file}" install -m 0644 "$logind_tmp" "$logind_file"
  rm -f "$logind_tmp"

  case "$PKG_FAMILY" in
    arch)
      if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -Eq '(^|[[:space:]])resume($|[[:space:]])' /etc/mkinitcpio.conf; then
          run_root_logged "Enable resume hook in mkinitcpio" sed -i -E 's/\bfilesystems\b/resume filesystems/' /etc/mkinitcpio.conf
        fi
        run_root_logged "Rebuild initramfs" mkinitcpio -P
      else
        warn "mkinitcpio was not found. Resume hook was not updated."
      fi
      ;;
    deb)
      local resume_tmp
      resume_tmp="$(mktemp)"
      printf 'RESUME=UUID=%s\n' "$resume_uuid" >"$resume_tmp"
      run_root_logged "Install /etc/initramfs-tools/conf.d/resume" install -m 0644 "$resume_tmp" /etc/initramfs-tools/conf.d/resume
      rm -f "$resume_tmp"
      run_root_logged "Rebuild initramfs" update-initramfs -u -k all
      ;;
  esac

  if [ -f /etc/default/grub ]; then
    ensure_grub_kernel_arg "$resume_arg"
    if command -v update-grub >/dev/null 2>&1; then
      run_root_logged "Regenerate GRUB config" update-grub
    else
      run_root_logged "Regenerate GRUB config" grub-mkconfig -o /boot/grub/grub.cfg
    fi
  elif [ -d /boot/loader/entries ]; then
    ensure_loader_entry_arg "$resume_arg"
  else
    warn "No supported bootloader config was found. Resume kernel arg was not persisted."
  fi

  run_root_logged "Restart systemd-logind" systemctl restart systemd-logind
}

maybe_laptop_tasks() {
  if [ "$IS_LAPTOP" -ne 1 ]; then
    log
    log "Laptop-specific tasks skipped because no battery-backed system was detected."
    return 0
  fi

  task "Configure laptop power defaults" configure_laptop_power diagnose_services

  if [ -z "$SWAP_NAME" ]; then
    warn "No swap detected. The hibernate-on-lid-close step will be skipped."
    return 0
  fi

  task "Configure hibernate on lid close" configure_hibernate diagnose_hibernate
}

post_summary() {
  log
  log "Bootstrap finished."
  log "- Logs: ${LOG_DIR}"
  log "- Re-login before testing Cargo's mold config or JAVA_HOME."
  log "- In i3, nm-applet handles clickable Wi-Fi from the tray."
}

main() {
  require_linux
  detect_container
  detect_distro
  detect_laptop
  detect_swap
  print_summary

  case "$PKG_FAMILY" in
    arch)
      task "Refresh Arch packages" refresh_arch diagnose_packages
      task "Install common Arch packages" install_common_arch diagnose_packages
      ;;
    deb)
      task "Refresh apt metadata" refresh_deb diagnose_packages
      task "Install common Debian/Ubuntu packages" install_common_deb diagnose_packages
      ;;
  esac

  task "Install zsh, Oh My Zsh, nvm, and pyenv" install_shell_tooling diagnose_shell_tooling
  task "Install Codex CLI" install_codex_cli diagnose_codex_cli
  task "Install OpenJDK 25" install_java diagnose_java
  task "Install mold" install_mold diagnose_mold
  task "Install Rust toolchain" install_rust diagnose_rust
  task "Build and install Slippi Launcher from source" install_slippi_from_source diagnose_slippi
  task "Install Google Chrome" install_chrome diagnose_chrome
  task "Install Discord" install_discord diagnose_discord
  task "Install calibre" install_calibre diagnose_calibre
  task "Enable core services" enable_core_services diagnose_services
  task "Apply dotfiles with Stow" apply_dotfiles diagnose_dotfiles
  maybe_laptop_tasks
  post_summary
}

main "$@"
